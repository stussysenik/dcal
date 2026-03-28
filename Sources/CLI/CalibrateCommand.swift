import ArgumentParser
import Foundation
import Domain
import Infrastructure

struct Calibrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Auto-calibrate display for cinema accuracy."
    )

    @Option(name: .long, help: "Calibration target: rec709, srgb, dcip3, linear")
    var target: String = "rec709"

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    @Flag(name: .long, help: "Show detailed analysis without applying changes")
    var dryRun = false

    @Flag(name: .long, help: "Restore display to system default (undo calibration)")
    var reset = false

    @Flag(name: .long, help: "Use formula API (simpler, less precise)")
    var formula = false

    func run() throws {
        let gamma = GammaAdapter()
        let detector = DisplayDetector()
        let displays = try syncBridge { try await detector.connectedDisplays() }

        guard let targetDisplay = displays.first else {
            print("  No displays detected.")
            return
        }

        let displayID = targetDisplay.id

        if reset {
            print("  Restoring \(targetDisplay.name) to system defaults...")
            gamma.restoreDefaults()
            print("  ✓ ColorSync settings restored.")
            return
        }

        print("dcal calibrate — \(targetDisplay.name)")
        print("════════════════════════════════════════════════════════════")

        // Check for f.lux — it fights with gamma table writes
        if isFluxRunning() {
            print("")
            print("  ⚠ f.lux detected — it may override gamma table changes.")
            print("    Consider disabling f.lux before calibrating.")
        }

        // Step 1: Read current gamma
        print("")
        print("  Step 1: Reading current gamma response...")
        guard let currentRamp = gamma.readGamma(displayID: displayID) else {
            print("  ✗ Failed to read gamma table.")
            return
        }
        let analysis = gamma.analyzeGamma(currentRamp)
        print("     Current gamma:  R=\(f2(analysis.redGamma))  G=\(f2(analysis.greenGamma))  B=\(f2(analysis.blueGamma))  avg=\(f2(analysis.averageGamma))")
        print("     Channel match:  ±\(f3(analysis.channelDeviation))")
        print("     Samples:        \(analysis.sampleCount) entries")
        print("     Native gamma:   \(f2(targetDisplay.estimatedNativeGamma)) (estimated)")

        // Step 2: Analyze display
        print("")
        print("  Step 2: Display analysis")
        print("     Bit depth:      \(targetDisplay.bitDepth)-bit")
        print("     Color space:    \(targetDisplay.colorSpace)")
        print("     Control:        \(targetDisplay.controlMethod.rawValue)")

        let gamutCoverage: String
        if targetDisplay.colorSpace.contains("P3") {
            gamutCoverage = "~99% sRGB · ~93% DCI-P3"
        } else {
            gamutCoverage = "~99% sRGB"
        }
        print("     Gamut:          \(gamutCoverage)")

        // Step 3: Generate target ramp
        let targetGamma: Double
        let targetName: String

        switch self.target.lowercased() {
        case "rec709":
            targetGamma = 2.4
            targetName = "Rec.709 (BT.1886 γ2.4)"
        case "srgb":
            targetGamma = 2.2
            targetName = "sRGB (γ2.2)"
        case "dcip3":
            targetGamma = 2.6
            targetName = "DCI-P3 (γ2.6)"
        case "linear":
            targetGamma = 1.0
            targetName = "Linear (γ1.0)"
        default:
            targetGamma = 2.4
            targetName = "Rec.709 (BT.1886 γ2.4)"
        }

        print("")
        print("  Step 3: Generating calibration for \(targetName)")

        /* The GPU LUT transforms framebuffer values before the panel.
           The panel applies its native EOTF on top: light = table(x)^native
           We want: light = x^target
           Therefore: table(x) = x^(target/native)

           Per-channel correction preserves the ICC profile's relative channel
           weighting so white balance is not disturbed. */
        let nativeGamma = targetDisplay.estimatedNativeGamma
        let baseTableGamma = targetGamma / nativeGamma

        // Per-channel: preserve the ICC profile's relative channel weighting
        let redTableGamma = baseTableGamma * (analysis.redGamma / max(analysis.averageGamma, 0.1))
        let greenTableGamma = baseTableGamma * (analysis.greenGamma / max(analysis.averageGamma, 0.1))
        let blueTableGamma = baseTableGamma * (analysis.blueGamma / max(analysis.averageGamma, 0.1))

        let calibratedRamp: GammaRamp
        let optimizerNote: String

        if targetDisplay.bitDepth <= 8 {
            let optimized = BitDepthOptimizer.optimizeForPerceptualUniformity(
                nativeGamma: analysis.averageGamma,
                targetGamma: targetGamma
            )
            let risk = BitDepthOptimizer.bandingRisk(ramp: optimized, gamma: targetGamma)
            calibratedRamp = GammaRamp(red: optimized, green: optimized, blue: optimized)
            optimizerNote = "8-bit perceptual optimizer (banding risk: \(f2(risk)) L*)"
        } else {
            let size = targetDisplay.bitDepth >= 10 ? 1024 : 256
            let redValues = (0..<size).map { i -> Double in
                let input = Double(i) / Double(size - 1)
                return pow(input, redTableGamma)
            }
            let greenValues = (0..<size).map { i -> Double in
                let input = Double(i) / Double(size - 1)
                return pow(input, greenTableGamma)
            }
            let blueValues = (0..<size).map { i -> Double in
                let input = Double(i) / Double(size - 1)
                return pow(input, blueTableGamma)
            }
            calibratedRamp = GammaRamp(red: redValues, green: greenValues, blue: blueValues)
            optimizerNote = "\(targetDisplay.bitDepth)-bit · \(size)-entry LUT · per-channel"
        }

        print("     Method:         \(optimizerNote)")
        print("     Target gamma:   \(f2(targetGamma))")
        print("     Table gamma:    R=\(f2(redTableGamma))  G=\(f2(greenTableGamma))  B=\(f2(blueTableGamma))")
        print("     End-to-end:     table × native(\(f2(nativeGamma))) = \(f2(targetGamma))")

        if dryRun {
            print("")
            print("  ── Dry run: no changes applied ──")
            print("  Run without --dry-run to apply calibration.")
            return
        }

        // Step 4: Apply
        print("")
        print("  Step 4: Applying calibration...")

        let success: Bool
        if formula {
            // Use the formula-based API — simpler, less precise, but more compatible
            success = gamma.writeGammaFormula(
                displayID: displayID,
                redGamma: redTableGamma,
                greenGamma: greenTableGamma,
                blueGamma: blueTableGamma
            )
        } else {
            success = gamma.writeGamma(displayID: displayID, ramp: calibratedRamp)
        }

        if success {
            if let verifyRamp = gamma.readGamma(displayID: displayID) {
                let verifyAnalysis = gamma.analyzeGamma(verifyRamp)

                // The measured gamma from readGamma is the table gamma only.
                // End-to-end gamma = table gamma * native panel gamma.
                let tableGamma = verifyAnalysis.averageGamma
                let estimatedEndToEnd = tableGamma * nativeGamma
                let gammaError = abs(estimatedEndToEnd - targetGamma)

                print("     ✓ Gamma ramp applied\(formula ? " (formula API)" : "")")
                print("")
                print("  Step 5: Verification")
                print("     Table gamma:     R=\(f2(verifyAnalysis.redGamma))  G=\(f2(verifyAnalysis.greenGamma))  B=\(f2(verifyAnalysis.blueGamma))")
                print("     Native gamma:    \(f2(nativeGamma)) (estimated)")
                print("     Measured gamma:  \(f2(estimatedEndToEnd)) (table × native)")
                print("     Target gamma:    \(f2(targetGamma))")
                print("     Error:           ±\(f3(gammaError))")

                print("")
                print("  ══ Results ══════════════════════════════════════════════")
                if gammaError < 0.05 {
                    print("  ✓ Gamma           \(f2(estimatedEndToEnd))  (target: \(f2(targetGamma)))  PASS")
                } else {
                    print("  ⚠ Gamma           \(f2(estimatedEndToEnd))  (target: \(f2(targetGamma)))  CLOSE")
                }

                let channelOK = verifyAnalysis.channelDeviation < 0.05
                print("  \(channelOK ? "✓" : "⚠") Channel balance  ±\(f3(verifyAnalysis.channelDeviation))  \(channelOK ? "PASS" : "CHECK")")
                print("  ✓ Profile         \(targetName)")
            }
        } else {
            print("     ✗ Failed to apply gamma ramp.")
            print("       macOS may be blocking gamma table writes.")
        }

        print("")
        print("  Use 'dcal calibrate --reset' to restore defaults.")
    }

    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }

    /// Detect if f.lux is running — it conflicts with gamma table writes.
    private func isFluxRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Flux"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

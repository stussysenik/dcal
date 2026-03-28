/* AnalyzeCommand — inspect display calibration state without changing anything.
   Three modes:
   - Quick (default): gamma per channel, bit depth, color space, banding risk, recommendation.
   - Detailed (--detailed): gamut coverage, grayscale tracking, adjustments table, recommendations.
   - Export (--export): write CSV ramp data + MATLAB script to ~/.dcal/exports/<timestamp>/. */

import ArgumentParser
import Foundation
import Application
import Domain
import Infrastructure

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze display calibration state."
    )

    @Flag(name: .long, help: "Show detailed analysis with all parameters.")
    var detailed = false

    @Flag(name: .long, help: "Export data for MATLAB/external analysis.")
    var export = false

    func run() throws {
        let gammaAdapter = GammaAdapter()
        let detector = DisplayDetector()
        let displays = try syncBridge { try await detector.connectedDisplays() }

        guard let display = displays.first else {
            print("  No displays detected.")
            return
        }

        let displayID = display.id

        guard let ramp = gammaAdapter.readGamma(displayID: displayID) else {
            print("  ✗ Failed to read gamma table for \(display.name).")
            return
        }

        let analysis = gammaAdapter.analyzeGamma(ramp)

        if export {
            try runExport(display: display, ramp: ramp, analysis: analysis)
            return
        }

        // ── Header ──────────────────────────────────────────────────────
        print("dcal analyze — \(display.name)")
        print("════════════════════════════════════════════════════════════")

        // ── Quick mode (always shown) ───────────────────────────────────
        print("")
        print("  Gamma Response")
        print("     Red:            \(f2(analysis.redGamma))")
        print("     Green:          \(f2(analysis.greenGamma))")
        print("     Blue:           \(f2(analysis.blueGamma))")
        print("     Average:        \(f2(analysis.averageGamma))")
        print("     Channel match:  ±\(f3(analysis.channelDeviation))")
        if analysis.isLinear {
            print("     Note:           Table is effectively linear (identity)")
        }

        print("")
        print("  Display Properties")
        print("     Bit depth:      \(display.bitDepth)-bit")
        print("     Color space:    \(display.colorSpace)")
        print("     ICC profile:    \(display.iccProfile)")
        print("     Native gamma:   \(f2(display.estimatedNativeGamma)) (estimated)")

        // Banding risk
        let bandingRisk = BitDepthOptimizer.bandingRisk(ramp: ramp.red, gamma: analysis.averageGamma)
        print("")
        print("  Banding Risk")
        print("     Max L* gap:     \(f2(bandingRisk))")
        if bandingRisk < 0.5 {
            print("     Assessment:     Excellent — invisible to all observers")
        } else if bandingRisk < 1.0 {
            print("     Assessment:     Good — at threshold of visibility")
        } else if bandingRisk < 2.0 {
            print("     Assessment:     Fair — may be visible in smooth gradients")
        } else {
            print("     Assessment:     Poor — banding likely visible in shadows")
        }

        // End-to-end gamma estimate
        let endToEnd = analysis.averageGamma * display.estimatedNativeGamma
        print("")
        print("  End-to-End Gamma")
        print("     Table × native: \(f2(analysis.averageGamma)) × \(f2(display.estimatedNativeGamma)) = \(f2(endToEnd))")

        // Recommendation
        print("")
        print("  ── Recommendation ──")
        let recommendation = generateRecommendation(
            analysis: analysis,
            display: display,
            endToEnd: endToEnd,
            bandingRisk: bandingRisk
        )
        print("  \(recommendation)")

        // ── Detailed mode ───────────────────────────────────────────────
        if detailed {
            printDetailedAnalysis(
                display: display,
                ramp: ramp,
                analysis: analysis,
                endToEnd: endToEnd,
                bandingRisk: bandingRisk
            )
        }

        print("")
    }

    // MARK: - Detailed Analysis

    private func printDetailedAnalysis(
        display: DisplayInfo,
        ramp: GammaRamp,
        analysis: GammaAnalysis,
        endToEnd: Double,
        bandingRisk: Double
    ) {
        // Gamut coverage estimate
        print("")
        print("  ── Detailed Analysis ──────────────────────────────────────")

        print("")
        print("  Gamut Coverage (estimated)")
        if display.colorSpace.contains("P3") {
            print("     sRGB:           ~99%")
            print("     DCI-P3:         ~93%")
            print("     Rec. 2020:      ~70%")
        } else if display.colorSpace.contains("Adobe") {
            print("     sRGB:           ~99%")
            print("     Adobe RGB:      ~95%")
            print("     DCI-P3:         ~85%")
        } else {
            print("     sRGB:           ~99%")
            print("     DCI-P3:         ~75%")
        }

        // Grayscale tracking analysis
        print("")
        print("  Grayscale Tracking")
        let redBias = analysis.redGamma - analysis.averageGamma
        let greenBias = analysis.greenGamma - analysis.averageGamma
        let blueBias = analysis.blueGamma - analysis.averageGamma
        print("     Red bias:       \(signedF3(redBias))")
        print("     Green bias:     \(signedF3(greenBias))")
        print("     Blue bias:      \(signedF3(blueBias))")

        if analysis.channelDeviation < 0.02 {
            print("     Tracking:       Excellent — neutral gray ramp")
        } else if analysis.channelDeviation < 0.05 {
            print("     Tracking:       Good — minor color cast")
        } else {
            let dominantChannel: String
            if redBias > greenBias && redBias > blueBias { dominantChannel = "warm (red)" }
            else if blueBias > redBias && blueBias > greenBias { dominantChannel = "cool (blue)" }
            else { dominantChannel = "green tint" }
            print("     Tracking:       Fair — visible \(dominantChannel) cast in midtones")
        }

        // Available adjustments table
        print("")
        print("  Available Adjustments")
        print("     ┌────────────────────┬──────────┬────────────────────┐")
        print("     │ Adjustment         │ Fidelity │ Method             │")
        print("     ├────────────────────┼──────────┼────────────────────┤")
        print("     │ Gamma correction   │ High     │ GPU LUT            │")
        print("     │ White balance      │ High     │ Per-channel LUT    │")
        if display.bitDepth <= 8 {
            print("     │ Banding reduction  │ Medium   │ Perceptual remap   │")
        }
        if display.isControllable {
            print("     │ Brightness         │ Native   │ \(display.controlMethod.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) │")
            if display.controlMethod == .ddcCI {
                print("     │ Contrast           │ Native   │ DDC/CI             │")
            }
        }
        print("     └────────────────────┴──────────┴────────────────────┘")

        // Specific recommendations
        print("")
        print("  Recommendations")
        var recNum = 1

        if abs(endToEnd - 2.4) > 0.1 {
            print("     \(recNum). Run 'dcal calibrate --target rec709' for BT.1886 compliance")
            recNum += 1
        }
        if analysis.channelDeviation > 0.03 {
            print("     \(recNum). Per-channel calibration will improve grayscale neutrality")
            recNum += 1
        }
        if bandingRisk > 1.0 && display.bitDepth <= 8 {
            print("     \(recNum). Enable perceptual optimizer to reduce shadow banding")
            recNum += 1
        }
        if display.bitDepth < 10 {
            print("     \(recNum). Consider 10-bit output mode for smoother gradients")
            recNum += 1
        }
        if recNum == 1 {
            print("     Display looks well-calibrated. No immediate action needed.")
        }
    }

    // MARK: - Export Mode

    private func runExport(display: DisplayInfo, ramp: GammaRamp, analysis: GammaAnalysis) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let exportDir = NSHomeDirectory() + "/.dcal/exports/\(timestamp)"
        try FileManager.default.createDirectory(
            atPath: exportDir,
            withIntermediateDirectories: true
        )

        // Write gamma ramp CSV
        let csvPath = exportDir + "/gamma_ramp.csv"
        var csvContent = "index,input,red,green,blue\n"
        for i in 0..<ramp.count {
            let input = Double(i) / Double(max(ramp.count - 1, 1))
            csvContent += "\(i),\(f6(input)),\(f6(ramp.red[i])),\(f6(ramp.green[i])),\(f6(ramp.blue[i]))\n"
        }
        try csvContent.write(toFile: csvPath, atomically: true, encoding: .utf8)

        // Write analysis summary CSV
        let summaryPath = exportDir + "/analysis.csv"
        var summaryContent = "parameter,value\n"
        summaryContent += "display_name,\(display.name)\n"
        summaryContent += "bit_depth,\(display.bitDepth)\n"
        summaryContent += "color_space,\(display.colorSpace)\n"
        summaryContent += "icc_profile,\(display.iccProfile)\n"
        summaryContent += "native_gamma,\(f6(display.estimatedNativeGamma))\n"
        summaryContent += "red_gamma,\(f6(analysis.redGamma))\n"
        summaryContent += "green_gamma,\(f6(analysis.greenGamma))\n"
        summaryContent += "blue_gamma,\(f6(analysis.blueGamma))\n"
        summaryContent += "average_gamma,\(f6(analysis.averageGamma))\n"
        summaryContent += "channel_deviation,\(f6(analysis.channelDeviation))\n"
        summaryContent += "sample_count,\(analysis.sampleCount)\n"
        try summaryContent.write(toFile: summaryPath, atomically: true, encoding: .utf8)

        // Write MATLAB verification script
        let matlabPath = exportDir + "/verify_gamma.m"
        let matlabScript = """
        %% dcal gamma ramp verification — \(timestamp)
        %% Auto-generated by dcal analyze --export

        data = readmatrix('gamma_ramp.csv', 'NumHeaderLines', 1);
        input = data(:, 2);
        red   = data(:, 3);
        green = data(:, 4);
        blue  = data(:, 5);

        %% Fit gamma per channel (log-log regression)
        valid = input > 0.01 & input < 0.99;
        logIn = log(input(valid));

        fitR = logIn \\ log(max(red(valid), 1e-6));
        fitG = logIn \\ log(max(green(valid), 1e-6));
        fitB = logIn \\ log(max(blue(valid), 1e-6));

        fprintf('Fitted gamma — R: %.4f  G: %.4f  B: %.4f\\n', fitR, fitG, fitB);

        %% Plot
        figure('Name', 'dcal Gamma Ramp Analysis');

        subplot(2, 1, 1);
        plot(input, red, 'r-', input, green, 'g-', input, blue, 'b-', ...
             input, input, 'k--', 'LineWidth', 1.2);
        xlabel('Input'); ylabel('Output');
        title('Gamma Ramp (per channel)');
        legend('Red', 'Green', 'Blue', 'Identity', 'Location', 'southeast');
        grid on;

        subplot(2, 1, 2);
        deviation = (red + green + blue) / 3 - input;
        plot(input, deviation, 'k-', 'LineWidth', 1.2);
        xlabel('Input'); ylabel('Deviation from identity');
        title('Ramp Deviation');
        grid on;

        sgtitle(sprintf('dcal — \\\\gamma_{avg} = %.3f', (fitR + fitG + fitB) / 3));
        """
        try matlabScript.write(toFile: matlabPath, atomically: true, encoding: .utf8)

        print("dcal analyze --export")
        print("════════════════════════════════════════════════════════════")
        print("")
        print("  Exported to: \(exportDir)/")
        print("")
        print("  Files:")
        print("     gamma_ramp.csv    \(ramp.count) samples, RGB channels")
        print("     analysis.csv      Display parameters & gamma fit")
        print("     verify_gamma.m    MATLAB verification script")
        print("")
        print("  In MATLAB:")
        print("     cd '\(exportDir)'")
        print("     verify_gamma")
    }

    // MARK: - Recommendation

    private func generateRecommendation(
        analysis: GammaAnalysis,
        display: DisplayInfo,
        endToEnd: Double,
        bandingRisk: Double
    ) -> String {
        // Prioritize the most impactful issue
        if analysis.isLinear && display.estimatedNativeGamma < 1.5 {
            return "Display appears to have a linear response. Run 'dcal calibrate' to apply a target curve."
        }

        let gammaOff = abs(endToEnd - 2.2)
        let rec709Off = abs(endToEnd - 2.4)

        if gammaOff < 0.05 && analysis.channelDeviation < 0.03 {
            return "Display is well-calibrated for sRGB (γ2.2). No action needed."
        }
        if rec709Off < 0.05 && analysis.channelDeviation < 0.03 {
            return "Display is well-calibrated for Rec.709 (γ2.4). No action needed."
        }

        if analysis.channelDeviation > 0.1 {
            return "Significant channel imbalance detected. Run 'dcal calibrate' to correct white balance."
        }

        if bandingRisk > 2.0 && display.bitDepth <= 8 {
            return "High banding risk in shadows. Run 'dcal calibrate' with perceptual optimizer."
        }

        if gammaOff > 0.15 {
            return "Gamma is \(f2(endToEnd)), run 'dcal calibrate --target srgb' or '--target rec709'."
        }

        return "Display is in reasonable shape. Run 'dcal calibrate' for precision calibration."
    }

    // MARK: - Formatting

    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func f6(_ v: Double) -> String { String(format: "%.6f", v) }
    private func signedF3(_ v: Double) -> String {
        v >= 0 ? "+\(f3(v))" : f3(v)
    }
}

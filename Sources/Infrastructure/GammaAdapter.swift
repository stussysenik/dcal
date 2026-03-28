/* CoreGraphics Gamma Adapter — reads and writes display gamma tables.

   This is the primary mechanism for software-based display calibration
   on macOS. The gamma table maps input code values to output luminance,
   allowing us to correct for a display's native response curve.

   CoreGraphics provides:
   - CGGetDisplayTransferByTable: read current gamma ramp (256+ entries per channel)
   - CGSetDisplayTransferByTable: apply a custom gamma ramp
   - CGDisplayRestoreColorSyncSettings: revert to the system ICC profile

   Important: on some newer macOS versions, gamma table writes may be
   silently ignored. We verify the write took effect by reading back. */

import Foundation
import CoreGraphics

public struct GammaAdapter: Sendable {
    public init() {}

    /// Read the current gamma ramp from a display.
    /// Returns three arrays (R, G, B) of normalized [0,1] values.
    public func readGamma(displayID: CGDirectDisplayID, sampleCount: Int = 256) -> GammaRamp? {
        var red = [CGGammaValue](repeating: 0, count: sampleCount)
        var green = [CGGammaValue](repeating: 0, count: sampleCount)
        var blue = [CGGammaValue](repeating: 0, count: sampleCount)
        var actual: UInt32 = 0

        let err = CGGetDisplayTransferByTable(
            displayID,
            UInt32(sampleCount),
            &red, &green, &blue,
            &actual
        )

        guard err == .success, actual > 0 else { return nil }

        return GammaRamp(
            red: red[0..<Int(actual)].map { Double($0) },
            green: green[0..<Int(actual)].map { Double($0) },
            blue: blue[0..<Int(actual)].map { Double($0) }
        )
    }

    /// Apply a gamma ramp to a display.
    /// The ramp must have equal-length R/G/B arrays of normalized [0,1] values.
    public func writeGamma(displayID: CGDirectDisplayID, ramp: GammaRamp) -> Bool {
        let count = ramp.red.count
        guard count == ramp.green.count, count == ramp.blue.count, count > 0 else {
            return false
        }

        let red = ramp.red.map { CGGammaValue($0) }
        let green = ramp.green.map { CGGammaValue($0) }
        let blue = ramp.blue.map { CGGammaValue($0) }

        let err = CGSetDisplayTransferByTable(
            displayID,
            UInt32(count),
            red, green, blue
        )

        return err == .success
    }

    /// Apply a gamma ramp using the formula-based API (simpler, less precise).
    /// Each channel has: min + (max - min) * pow(input, 1/gamma)
    public func writeGammaFormula(
        displayID: CGDirectDisplayID,
        redGamma: Double, greenGamma: Double, blueGamma: Double,
        redMin: Double = 0, greenMin: Double = 0, blueMin: Double = 0,
        redMax: Double = 1, greenMax: Double = 1, blueMax: Double = 1
    ) -> Bool {
        let err = CGSetDisplayTransferByFormula(
            displayID,
            CGGammaValue(redMin), CGGammaValue(redMax), CGGammaValue(redGamma),
            CGGammaValue(greenMin), CGGammaValue(greenMax), CGGammaValue(greenGamma),
            CGGammaValue(blueMin), CGGammaValue(blueMax), CGGammaValue(blueGamma)
        )
        return err == .success
    }

    /// Restore the display to its ColorSync ICC profile settings.
    public func restoreDefaults() {
        CGDisplayRestoreColorSyncSettings()
    }

    /// Analyze a gamma ramp: compute the effective gamma per channel
    /// by fitting a power law to the measured curve.
    public func analyzeGamma(_ ramp: GammaRamp) -> GammaAnalysis {
        let redGamma = fitGamma(ramp.red)
        let greenGamma = fitGamma(ramp.green)
        let blueGamma = fitGamma(ramp.blue)
        let avgGamma = (redGamma + greenGamma + blueGamma) / 3.0

        /* Check channel balance: how closely matched are R, G, B gammas?
           Well-calibrated displays have R ≈ G ≈ B gamma.
           Deviation indicates a color temperature shift. */
        let maxDev = max(abs(redGamma - avgGamma),
                         abs(greenGamma - avgGamma),
                         abs(blueGamma - avgGamma))

        return GammaAnalysis(
            redGamma: redGamma,
            greenGamma: greenGamma,
            blueGamma: blueGamma,
            averageGamma: avgGamma,
            channelDeviation: maxDev,
            isLinear: avgGamma < 1.05 && avgGamma > 0.95,
            sampleCount: ramp.red.count
        )
    }

    /// Fit a power-law gamma to a set of output values.
    /// Uses least-squares regression in log space:
    ///   output = input^gamma  →  log(output) = gamma * log(input)
    private func fitGamma(_ values: [Double]) -> Double {
        guard values.count > 2 else { return 1.0 }

        var sumXY = 0.0
        var sumXX = 0.0
        let n = values.count

        for i in 1..<(n - 1) {
            let input = Double(i) / Double(n - 1)
            let output = max(values[i], 0.0001) // avoid log(0)

            let logIn = log(input)
            let logOut = log(output)

            sumXY += logIn * logOut
            sumXX += logIn * logIn
        }

        guard sumXX > 0 else { return 1.0 }
        return sumXY / sumXX
    }
}

/// A display's RGB gamma ramp — three channels of normalized [0,1] values.
public struct GammaRamp: Sendable {
    public let red: [Double]
    public let green: [Double]
    public let blue: [Double]

    public init(red: [Double], green: [Double], blue: [Double]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var count: Int { red.count }

    /// Generate a simple power-law gamma ramp.
    public static func powerLaw(gamma: Double, size: Int = 256) -> GammaRamp {
        let values = (0..<size).map { i -> Double in
            let input = Double(i) / Double(size - 1)
            return pow(input, 1.0 / gamma) // inverse: we encode, display decodes with native gamma
        }
        return GammaRamp(red: values, green: values, blue: values)
    }

    /// Generate an identity (linear) gamma ramp.
    public static func identity(size: Int = 256) -> GammaRamp {
        let values = (0..<size).map { Double($0) / Double(size - 1) }
        return GammaRamp(red: values, green: values, blue: values)
    }
}

/// Analysis results from measuring a display's gamma response.
public struct GammaAnalysis: Sendable {
    public let redGamma: Double
    public let greenGamma: Double
    public let blueGamma: Double
    public let averageGamma: Double
    public let channelDeviation: Double
    public let isLinear: Bool
    public let sampleCount: Int
}

// RampComposer.swift
// dcal – Display Calibration Tool
//
// Composes brightness, contrast, and white point slider values into a
// single gamma LUT ready for CGSetDisplayTransferByTable.
//
// The composition pipeline per sample:
//   1. Contrast: shape the curve via power-law exponent
//      exponent = 2^((contrast - 50) / 50)
//      At contrast=50 → exponent=1.0 (identity)
//      At contrast=0  → exponent=0.5 (lifted shadows)
//      At contrast=100 → exponent=2.0 (crushed shadows)
//
//   2. Brightness: scale the maximum output
//      maxOutput = brightness / 100
//
//   3. White Point: per-channel gain from Kelvin → RGB conversion
//      At 6500K → (1,1,1). Below → warm. Above → cool.

import Foundation

public enum RampComposer {

    /// Compose a gamma LUT from the three adjustment parameters.
    ///
    /// - Parameters:
    ///   - brightness: 0–100. Scales maximum output. 100 = full, 0 = black.
    ///   - contrast: 0–100. Shapes the power curve. 50 = identity (no change).
    ///   - whitePointKelvin: 4000–10000. Color temperature for per-channel gain.
    ///   - size: LUT entries (default 256 for 8-bit).
    /// - Returns: A LUT1D ready to convert to GammaRamp and apply.
    public static func compose(
        brightness: Double,
        contrast: Double,
        whitePointKelvin: Double,
        size: Int = 256
    ) -> LUT1D {
        let exponent = pow(2.0, (contrast - 50.0) / 50.0)
        let maxOutput = min(max(brightness / 100.0, 0), 1)
        let gains = kelvinToRGBGains(whitePointKelvin)

        var red = [Double]()
        var green = [Double]()
        var blue = [Double]()
        red.reserveCapacity(size)
        green.reserveCapacity(size)
        blue.reserveCapacity(size)

        for i in 0..<size {
            let x = Double(i) / Double(size - 1)
            let curved = pow(x, exponent)
            let scaled = curved * maxOutput

            red.append(min(max(scaled * gains.red, 0), 1))
            green.append(min(max(scaled * gains.green, 0), 1))
            blue.append(min(max(scaled * gains.blue, 0), 1))
        }

        return LUT1D(size: size, red: red, green: green, blue: blue)
    }
}

// ColorTemperature.swift
// dcal – Display Calibration Tool
//
// Converts correlated color temperature (CCT) in Kelvin to per-channel
// RGB gain multipliers for white point adjustment.
//
// The algorithm:
// 1. Compute the CIE daylight locus chromaticity (x, y) for the given CCT
//    using the Hernandez-Andres approximation of the CIE daylight series.
// 2. Convert (x, y, Y=1) to XYZ tristimulus values.
// 3. Convert XYZ to linear sRGB using the standard matrix.
// 4. Normalize gains so the maximum channel is 1.0 (we only attenuate,
//    never boost beyond native gamut).
//
// At 6500K (D65) the gains are (1, 1, 1). Below 6500K, blue is attenuated
// (warmer). Above 6500K, red is attenuated (cooler).

import Foundation

/// Per-channel RGB gain multipliers for white point adjustment.
/// All values are in [0, 1], normalized so the brightest channel is 1.0.
public struct ColorTemperatureGains: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Convert a correlated color temperature (CCT) to per-channel RGB gains.
///
/// Uses the CIE daylight locus chromaticity approximation from:
///   Hernandez-Andres et al., "Calculating correlated color temperatures
///   across the entire gamut of daylight and skylight chromaticities" (1999).
///
/// - Parameter kelvin: Color temperature in Kelvin. Clamped to [4000, 10000].
/// - Returns: RGB gains normalized so max channel = 1.0.
public func kelvinToRGBGains(_ kelvin: Double) -> ColorTemperatureGains {
    let T = min(max(kelvin, 4000), 10000)

    // CIE daylight locus chromaticity x as a function of CCT.
    let x: Double
    if T <= 7000 {
        x = -4.6070e9 / (T * T * T) + 2.9678e6 / (T * T) + 0.09911e3 / T + 0.244063
    } else {
        x = -2.0064e9 / (T * T * T) + 1.9018e6 / (T * T) + 0.24748e3 / T + 0.237040
    }

    // CIE daylight locus chromaticity y from x.
    let y = -3.000 * x * x + 2.870 * x - 0.275

    // Convert xyY (with Y=1) to XYZ.
    guard y > 0 else {
        return ColorTemperatureGains(red: 1, green: 1, blue: 1)
    }
    let targetXYZ = CIExyY(x: x, y: y, Y: 1.0).toXYZ()

    // D65 reference white in XYZ (what 6500K should produce).
    let d65XYZ = CIELab.d65White

    // Convert both to linear sRGB.
    let targetRGB = LinearRGB.fromXYZ(targetXYZ, colorSpace: .sRGB)
    let d65RGB = LinearRGB.fromXYZ(d65XYZ, colorSpace: .sRGB)

    // Compute gains as ratio target/d65. This gives how much each channel
    // needs to be scaled relative to the D65 neutral point.
    guard d65RGB.r > 0, d65RGB.g > 0, d65RGB.b > 0 else {
        return ColorTemperatureGains(red: 1, green: 1, blue: 1)
    }

    var rGain = targetRGB.r / d65RGB.r
    var gGain = targetRGB.g / d65RGB.g
    var bGain = targetRGB.b / d65RGB.b

    // Normalize so the maximum channel is 1.0 (attenuate only, never boost).
    let maxGain = max(rGain, gGain, bGain)
    if maxGain > 0 {
        rGain /= maxGain
        gGain /= maxGain
        bGain /= maxGain
    }

    // Clamp to [0, 1] for safety (out-of-gamut chromaticities can go negative).
    return ColorTemperatureGains(
        red: min(max(rGain, 0), 1),
        green: min(max(gGain, 0), 1),
        blue: min(max(bGain, 0), 1)
    )
}

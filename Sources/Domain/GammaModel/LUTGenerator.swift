// LUTGenerator.swift
// dcal – Display Calibration Tool
//
// 1D Lookup Table (LUT) generation for display calibration.
//
// Why LUTs matter:
// A calibrated display doesn't change its panel hardware — it changes the signal
// sent to the panel. A 1D LUT sits between the GPU's frame buffer and the display
// input, remapping each code value so that the *combined* response of (LUT + panel)
// matches the desired transfer function.
//
// For example, if a display has a native gamma of 2.0 but the target is 2.4,
// the LUT pre-distorts the signal so that the end-to-end chain produces the
// correct 2.4 power-law response. The display "thinks" it's receiving normal
// input, but the LUT has already done the math.
//
// 1D LUTs operate per-channel (R, G, B independently). They cannot fix color
// crosstalk between channels — that requires a 3D LUT. But for gamma correction,
// white point adjustment, and per-channel response matching, 1D LUTs are both
// sufficient and computationally trivial.

import Foundation

// MARK: - LUT1D

/// A 1D lookup table for display calibration.
///
/// Each channel (red, green, blue) has an array of `size` entries, mapping
/// input code values to output code values. All values are normalized to [0, 1].
///
/// Common sizes:
/// - 256 entries: 8-bit displays (sRGB, consumer monitors)
/// - 1024 entries: 10-bit displays (professional broadcast monitors)
/// - 4096 entries: 12-bit displays (cinema reference monitors, DaVinci Resolve)
///
/// A LUT with all three channels identical is called a "monochrome" or "luminance"
/// LUT — it adjusts overall gamma without affecting color balance. When channels
/// differ, the LUT also corrects per-channel gamma to achieve a neutral gray ramp.
public struct LUT1D: Sendable, Equatable {

    /// Number of entries (typically 256 for 8-bit, 1024 for 10-bit, 4096 for 12-bit).
    public let size: Int

    /// Red channel table. Values normalized [0, 1].
    public let red: [Double]

    /// Green channel table. Values normalized [0, 1].
    public let green: [Double]

    /// Blue channel table. Values normalized [0, 1].
    public let blue: [Double]

    /// Creates a LUT with explicit per-channel tables.
    ///
    /// - Precondition: All three arrays must have the same length as `size`.
    public init(size: Int, red: [Double], green: [Double], blue: [Double]) {
        precondition(red.count == size, "Red channel count (\(red.count)) must equal size (\(size))")
        precondition(green.count == size, "Green channel count (\(green.count)) must equal size (\(size))")
        precondition(blue.count == size, "Blue channel count (\(blue.count)) must equal size (\(size))")
        self.size = size
        self.red = red
        self.green = green
        self.blue = blue
    }
}

// MARK: - LUT Generation

/// Functions for generating calibration LUTs.
///
/// The three generators cover the most common calibration scenarios:
///
/// 1. **Identity** — a "do nothing" LUT used as a baseline or reset.
/// 2. **Gamma** — a simple gamma correction for quick adjustments.
/// 3. **Calibration** — the full pipeline: undo the display's native response,
///    then apply the target response. This is what professional calibration
///    software computes after measuring the display with a colorimeter.
public enum LUTGenerator {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Identity LUT
    // ──────────────────────────────────────────────────────────────────────

    /// Generates a passthrough (identity) LUT — input equals output.
    ///
    /// An identity LUT is the starting point for any calibration workflow.
    /// Loading it into the display's LUT slot effectively disables any
    /// correction, returning the display to its native response.
    ///
    /// - Parameter size: Number of entries (e.g., 256 for 8-bit). Must be ≥ 2.
    /// - Returns: A LUT where every entry maps to itself.
    public static func generateIdentityLUT(size: Int) -> LUT1D {
        precondition(size >= 2, "LUT size must be at least 2")

        let table = (0 ..< size).map { i in
            Double(i) / Double(size - 1)
        }
        return LUT1D(size: size, red: table, green: table, blue: table)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Simple Gamma LUT
    // ──────────────────────────────────────────────────────────────────────

    /// Generates a simple gamma correction LUT.
    ///
    /// Applies `output = input^(1/gamma)` at each entry. This is the inverse
    /// power law — it pre-compensates so that a display with the given gamma
    /// produces a linear ramp.
    ///
    /// Use this for quick adjustments when you know the display's gamma but
    /// don't need full transfer-function matching.
    ///
    /// - Parameters:
    ///   - gamma: The gamma exponent to correct for. Must be > 0.
    ///   - size: Number of LUT entries. Must be ≥ 2.
    /// - Returns: A gamma correction LUT.
    public static func generateGammaLUT(gamma: Double, size: Int) -> LUT1D {
        precondition(size >= 2, "LUT size must be at least 2")
        precondition(gamma > 0, "Gamma must be positive")

        let inverseGamma = 1.0 / gamma
        let table = (0 ..< size).map { i in
            let normalized = Double(i) / Double(size - 1)
            return pow(normalized, inverseGamma)
        }
        return LUT1D(size: size, red: table, green: table, blue: table)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Calibration LUT (Transfer Function Mapping)
    // ──────────────────────────────────────────────────────────────────────

    /// Generates a calibration LUT that converts from one transfer function to another.
    ///
    /// This is the core of display calibration. The algorithm:
    ///
    /// 1. For each input code value V_in (normalized to [0, 1]):
    /// 2. Decode V_in through the **target** transfer function to get the desired
    ///    linear luminance L_target.
    /// 3. Encode L_target through the **source** (native) transfer function's
    ///    inverse to get the signal value V_out that will produce L_target on
    ///    the actual display.
    ///
    /// The result: when V_in passes through this LUT (producing V_out) and then
    /// through the display's native EOTF, the net effect matches the target EOTF.
    ///
    /// ```
    /// V_in → [LUT] → V_out → [Display Native EOTF] → L
    ///   ≡
    /// V_in → [Target EOTF] → L
    /// ```
    ///
    /// - Parameters:
    ///   - source: The display's native (measured) transfer function.
    ///   - target: The desired (target) transfer function.
    ///   - size: Number of LUT entries. Must be ≥ 2.
    /// - Returns: A calibration LUT that corrects the display's response.
    public static func generateCalibrationLUT(
        from source: TransferFunction,
        to target: TransferFunction,
        size: Int
    ) -> LUT1D {
        precondition(size >= 2, "LUT size must be at least 2")

        let table = (0 ..< size).map { i -> Double in
            let normalized = Double(i) / Double(size - 1)

            // Step 1: What linear luminance does the target curve want for this input?
            let targetLinear = target.decode(normalized)

            // Step 2: What signal must we send to the native display to get that luminance?
            let corrected = source.encode(targetLinear)

            // Clamp to valid signal range — the display can't go below black or above white.
            return min(max(corrected, 0.0), 1.0)
        }

        return LUT1D(size: size, red: table, green: table, blue: table)
    }
}

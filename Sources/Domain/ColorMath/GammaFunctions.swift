// ============================================================================
// GammaFunctions.swift — Electro-Optical & Opto-Electronic Transfer Functions
// ============================================================================
//
// WHY GAMMA EXISTS
// ----------------
// CRT monitors had a natural power-law response: light output ∝ voltage^2.5.
// Rather than fight this, the broadcast industry encoded signals with the
// inverse curve (γ ≈ 1/2.5 = 0.4), so the camera→CRT chain produced
// perceptually linear results.
//
// Modern displays are inherently linear (LCD, OLED) but still expect gamma-
// encoded signals because:
//   1. The entire content ecosystem is built around gamma encoding.
//   2. Gamma encoding efficiently allocates bits — it compresses highlights
//      (where the eye is less sensitive to differences) and expands shadows
//      (where small differences are visible). This is "perceptual quantization"
//      avant la lettre.
//
// TRANSFER FUNCTIONS IN THIS FILE
// --------------------------------
// sRGB (IEC 61966-2-1): Piecewise function — linear segment below 0.0031308,
//   power law with offset above. Nearly identical to a simple γ=2.2 curve
//   but with a defined linear toe to avoid infinite slope at zero.
//
// Simple power law: γ=2.2 (Rec.709 practical), γ=2.6 (DCI cinema), etc.
//
// NOT included here (future additions):
//   PQ (SMPTE ST 2084): Perceptual Quantizer for HDR, based on Barten model.
//   HLG (ARIB STD-B67): Hybrid Log-Gamma for HDR broadcast.
//   These are more complex and will live in their own files.
//
// TERMINOLOGY
// -----------
// "Compand" (compress + expand): The general term for applying a nonlinear
//   transfer function. "Companding" is the round-trip encode→decode process.
//
// OETF (Opto-Electronic Transfer Function): Scene light → signal value.
//   Applied by the camera (or content creator) during encoding.
//
// EOTF (Electro-Optical Transfer Function): Signal value → display light.
//   Applied by the display hardware (or our software) during decoding.
//
// For sRGB: sRGBCompand ≈ OETF, sRGBLinearize ≈ EOTF.
//
// ============================================================================

import Foundation

// MARK: - sRGB Transfer Function

/// Applies the sRGB companding function (OETF): linear light → sRGB signal.
///
/// Defined by IEC 61966-2-1 with a piecewise formula:
///
///   linear ≤ 0.0031308:  srgb = 12.92 × linear
///   linear > 0.0031308:  srgb = 1.055 × linear^(1/2.4) − 0.055
///
/// The linear segment prevents the curve from having infinite slope at zero,
/// which would cause noise amplification in dark regions. The crossover point
/// 0.0031308 is chosen so the two segments meet with C⁰ continuity (value match)
/// and near-C¹ continuity (slope nearly matches).
///
/// - Parameter linear: Linear light intensity, typically [0, 1].
///   Values outside this range are clamped for safety.
///
/// - Returns: sRGB-encoded signal value in [0, 1].
///
/// - Note: This function handles a single channel. Apply independently to R, G, B.
///   For full RGB conversion, first use `LinearRGB.fromXYZ()` to get linear values,
///   then apply this function to each channel.
public func sRGBCompand(_ linear: Double) -> Double {
    // Clamp to avoid NaN from negative inputs to pow().
    // Negative linear values indicate out-of-gamut colors.
    let v = max(0.0, min(1.0, linear))

    if v <= 0.0031308 {
        // Linear segment: slope = 12.92, matching the derivative of the
        // power segment at the crossover point.
        return 12.92 * v
    } else {
        // Power segment with offset. The exponent 1/2.4 ≈ 0.4167 is
        // close to but not exactly 1/2.2 ≈ 0.4545. The offset of 0.055
        // and the 1.055 multiplier ensure the curve passes through (0, 0)
        // in the linear segment and (1, 1) at full white.
        return 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
}

/// Applies the sRGB inverse companding function (EOTF): sRGB signal → linear light.
///
/// This is the inverse of `sRGBCompand()`:
///
///   srgb ≤ 0.04045:  linear = srgb / 12.92
///   srgb > 0.04045:  linear = ((srgb + 0.055) / 1.055)^2.4
///
/// The threshold 0.04045 = 12.92 × 0.0031308 is the image of the
/// companding crossover point.
///
/// Use this to convert sRGB pixel values (e.g., from an 8-bit image
/// where 128/255 ≈ 0.502) to linear light values for physically correct
/// math (compositing, color space conversion, lighting calculations).
///
/// - Parameter srgb: sRGB-encoded signal value, typically [0, 1].
///   Values outside this range are clamped.
///
/// - Returns: Linear light intensity in [0, 1].
public func sRGBLinearize(_ srgb: Double) -> Double {
    let v = max(0.0, min(1.0, srgb))

    if v <= 0.04045 {
        return v / 12.92
    } else {
        return pow((v + 0.055) / 1.055, 2.4)
    }
}

// MARK: - Simple Power-Law Gamma

/// Encodes a linear light value using a simple power-law gamma curve.
///
///   encoded = linear^(1/γ)
///
/// Common gamma values:
///   - γ = 2.2: Practical broadcast (Rec.709 approximation, Windows default)
///   - γ = 2.4: Dim surround viewing (BT.1886 reference EOTF)
///   - γ = 2.6: DCI cinema projection (SMPTE RP 431-2)
///   - γ = 1.8: Legacy Mac OS (pre-10.6)
///   - γ = 1.0: Linear (identity transform, no gamma)
///
/// - Parameters:
///   - linear: Linear light intensity, clamped to [0, 1].
///   - gamma: The gamma exponent (must be > 0).
///
/// - Returns: Gamma-encoded value in [0, 1].
///
/// - Note: Unlike sRGB, there is no linear toe segment. This means the
///   derivative at zero is infinite (for γ > 1), which can amplify noise
///   in very dark regions. Rec.709's official OETF adds a linear segment
///   similar to sRGB to avoid this, but in practice most implementations
///   use a simple power law.
public func gammaEncode(_ linear: Double, gamma: Double) -> Double {
    let v = max(0.0, min(1.0, linear))
    return pow(v, 1.0 / gamma)
}

/// Decodes a gamma-encoded value back to linear light using a power law.
///
///   linear = encoded^γ
///
/// This is the EOTF (display-side) operation: it converts the signal value
/// stored in the file/stream back to proportional light output.
///
/// - Parameters:
///   - encoded: Gamma-encoded signal value, clamped to [0, 1].
///   - gamma: The gamma exponent (must be > 0).
///
/// - Returns: Linear light intensity in [0, 1].
public func gammaDecode(_ encoded: Double, gamma: Double) -> Double {
    let v = max(0.0, min(1.0, encoded))
    return pow(v, gamma)
}

// MARK: - Rec.709 Transfer Function

/// Applies the Rec.709 OETF (ITU-R BT.709-6): linear → Rec.709 signal.
///
/// Piecewise definition:
///   linear < 0.018:  signal = 4.5 × linear
///   linear ≥ 0.018:  signal = 1.099 × linear^0.45 − 0.099
///
/// Nearly identical to sRGB in practice (the curves differ by less than
/// 0.001 across the entire range) but defined with different constants.
/// Rec.709 uses exponent 0.45 (≈ 1/2.222) vs. sRGB's 1/2.4 ≈ 0.4167.
///
/// - Parameter linear: Linear light intensity, clamped to [0, 1].
/// - Returns: Rec.709-encoded signal value in [0, 1].
public func rec709Encode(_ linear: Double) -> Double {
    let v = max(0.0, min(1.0, linear))

    if v < 0.018 {
        return 4.5 * v
    } else {
        return 1.099 * pow(v, 0.45) - 0.099
    }
}

/// Applies the Rec.709 inverse OETF: Rec.709 signal → linear light.
///
///   signal < 0.081:  linear = signal / 4.5
///   signal ≥ 0.081:  linear = ((signal + 0.099) / 1.099)^(1/0.45)
///
/// The threshold 0.081 = 4.5 × 0.018 is the image of the linear breakpoint.
///
/// - Parameter signal: Rec.709-encoded signal value, clamped to [0, 1].
/// - Returns: Linear light intensity in [0, 1].
public func rec709Decode(_ signal: Double) -> Double {
    let v = max(0.0, min(1.0, signal))

    if v < 0.081 {
        return v / 4.5
    } else {
        return pow((v + 0.099) / 1.099, 1.0 / 0.45)
    }
}

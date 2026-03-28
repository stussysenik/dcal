// TransferFunction.swift
// dcal – Display Calibration Tool
//
// Electro-Optical Transfer Functions (EOTFs) for professional display calibration.
// An EOTF describes how a display converts encoded signal values into visible light.
//
// Why this matters:
// Every pixel you see on screen passes through a transfer function. The display
// receives an encoded value (0–255 for 8-bit) and converts it to a luminance level.
// If you don't know the exact shape of this curve, you cannot calibrate the display.
// Different standards (sRGB, BT.1886, PQ, HLG) define different curves, each
// optimized for a specific viewing environment and content type.

import Foundation

// MARK: - TransferFunction

/// Represents a display's electro-optical transfer function (EOTF).
/// Maps encoded signal values [0,1] to linear light output [0,1].
///
/// The EOTF is the mathematical heart of display calibration. It answers the
/// question: "Given an encoded pixel value V, how much light L does the display
/// actually produce?"
///
/// - `decode(_ encoded:)` applies the EOTF:   encoded signal → linear light (V → L)
/// - `encode(_ linear:)` applies the inverse:  linear light → encoded signal (L → V)
public enum TransferFunction: Sendable, Equatable {

    /// Simple power law: L = V^gamma (most consumer displays).
    ///
    /// The original CRT phosphor response was approximately a power function with
    /// gamma ≈ 2.2–2.5. Modern LCDs emulate this curve for compatibility.
    /// A gamma of 2.2 is the de facto standard for general computing; 2.4 is
    /// used in dim viewing environments (broadcast, cinema).
    case powerLaw(gamma: Double)

    /// sRGB / IEC 61966-2-1 piecewise function.
    ///
    /// sRGB is the default colorspace of the internet and most consumer devices.
    /// It uses a piecewise function rather than a pure power law: a linear segment
    /// near black (to avoid an infinite slope at zero) joined to a power curve
    /// (approximately gamma 2.2) for the rest of the range.
    ///
    /// This dual structure avoids numerical instability in the shadows while closely
    /// matching the CRT response curve that users expect.
    case sRGB

    /// BT.1886 — the broadcast standard EOTF for Rec.709 content.
    ///
    /// ITU-R BT.1886-0 defines how broadcast monitors should reproduce Rec.709
    /// content. Unlike sRGB, it uses a pure 2.4 power law with black level
    /// compensation, which produces a more natural rendering in the dim surround
    /// conditions of a grading suite.
    ///
    /// The formula accounts for non-zero black level (Lb) so that shadow detail
    /// is preserved even on displays that don't achieve perfect black. This is
    /// critical for film professionals — if the black level compensation is wrong,
    /// shadow detail is either crushed or lifted, destroying the colorist's intent.
    ///
    /// - Parameters:
    ///   - blackLevel: The display's minimum luminance (Lb), normalized [0,1].
    ///     A perfect display has blackLevel = 0. Real displays range from 0.0005 to 0.01.
    ///   - whiteLevel: The display's peak luminance (Lw), normalized [0,1].
    ///     Typically 1.0 (representing 100 cd/m² or whatever the display's max is).
    case bt1886(blackLevel: Double, whiteLevel: Double)

    /// PQ (Perceptual Quantizer) — SMPTE ST.2084 HDR transfer function.
    ///
    /// PQ is designed for high dynamic range content with luminances up to
    /// 10,000 cd/m². It is based on the Barten model of human contrast sensitivity,
    /// allocating code values to match the eye's ability to perceive differences
    /// in brightness. This means no code values are wasted — every step is at
    /// the threshold of visibility.
    ///
    /// PQ is absolute: code value 0.5 always means the same luminance regardless
    /// of the display. This is fundamentally different from SDR transfer functions
    /// which are relative to the display's peak white.
    case pq

    /// HLG (Hybrid Log-Gamma) — BBC/NHK HDR broadcast transfer function.
    ///
    /// HLG is designed for live broadcast where backward compatibility with SDR
    /// displays is essential. The lower half of the signal range uses a power law
    /// (like traditional SDR), while the upper half switches to a logarithmic curve
    /// to accommodate the extended dynamic range.
    ///
    /// Unlike PQ, HLG is scene-referred and relative — it adapts to the display's
    /// peak luminance, making it more forgiving for consumer TVs of varying brightness.
    case hlg
}

// MARK: - EOTF / Inverse EOTF

extension TransferFunction {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Decode (EOTF): encoded signal V → linear light L
    // ──────────────────────────────────────────────────────────────────────

    /// Applies the electro-optical transfer function.
    ///
    /// Converts an encoded signal value (as stored in a video file or frame buffer)
    /// to the linear-light luminance the display should produce.
    ///
    /// - Parameter encoded: Normalized signal value in [0, 1].
    /// - Returns: Linear light output in [0, 1] (or [0, 10000] for PQ, normalized).
    public func decode(_ encoded: Double) -> Double {
        let v = clamp01(encoded)

        switch self {

        // ── Power Law ────────────────────────────────────────────────────
        // L = V^γ  — the simplest and most common transfer function.
        case .powerLaw(let gamma):
            return pow(v, gamma)

        // ── sRGB (IEC 61966-2-1) ─────────────────────────────────────────
        // Piecewise: linear segment below the knee, power curve above.
        //   V ≤ 0.04045:  L = V / 12.92
        //   V > 0.04045:  L = ((V + 0.055) / 1.055)^2.4
        case .sRGB:
            if v <= 0.04045 {
                return v / 12.92
            } else {
                return pow((v + 0.055) / 1.055, 2.4)
            }

        // ── BT.1886 (ITU-R BT.1886-0) ───────────────────────────────────
        // L = a * max(V + b, 0)^γ
        //
        // This is the canonical broadcast EOTF. The constants a and b are
        // derived from the display's measured black and white luminance so
        // that the curve smoothly maps the full signal range while
        // preserving shadow detail above the black level.
        case .bt1886(let blackLevel, let whiteLevel):
            let params = BT1886.parameters(blackLevel: blackLevel, whiteLevel: whiteLevel)
            let base = max(v + params.b, 0.0)
            return params.a * pow(base, BT1886.gamma)

        // ── PQ (SMPTE ST.2084) ───────────────────────────────────────────
        // The perceptual quantizer. Designed so that each code-value step
        // corresponds to approximately one just-noticeable difference (JND).
        //
        // EOTF: L = 10000 * ((max(V^(1/m2) - c1, 0)) / (c2 - c3 * V^(1/m2)))^(1/m1)
        //
        // We normalize the output to [0, 1] by dividing by 10000.
        case .pq:
            let vp = pow(v, 1.0 / PQ.m2)
            let numerator = max(vp - PQ.c1, 0.0)
            let denominator = PQ.c2 - PQ.c3 * vp
            // Guard against division by zero at V = 0
            if denominator <= 0 { return 0.0 }
            let linear = pow(numerator / denominator, 1.0 / PQ.m1)
            // Return normalized to [0,1] — multiply by 10000 to get cd/m²
            return linear

        // ── HLG (ARIB STD-B67) ───────────────────────────────────────────
        // Hybrid Log-Gamma OETF inverse (scene linear from HLG signal).
        //   V ≤ 0.5:   L = (V²) / 3
        //   V > 0.5:   L = (exp((V - c) / a) + b) / 12
        // where a = 0.17883277, b = 1 - 4a, c = 0.5 - a * ln(4a)
        case .hlg:
            if v <= 0.5 {
                return (v * v) / 3.0
            } else {
                return (exp((v - HLG.c) / HLG.a) + HLG.b) / 12.0
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Encode (Inverse EOTF): linear light L → encoded signal V
    // ──────────────────────────────────────────────────────────────────────

    /// Applies the inverse of the electro-optical transfer function.
    ///
    /// Converts linear light luminance back to the encoded signal value that
    /// would produce it. Used when building LUTs and calibration curves.
    ///
    /// - Parameter linear: Linear light value in [0, 1].
    /// - Returns: Encoded signal value in [0, 1].
    public func encode(_ linear: Double) -> Double {
        let l = clamp01(linear)

        switch self {

        // ── Power Law (inverse) ──────────────────────────────────────────
        // V = L^(1/γ)
        case .powerLaw(let gamma):
            guard gamma != 0 else { return 0.0 }
            return pow(l, 1.0 / gamma)

        // ── sRGB (inverse) ───────────────────────────────────────────────
        //   L ≤ 0.0031308:  V = 12.92 * L
        //   L > 0.0031308:  V = 1.055 * L^(1/2.4) - 0.055
        case .sRGB:
            if l <= 0.0031308 {
                return 12.92 * l
            } else {
                return 1.055 * pow(l, 1.0 / 2.4) - 0.055
            }

        // ── BT.1886 (inverse) ────────────────────────────────────────────
        // Solve L = a * max(V + b, 0)^γ  for V:
        //   V = (L / a)^(1/γ) - b
        case .bt1886(let blackLevel, let whiteLevel):
            let params = BT1886.parameters(blackLevel: blackLevel, whiteLevel: whiteLevel)
            guard params.a != 0 else { return 0.0 }
            return pow(l / params.a, 1.0 / BT1886.gamma) - params.b

        // ── PQ (inverse, SMPTE ST.2084 OETF) ────────────────────────────
        // V = ((c1 + c2 * L^m1) / (1 + c3 * L^m1))^m2
        case .pq:
            let lm1 = pow(l, PQ.m1)
            let numerator = PQ.c1 + PQ.c2 * lm1
            let denominator = 1.0 + PQ.c3 * lm1
            return pow(numerator / denominator, PQ.m2)

        // ── HLG (OETF, ARIB STD-B67) ────────────────────────────────────
        //   L ≤ 1/12:   V = sqrt(3 * L)
        //   L > 1/12:   V = a * ln(12 * L - b) + c
        case .hlg:
            if l <= 1.0 / 12.0 {
                return sqrt(3.0 * l)
            } else {
                return HLG.a * log(12.0 * l - HLG.b) + HLG.c
            }
        }
    }
}

// MARK: - BT.1886 Constants & Parameter Derivation

/// ITU-R BT.1886-0 constants and parameter derivation.
///
/// BT.1886 defines how a display should render Rec.709 content. The key insight
/// is that real displays never achieve perfect black — there's always some residual
/// luminance (the "black level"). The formula compensates for this by adjusting the
/// curve so that the full signal range [0, 1] maps smoothly from the actual black
/// level to the actual white level.
///
/// Without this compensation, shadow detail is either crushed (if you ignore the
/// black level) or lifted (if you simply add an offset). BT.1886 gets it right.
private enum BT1886 {
    /// The BT.1886 gamma exponent — always 2.4 per the standard.
    static let gamma: Double = 2.4

    /// Derived parameters for the BT.1886 EOTF.
    struct Parameters {
        /// Scale factor derived from white and black luminance.
        let a: Double
        /// Offset derived from black luminance relative to white.
        let b: Double
    }

    /// Derives the a and b parameters from measured display luminance.
    ///
    /// From ITU-R BT.1886-0:
    /// ```
    /// a = (Lw^(1/γ) - Lb^(1/γ))^γ
    /// b = Lb^(1/γ) / (Lw^(1/γ) - Lb^(1/γ))
    /// ```
    ///
    /// - Parameters:
    ///   - blackLevel: Display's minimum luminance Lb (normalized, ≥ 0).
    ///   - whiteLevel: Display's peak luminance Lw (normalized, > 0).
    /// - Returns: The derived (a, b) parameters.
    static func parameters(blackLevel: Double, whiteLevel: Double) -> Parameters {
        let lw = max(whiteLevel, 1e-10)
        let lb = max(blackLevel, 0.0)

        let lwRoot = pow(lw, 1.0 / gamma)
        let lbRoot = pow(lb, 1.0 / gamma)
        let diff = lwRoot - lbRoot

        guard diff > 1e-10 else {
            // Degenerate case: white ≈ black — return identity-like parameters
            return Parameters(a: 1.0, b: 0.0)
        }

        let a = pow(diff, gamma)
        let b = lbRoot / diff

        return Parameters(a: a, b: b)
    }
}

// MARK: - PQ (ST.2084) Constants

/// SMPTE ST.2084 Perceptual Quantizer constants.
///
/// These constants were derived from Barten's model of human contrast sensitivity.
/// They ensure that each code-value step in a 10-bit or 12-bit PQ signal corresponds
/// to roughly one just-noticeable difference (JND) in luminance. This means PQ
/// wastes zero bits — every step matters.
///
/// The constant names follow the SMPTE specification notation.
private enum PQ {
    /// m1 = 2610 / 16384 = 0.1593017578125
    static let m1: Double = 2610.0 / 16384.0

    /// m2 = 2523 / 4096 * 128 = 78.84375
    static let m2: Double = 2523.0 / 4096.0 * 128.0

    /// c1 = 3424 / 4096 = 0.8359375 (also known as c3 - c2 + 1)
    static let c1: Double = 3424.0 / 4096.0

    /// c2 = 2413 / 4096 * 32 = 18.8515625
    static let c2: Double = 2413.0 / 4096.0 * 32.0

    /// c3 = 2392 / 4096 * 32 = 18.6875
    static let c3: Double = 2392.0 / 4096.0 * 32.0
}

// MARK: - HLG (ARIB STD-B67) Constants

/// Hybrid Log-Gamma constants from ARIB STD-B67.
///
/// HLG was jointly developed by the BBC and NHK for live HDR broadcasting.
/// The "hybrid" name comes from its dual nature: a square-root (gamma-like)
/// curve in the lower half for SDR compatibility, and a logarithmic curve
/// in the upper half to extend the dynamic range without clipping highlights.
private enum HLG {
    /// a = 0.17883277 — controls the log curve slope
    static let a: Double = 0.17883277

    /// b = 1 - 4a = 0.28466892 — ensures continuity at the knee point
    static let b: Double = 1.0 - 4.0 * 0.17883277

    /// c = 0.5 - a * ln(4a) — ensures the knee point is at V = 0.5
    static let c: Double = 0.5 - 0.17883277 * log(4.0 * 0.17883277)
}

// MARK: - Utility

/// Clamps a value to the [0, 1] range.
///
/// Display signals and linear light values are always non-negative and bounded.
/// Clamping prevents numerical artifacts from propagating through the pipeline.
@inline(__always)
private func clamp01(_ value: Double) -> Double {
    min(max(value, 0.0), 1.0)
}

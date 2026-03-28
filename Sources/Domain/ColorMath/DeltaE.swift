// ============================================================================
// DeltaE.swift — CIE Delta-E 2000 Color Difference
// ============================================================================
//
// Delta-E ("ΔE") quantifies the perceptual difference between two colors.
// The human eye can barely distinguish colors with ΔE < 1.0; differences
// above ~3.0 are obvious to most observers.
//
// HISTORY OF DELTA-E FORMULAS
// ---------------------------
// CIE76 (ΔE*ab):  Simple Euclidean distance in Lab. Fast but non-uniform —
//                   blues look more different than they are, and grays need
//                   larger Lab differences to be noticed.
//
// CIE94 (ΔE*94):  Added weighting for chroma and hue, improving perceptual
//                   uniformity. Still had issues in the blue region.
//
// CIEDE2000 (ΔE00): The current gold standard. Adds:
//                    - Hue rotation term (RT) to fix blue-purple nonuniformity
//                    - Chroma-dependent a* rescaling (a' prime)
//                    - Improved lightness, chroma, and hue weighting (SL, SC, SH)
//
// In professional display calibration, ΔE00 < 1.0 is the target for critical
// grading monitors. Broadcast specifications like EBU Tech 3320 specify
// ΔE00 thresholds for color accuracy testing.
//
// REFERENCE
// ---------
// Sharma, G., Wu, W., & Dalal, E. N. (2005).
// "The CIEDE2000 Color-Difference Formula: Implementation Notes,
//  Supplementary Test Data, and Mathematical Observations."
// Color Research & Application, 30(1), 21–30.
//
// ============================================================================

import Foundation

/// Calculates CIE Delta-E 2000 (CIEDE2000) between two Lab colors.
///
/// This is the definitive perceptual color difference metric used in the
/// film and broadcast industries. It accounts for non-uniformities in
/// human color perception that simpler formulas (CIE76, CIE94) miss.
///
/// - Parameters:
///   - lab1: First color in CIE L*a*b*.
///   - lab2: Second color in CIE L*a*b*.
///   - kL: Parametric lightness factor. Default 1.0 (reference conditions: D65, 1000 lux, uniform background L*=50).
///   - kC: Parametric chroma factor. Default 1.0.
///   - kH: Parametric hue factor. Default 1.0.
///
/// - Returns: The ΔE00 value. Zero means identical; <1.0 is imperceptible;
///   1–3 is noticeable by trained observers; >5 is clearly different.
///
/// - Note: The algorithm operates in a modified L'C'h' space with 7 distinct
///   correction steps. Each step addresses a specific perceptual non-uniformity
///   in the original Lab space.
public func deltaE2000(
    _ lab1: CIELab,
    _ lab2: CIELab,
    kL: Double = 1.0,
    kC: Double = 1.0,
    kH: Double = 1.0
) -> Double {

    // ─── Step 0: Extract Lab components ─────────────────────────────
    let L1 = lab1.L, a1 = lab1.a, b1 = lab1.b
    let L2 = lab2.L, a2 = lab2.a, b2 = lab2.b

    // ─── Step 1: Calculate C*ab (chroma in original Lab) ────────────
    // C*ab = √(a² + b²) — the radial distance from the achromatic axis.
    let C1ab = sqrt(a1 * a1 + b1 * b1)
    let C2ab = sqrt(a2 * a2 + b2 * b2)

    // Arithmetic mean of the two chromas (used in several corrections).
    let Cab_mean = (C1ab + C2ab) / 2.0

    // ─── Step 2: Calculate a' (chroma-dependent a* adjustment) ──────
    //
    // Lab's a* axis is known to be "compressed" at low chroma — neutral
    // colors appear to change hue too easily. The CIEDE2000 formula
    // stretches the a* axis as a function of mean chroma:
    //
    //   G = 0.5 * (1 - √(C̄^7 / (C̄^7 + 25^7)))
    //   a' = a * (1 + G)
    //
    // At high chroma (C̄ >> 25), G → 0 and a' ≈ a (no change).
    // At low chroma (C̄ → 0), G → 0.5 and a' = 1.5 * a (stretched by 50%).
    let Cab_mean_pow7 = pow(Cab_mean, 7.0)
    let twentyFive_pow7 = 6103515625.0  // 25^7 = 6,103,515,625
    let G = 0.5 * (1.0 - sqrt(Cab_mean_pow7 / (Cab_mean_pow7 + twentyFive_pow7)))

    let a1_prime = a1 * (1.0 + G)
    let a2_prime = a2 * (1.0 + G)

    // ─── Step 3: Calculate C' and h' in the modified space ──────────
    let C1_prime = sqrt(a1_prime * a1_prime + b1 * b1)
    let C2_prime = sqrt(a2_prime * a2_prime + b2 * b2)

    // Hue angle h' in degrees [0, 360). Use atan2 for correct quadrant.
    // When C' = 0 (achromatic), the hue is undefined — set to 0.
    var h1_prime = atan2(b1, a1_prime) * 180.0 / .pi
    if h1_prime < 0 { h1_prime += 360.0 }
    if C1_prime == 0 { h1_prime = 0.0 }

    var h2_prime = atan2(b2, a2_prime) * 180.0 / .pi
    if h2_prime < 0 { h2_prime += 360.0 }
    if C2_prime == 0 { h2_prime = 0.0 }

    // ─── Step 4: Calculate ΔL', ΔC', ΔH' ───────────────────────────
    let deltaL_prime = L2 - L1
    let deltaC_prime = C2_prime - C1_prime

    // Hue difference requires careful handling of the circular nature
    // of hue angles. The difference must be in the range (-180, 180].
    let dh_prime: Double
    if C1_prime * C2_prime == 0 {
        // One or both colors are achromatic — hue difference is zero.
        dh_prime = 0.0
    } else {
        var diff = h2_prime - h1_prime
        if diff > 180.0 {
            diff -= 360.0
        } else if diff < -180.0 {
            diff += 360.0
        }
        dh_prime = diff
    }

    // ΔH' is the chord-based hue difference (not the arc), computed via:
    //   ΔH' = 2 √(C'₁ C'₂) sin(Δh'/2)
    // This correctly handles the geometry of the hue circle.
    let deltaH_prime = 2.0 * sqrt(C1_prime * C2_prime) * sin(dh_prime * .pi / 360.0)

    // ─── Step 5: Calculate mean L', C', h' ──────────────────────────
    let L_prime_mean = (L1 + L2) / 2.0
    let C_prime_mean = (C1_prime + C2_prime) / 2.0

    // Mean hue: same circular averaging problem as above. When both
    // colors are achromatic, mean hue is irrelevant (set to sum).
    let h_prime_mean: Double
    if C1_prime * C2_prime == 0 {
        // At least one achromatic: mean hue is the sum (the non-zero one, or 0).
        h_prime_mean = h1_prime + h2_prime
    } else if abs(h1_prime - h2_prime) <= 180.0 {
        h_prime_mean = (h1_prime + h2_prime) / 2.0
    } else {
        // Hues straddle the 0°/360° boundary.
        if h1_prime + h2_prime < 360.0 {
            h_prime_mean = (h1_prime + h2_prime + 360.0) / 2.0
        } else {
            h_prime_mean = (h1_prime + h2_prime - 360.0) / 2.0
        }
    }

    // ─── Step 6: Weighting functions SL, SC, SH ────────────────────
    //
    // These correct for the varying sensitivity of human vision to L*, C*, h
    // differences at different locations in color space.

    // SL: Lightness weighting — the eye is more tolerant of lightness
    // differences in dark and light regions than in the midtones.
    let L_prime_mean_50_sq = (L_prime_mean - 50.0) * (L_prime_mean - 50.0)
    let SL = 1.0 + (0.015 * L_prime_mean_50_sq) / sqrt(20.0 + L_prime_mean_50_sq)

    // SC: Chroma weighting — higher chroma = higher tolerance.
    let SC = 1.0 + 0.045 * C_prime_mean

    // T: Hue-dependent term used in SH. It accounts for the fact that
    // perceptual hue uniformity varies around the hue circle — hue
    // differences are harder to see near yellow (h≈90°) and easier
    // to see near blue-violet (h≈275°).
    let T = 1.0
        - 0.17 * cos((h_prime_mean - 30.0) * .pi / 180.0)
        + 0.24 * cos((2.0 * h_prime_mean) * .pi / 180.0)
        + 0.32 * cos((3.0 * h_prime_mean + 6.0) * .pi / 180.0)
        - 0.20 * cos((4.0 * h_prime_mean - 63.0) * .pi / 180.0)

    // SH: Hue weighting.
    let SH = 1.0 + 0.015 * C_prime_mean * T

    // ─── Step 7: Rotation term RT ───────────────────────────────────
    //
    // The blue region of Lab (around h≈275°) has a known non-uniformity
    // where the principal axes of perceptual tolerance ellipses are
    // rotated relative to the L*C*h axes. The RT term applies a
    // cross-coupling between ΔC' and ΔH' to compensate.

    // Δθ narrows the rotation to the blue region (Gaussian centered at 275°).
    let deltaTheta = 30.0 * exp(-((h_prime_mean - 275.0) / 25.0) * ((h_prime_mean - 275.0) / 25.0))

    // RC: chroma-dependent rotation magnitude.
    let C_prime_mean_pow7 = pow(C_prime_mean, 7.0)
    let RC = 2.0 * sqrt(C_prime_mean_pow7 / (C_prime_mean_pow7 + twentyFive_pow7))

    // RT is negative in the blue region, creating the cross-term rotation.
    let RT = -sin(2.0 * deltaTheta * .pi / 180.0) * RC

    // ─── Step 8: Final combination ──────────────────────────────────
    //
    // The overall ΔE00 is a weighted Euclidean distance in the corrected
    // L'C'h' space, with the RT cross-term:
    //
    //   ΔE00 = √[ (ΔL'/(kL·SL))² + (ΔC'/(kC·SC))² + (ΔH'/(kH·SH))²
    //            + RT·(ΔC'/(kC·SC))·(ΔH'/(kH·SH)) ]
    let termL = deltaL_prime / (kL * SL)
    let termC = deltaC_prime / (kC * SC)
    let termH = deltaH_prime / (kH * SH)

    let deltaE = sqrt(
        termL * termL
        + termC * termC
        + termH * termH
        + RT * termC * termH
    )

    return deltaE
}

// MARK: - Convenience: Simple CIE76 Delta-E

/// CIE76 ΔE*ab — simple Euclidean distance in Lab space.
///
/// This is the original 1976 formula: ΔE = √((ΔL*)² + (Δa*)² + (Δb*)²).
/// Fast but perceptually non-uniform. Use `deltaE2000` for accuracy.
/// Included here because some legacy specifications reference CIE76 values.
public func deltaE76(_ lab1: CIELab, _ lab2: CIELab) -> Double {
    let dL = lab1.L - lab2.L
    let da = lab1.a - lab2.a
    let db = lab1.b - lab2.b
    return sqrt(dL * dL + da * da + db * db)
}

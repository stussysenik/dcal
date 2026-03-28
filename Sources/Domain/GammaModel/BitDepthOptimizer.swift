// BitDepthOptimizer.swift
// dcal – Display Calibration Tool
//
// Perceptual optimization of 8-bit gamma ramps.
//
// The fundamental problem:
// An 8-bit display has only 256 discrete levels per channel. That sounds like
// a lot, but human vision is far more sensitive to differences in dark tones
// than bright tones. A naive linear-to-gamma mapping wastes many of those 256
// levels on bright regions (where the eye can't tell the difference) and starves
// the dark regions (where banding artifacts are painfully visible).
//
// The solution is CIE L* (lightness):
// CIE L* was specifically designed so that equal numerical differences correspond
// to equal perceived differences. An L* step from 10 to 11 looks the same as a
// step from 90 to 91 — even though the underlying luminance change is very
// different. By spacing our 256 levels evenly in L*, we guarantee that the
// display produces the smoothest possible gradients with its limited bit depth.
//
// This is the difference between a "calibrated" display and a "properly calibrated"
// display. The same hardware, the same panel, but the optimized ramp eliminates
// visible banding in shadows and produces smooth gradients across the full range.
// For film professionals working with dark scenes (horror, noir, night exteriors),
// this is the difference between seeing the director's intent and seeing staircase
// artifacts where there should be smooth shadow gradients.

import Foundation

// MARK: - CIE L* Constants

/// CIE L* (lightness) constants from CIE 15:2004.
///
/// L* is a perceptual lightness scale from 0 (black) to 100 (white).
/// It models the nonlinear response of human vision to luminance:
/// we perceive far more detail in shadows than in highlights.
///
/// The formula has two segments:
/// - A linear portion near black (L* ≤ 8), avoiding division-by-zero issues.
/// - A cube-root portion for the rest, closely matching the Stevens power law
///   for brightness perception.
private enum CIEL {
    /// The L* threshold below which the linear segment is used.
    /// L* = 8 corresponds to Y ≈ 0.008856 (the "epsilon" in CIE formulas).
    static let linearThreshold: Double = 8.0

    /// The kappa constant: 903.3 (exact: 24389/27).
    /// Used in the linear segment: L* = kappa * Y for small Y.
    static let kappa: Double = 903.3

    /// Converts CIE L* lightness to relative luminance Y.
    ///
    /// This is the inverse L* formula — given a perceptual lightness value,
    /// find the physical luminance that produces it.
    ///
    /// - Parameter lStar: CIE L* value in [0, 100].
    /// - Returns: Relative luminance Y in [0, 1].
    static func lStarToLuminance(_ lStar: Double) -> Double {
        if lStar <= linearThreshold {
            // Linear segment: Y = L* / kappa
            return lStar / kappa
        } else {
            // Cube-root segment: Y = ((L* + 16) / 116)^3
            let ratio = (lStar + 16.0) / 116.0
            return ratio * ratio * ratio
        }
    }

    /// Converts relative luminance Y to CIE L* lightness.
    ///
    /// - Parameter luminance: Relative luminance Y in [0, 1].
    /// - Returns: CIE L* value in [0, 100].
    static func luminanceToLStar(_ luminance: Double) -> Double {
        let epsilon = 216.0 / 24389.0  // ≈ 0.008856
        if luminance <= epsilon {
            // Linear segment: L* = kappa * Y
            return kappa * luminance
        } else {
            // Cube-root segment: L* = 116 * Y^(1/3) - 16
            return 116.0 * pow(luminance, 1.0 / 3.0) - 16.0
        }
    }
}

// MARK: - BitDepthOptimizer

/// Optimizes a 256-level gamma ramp for maximum perceptual uniformity.
///
/// The problem: 8-bit displays have only 256 levels per channel. A naive gamma
/// ramp wastes levels in bright regions (where the eye is less sensitive) and
/// starves dark regions (where banding is most visible).
///
/// The solution: Allocate more of the 256 levels to perceptually-sensitive
/// regions using CIE L* (lightness) as the perceptual model. L* is designed
/// so that equal numerical differences correspond to equal perceived differences.
///
/// This is what separates a properly calibrated 8-bit display from a poorly
/// calibrated one — the same hardware, dramatically better visual output.
public struct BitDepthOptimizer: Sendable {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Perceptual Optimization
    // ──────────────────────────────────────────────────────────────────────

    /// Generates a perceptually-optimized gamma ramp for an 8-bit display.
    ///
    /// Returns 256 normalized output values [0, 1] that, when applied to the
    /// display's native response, produce evenly-spaced CIE L* lightness steps.
    ///
    /// The algorithm:
    /// 1. Divide the L* range (0–100) into 255 equal steps (256 levels, 255 intervals).
    /// 2. For each level i, compute the target L* = i * (100 / 255).
    /// 3. Convert L* to linear luminance Y using the CIE L* inverse formula.
    /// 4. Scale Y from the [0, 1] luminance range into the [blackLevel, whiteLevel]
    ///    range to account for the display's actual dynamic range.
    /// 5. Apply the target gamma to convert linear luminance to an encoded signal value.
    /// 6. Run a near-black preservation pass to ensure shadow detail survives quantization.
    ///
    /// The result is a ramp where moving from level N to level N+1 always produces
    /// the same perceived brightness change — no matter where you are in the range.
    ///
    /// - Parameters:
    ///   - nativeGamma: The display's measured gamma (used for diagnostics/context,
    ///     but the optimization targets perceptual uniformity regardless).
    ///   - targetGamma: The desired output gamma (default 2.4, per BT.1886).
    ///   - blackLevel: The display's minimum luminance, normalized [0, 1] (default 0).
    ///   - whiteLevel: The display's peak luminance, normalized [0, 1] (default 1).
    /// - Returns: Array of 256 normalized output values [0, 1].
    public static func optimizeForPerceptualUniformity(
        nativeGamma: Double,
        targetGamma: Double = 2.4,
        blackLevel: Double = 0.0,
        whiteLevel: Double = 1.0
    ) -> [Double] {
        precondition(targetGamma > 0, "Target gamma must be positive")

        let levels = 256
        let maxIndex = Double(levels - 1)
        let inverseGamma = 1.0 / targetGamma

        // The display's usable luminance range
        let luminanceRange = max(whiteLevel - blackLevel, 1e-10)

        var ramp = (0 ..< levels).map { i -> Double in
            // Step 1: Target L* for this level — evenly spaced from 0 to 100
            let targetLStar = Double(i) / maxIndex * 100.0

            // Step 2: Convert L* to linear luminance Y ∈ [0, 1]
            let linearY = CIEL.lStarToLuminance(targetLStar)

            // Step 3: Scale to the display's actual luminance range
            //
            // The display can't produce luminance below its black level or above
            // its white level. We map the perceptually-uniform Y into this range.
            let displayLuminance = blackLevel + linearY * luminanceRange

            // Step 4: Convert linear luminance to encoded signal value
            //
            // Apply the inverse of the target gamma to get the signal value that
            // will produce this luminance through the target transfer function.
            // V = L^(1/γ)
            let encoded = pow(max(displayLuminance, 0.0), inverseGamma)

            // Clamp to valid signal range
            return min(max(encoded, 0.0), 1.0)
        }

        // Step 5: Ensure near-black levels are distinguishable
        preserveNearBlack(ramp: &ramp)

        return ramp
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Banding Risk Analysis
    // ──────────────────────────────────────────────────────────────────────

    /// Analyzes a gamma ramp for banding risk.
    ///
    /// Banding occurs when consecutive display levels produce luminance values
    /// that are too far apart in perceptual space — the eye sees discrete steps
    /// instead of smooth gradients. This function quantifies the worst case.
    ///
    /// The algorithm:
    /// 1. For each consecutive pair of ramp values, compute the luminance
    ///    each would produce through the given gamma.
    /// 2. Convert both luminances to CIE L*.
    /// 3. Record the maximum L* gap across all consecutive pairs.
    ///
    /// Professional target: maxGap < 1.0 L* unit. At 1.0 L* per step, banding
    /// is at the threshold of visibility. Below 0.5 L*, it's invisible to
    /// virtually all observers.
    ///
    /// - Parameters:
    ///   - ramp: Array of normalized output values [0, 1] (typically 256 entries).
    ///   - gamma: The display gamma used to convert ramp values to luminance.
    /// - Returns: The maximum gap between consecutive L* values. Lower is better.
    public static func bandingRisk(ramp: [Double], gamma: Double) -> Double {
        guard ramp.count >= 2 else { return 0.0 }

        var maxGap: Double = 0.0

        for i in 1 ..< ramp.count {
            // Convert encoded ramp values to linear luminance: L = V^γ
            let luminancePrev = pow(max(ramp[i - 1], 0.0), gamma)
            let luminanceCurr = pow(max(ramp[i], 0.0), gamma)

            // Convert to perceptual lightness
            let lStarPrev = CIEL.luminanceToLStar(luminancePrev)
            let lStarCurr = CIEL.luminanceToLStar(luminanceCurr)

            // The gap between consecutive perceptual levels
            let gap = abs(lStarCurr - lStarPrev)
            maxGap = max(maxGap, gap)
        }

        return maxGap
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: Near-Black Preservation
    // ──────────────────────────────────────────────────────────────────────

    /// Preserves near-black detail by ensuring levels 0–10 produce
    /// distinguishable luminance steps.
    ///
    /// Critical for shadow detail in film: a dark scene (horror, noir, night
    /// exterior) lives in levels 0–20. If consecutive levels map to the same
    /// or nearly-the-same output value, shadow detail is crushed — objects
    /// in the shadows become invisible, and the colorist's work is destroyed.
    ///
    /// This function walks the near-black region and nudges any level that is
    /// too close to its predecessor upward by the minimum step size. It's a
    /// gentle correction — it doesn't change the overall shape of the ramp,
    /// just ensures that every shadow level is actually distinct.
    ///
    /// - Parameters:
    ///   - ramp: The gamma ramp to modify (256 normalized values, mutated in place).
    ///   - minimumStep: The minimum difference between consecutive levels in the
    ///     near-black region (default 0.001, which is ~0.25 code values at 8-bit).
    public static func preserveNearBlack(
        ramp: inout [Double],
        minimumStep: Double = 0.001
    ) {
        guard ramp.count >= 2 else { return }

        // Near-black region: levels 0 through 10 (or the end of the ramp, whichever is smaller).
        // These are the levels most susceptible to quantization collapse.
        let nearBlackEnd = min(11, ramp.count)

        for i in 1 ..< nearBlackEnd {
            let previousValue = ramp[i - 1]
            let currentValue = ramp[i]

            // If this level is indistinguishable from the previous one, nudge it up.
            if currentValue - previousValue < minimumStep {
                let nudged = previousValue + minimumStep
                // Don't let the nudge exceed 1.0 — that would be brighter than white.
                ramp[i] = min(nudged, 1.0)
            }
        }
    }
}

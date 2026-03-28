// ============================================================================
// ChromaticAdaptation.swift — Bradford Chromatic Adaptation Transform
// ============================================================================
//
// WHAT IS CHROMATIC ADAPTATION?
// -----------------------------
// When you view a white sheet of paper under tungsten light (warm, ~2856K)
// and then under daylight (cool, ~6504K), the paper looks "white" in both
// cases — your visual system adapts. But the spectral composition of the
// reflected light is completely different.
//
// In colorimetry, we need to mathematically predict what XYZ values a color
// would have under a different illuminant. This is called "chromatic
// adaptation" and is essential for:
//
//   - Converting between D65 (broadcast) and D50 (ICC print) workflows
//   - Adapting DCI cinema white (~6300K) to D65 for display
//   - Simulating how colors appear under tungsten (illuminant A)
//
// THE BRADFORD TRANSFORM
// ----------------------
// The Bradford model (Lam, 1985; refined by Hunt, Pointer) is the industry
// standard. It works by:
//
//   1. Converting XYZ to "cone response" (LMS) space via the Bradford matrix
//   2. Scaling each cone channel by the ratio of destination/source white
//      points (von Kries diagonal adaptation)
//   3. Converting back to XYZ
//
// The Bradford matrix is NOT a pure LMS transformation — it includes a
// "sharpened" blue channel that better predicts human adaptation behavior,
// especially in the blue region where simple von Kries fails.
//
// ICC USAGE
// ---------
// The ICC profile specification mandates the Bradford transform for adapting
// between the profile's native illuminant and the D50 Profile Connection
// Space (PCS). This makes it the most widely-used CAT in color management.
//
// ============================================================================

import Foundation

// MARK: - Illuminant

/// CIE Standard Illuminants — mathematically defined spectral power
/// distributions that represent common lighting conditions.
///
/// Each illuminant is specified by its chromaticity coordinates (x, y) on the
/// CIE 1931 diagram for the 2° standard observer. The corresponding XYZ
/// white point is derived by setting Y = 1.0 and computing X and Z from
/// the chromaticity.
public enum Illuminant: Sendable, Equatable {

    /// CIE Standard Illuminant D65 — average noon daylight.
    /// Correlated Color Temperature: ~6504 K.
    /// Used by: sRGB, Rec.709, Rec.2020, Display P3, most digital standards.
    case d65

    /// CIE Standard Illuminant D50 — horizon daylight.
    /// Correlated Color Temperature: ~5003 K.
    /// Used by: ICC Profile Connection Space (PCS), graphic arts, prepress.
    case d50

    /// CIE Standard Illuminant D55 — mid-morning/afternoon daylight.
    /// Correlated Color Temperature: ~5503 K.
    /// Used by: Some photographic and transparency viewing standards.
    case d55

    /// DCI Cinema White — the reference white for DCI-P3 theatrical projection.
    /// Correlated Color Temperature: ~6300 K (slightly greenish compared to D65).
    /// This is NOT a CIE standard illuminant but is critical for cinema work.
    /// Chromaticity: x = 0.314, y = 0.351 (per SMPTE RP 431-2).
    case d63

    /// CIE Standard Illuminant A — tungsten/incandescent lamp.
    /// Correlated Color Temperature: 2856 K.
    /// Used by: CIE reference conditions, some photometric calibrations.
    /// Note: Very warm (orange) — large adaptation required when converting
    /// to/from daylight illuminants.
    case a

    /// CIE xy chromaticity coordinates for this illuminant (2° standard observer).
    ///
    /// These are the exact values published by CIE and used in ISO standards.
    public var chromaticity: (x: Double, y: Double) {
        switch self {
        case .d65: return (x: 0.3127, y: 0.3290)
        case .d50: return (x: 0.3457, y: 0.3585)
        case .d55: return (x: 0.3324, y: 0.3474)
        case .d63: return (x: 0.3140, y: 0.3510)
        case .a:   return (x: 0.4476, y: 0.4074)
        }
    }

    /// The XYZ tristimulus values of this illuminant's white point,
    /// normalized so Y = 1.0.
    ///
    /// Derived from chromaticity: X = x/y, Y = 1, Z = (1-x-y)/y.
    public var whitePoint: CIEXYZ {
        let (x, y) = chromaticity
        return CIEXYZ(
            X: x / y,
            Y: 1.0,
            Z: (1.0 - x - y) / y
        )
    }
}

// MARK: - Bradford Matrices

/// The Bradford cone response matrix.
///
/// Transforms CIE XYZ to the "sharpened" LMS cone response domain used
/// by the Bradford chromatic adaptation model. The matrix was derived
/// empirically by Lam (1985) and refined by Hunt & Pointer to optimize
/// adaptation predictions.
///
/// Key property: the third row has a negative coefficient for Y, which
/// creates the "sharpened" blue channel that is NOT a pure LMS transform
/// but better predicts human chromatic adaptation behavior.
private let bradfordMatrix: Matrix3x3 = [
    [ 0.8951000,  0.2664000, -0.1614000],
    [-0.7502000,  1.7135000,  0.0367000],
    [ 0.0389000, -0.0685000,  1.0296000]
]

/// Inverse Bradford matrix — transforms from cone response space back to XYZ.
///
/// Pre-computed inverse of `bradfordMatrix` to avoid runtime matrix inversion.
/// Verified: bradfordMatrix × inverseBradfordMatrix = I₃ (identity).
private let inverseBradfordMatrix: Matrix3x3 = [
    [ 0.9869929, -0.1470543,  0.1599627],
    [ 0.4323053,  0.5183603,  0.0492912],
    [-0.0085287,  0.0400428,  0.9684867]
]

// MARK: - Matrix Helpers

/// Multiplies a 3×3 matrix by a 3-element column vector, returning a 3-element vector.
///
/// This is the fundamental operation for all color space transforms:
///   [x']   [m00 m01 m02] [x]
///   [y'] = [m10 m11 m12] [y]
///   [z']   [m20 m21 m22] [z]
private func multiplyMatrixVector(_ m: Matrix3x3, _ v: (Double, Double, Double)) -> (Double, Double, Double) {
    return (
        m[0][0] * v.0 + m[0][1] * v.1 + m[0][2] * v.2,
        m[1][0] * v.0 + m[1][1] * v.1 + m[1][2] * v.2,
        m[2][0] * v.0 + m[2][1] * v.1 + m[2][2] * v.2
    )
}

/// Multiplies two 3×3 matrices and returns the product.
///
/// Used to compose the full adaptation matrix M = M_Bradford⁻¹ × D × M_Bradford
/// where D is the diagonal von Kries scaling matrix.
private func multiplyMatrices(_ a: Matrix3x3, _ b: Matrix3x3) -> Matrix3x3 {
    var result: Matrix3x3 = [
        [0, 0, 0],
        [0, 0, 0],
        [0, 0, 0]
    ]
    for i in 0..<3 {
        for j in 0..<3 {
            result[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]
        }
    }
    return result
}

// MARK: - Bradford Chromatic Adaptation

/// Performs Bradford chromatic adaptation, transforming XYZ coordinates from
/// one illuminant's white point to another.
///
/// This is the standard method used by ICC color management and is essential
/// for converting between:
///   - D65 (broadcast/web) ↔ D50 (ICC print)
///   - D65 ↔ DCI cinema white (D63)
///   - Any pair of illuminants in the `Illuminant` enum
///
/// THE ALGORITHM
/// 1. Compute source and destination white points in cone response (LMS) space
///    by multiplying their XYZ values by the Bradford matrix.
/// 2. Compute the von Kries diagonal scaling factors: ratio = dest_LMS / src_LMS
///    for each cone channel independently.
/// 3. Build the complete 3×3 adaptation matrix:
///    M_adapt = M_Bradford⁻¹ × diag(ratios) × M_Bradford
/// 4. Apply M_adapt to the input XYZ.
///
/// - Parameters:
///   - xyz: The color in CIE XYZ to adapt.
///   - source: The illuminant the color was measured/defined under.
///   - destination: The illuminant to adapt the color to.
///
/// - Returns: The adapted CIE XYZ values under the destination illuminant.
///
/// - Note: If source == destination, the input is returned unchanged (identity transform).
public func bradfordAdapt(_ xyz: CIEXYZ, from source: Illuminant, to destination: Illuminant) -> CIEXYZ {

    // Short-circuit: adapting to the same illuminant is a no-op.
    guard source != destination else { return xyz }

    // Step 1: Get source and destination white points in XYZ.
    let srcWhite = source.whitePoint
    let dstWhite = destination.whitePoint

    // Step 2: Convert white points to Bradford cone response space (LMS).
    //
    // "LMS" here is in quotes because the Bradford matrix produces a
    // "sharpened" cone space that is NOT physiological LMS — it is an
    // empirically optimized transform for adaptation prediction.
    let srcLMS = multiplyMatrixVector(bradfordMatrix, (srcWhite.X, srcWhite.Y, srcWhite.Z))
    let dstLMS = multiplyMatrixVector(bradfordMatrix, (dstWhite.X, dstWhite.Y, dstWhite.Z))

    // Step 3: Compute von Kries diagonal scaling factors.
    //
    // The von Kries hypothesis (1902) states that chromatic adaptation
    // can be modeled by independent gain control of the three cone types.
    // Each cone channel is scaled by the ratio of the new white to the
    // old white in that channel:
    //
    //   L_adapted = L × (L_dst_white / L_src_white)
    //
    // This diagonal scaling in cone space is the core of all von Kries-type
    // chromatic adaptation transforms. The choice of cone space (Bradford
    // vs. Hunt-Pointer-Estévez vs. raw LMS) determines the accuracy.
    let scaleL = dstLMS.0 / srcLMS.0
    let scaleM = dstLMS.1 / srcLMS.1
    let scaleS = dstLMS.2 / srcLMS.2

    // Step 4: Build the diagonal scaling matrix.
    let diag: Matrix3x3 = [
        [scaleL, 0,      0     ],
        [0,      scaleM, 0     ],
        [0,      0,      scaleS]
    ]

    // Step 5: Compose the full adaptation matrix.
    //
    // M_adapt = M_Bradford⁻¹ × D × M_Bradford
    //
    // This takes XYZ → cone space (Bradford), applies diagonal scaling,
    // then converts back to XYZ. The composition into a single 3×3 matrix
    // means we only do one matrix-vector multiply per color sample, which
    // matters when adapting millions of pixels.
    let intermediate = multiplyMatrices(diag, bradfordMatrix)
    let adaptationMatrix = multiplyMatrices(inverseBradfordMatrix, intermediate)

    // Step 6: Apply the adaptation matrix to the input color.
    let result = multiplyMatrixVector(adaptationMatrix, (xyz.X, xyz.Y, xyz.Z))

    return CIEXYZ(X: result.0, Y: result.1, Z: result.2)
}

// MARK: - Convenience: Compute Adaptation Matrix

/// Computes the full 3×3 Bradford adaptation matrix from source to destination illuminant.
///
/// This is useful when you need to adapt many colors under the same illuminant
/// pair — compute the matrix once and apply it to each color, rather than
/// calling `bradfordAdapt` repeatedly (which recomputes the matrix each time).
///
/// - Parameters:
///   - source: The source illuminant.
///   - destination: The destination illuminant.
///
/// - Returns: A 3×3 matrix that can be multiplied with XYZ column vectors
///   to perform the adaptation.
public func bradfordAdaptationMatrix(from source: Illuminant, to destination: Illuminant) -> Matrix3x3 {
    let srcWhite = source.whitePoint
    let dstWhite = destination.whitePoint

    let srcLMS = multiplyMatrixVector(bradfordMatrix, (srcWhite.X, srcWhite.Y, srcWhite.Z))
    let dstLMS = multiplyMatrixVector(bradfordMatrix, (dstWhite.X, dstWhite.Y, dstWhite.Z))

    let diag: Matrix3x3 = [
        [dstLMS.0 / srcLMS.0, 0,                    0                   ],
        [0,                    dstLMS.1 / srcLMS.1,  0                   ],
        [0,                    0,                    dstLMS.2 / srcLMS.2 ]
    ]

    let intermediate = multiplyMatrices(diag, bradfordMatrix)
    return multiplyMatrices(inverseBradfordMatrix, intermediate)
}

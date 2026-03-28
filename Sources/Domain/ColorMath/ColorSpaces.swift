// ============================================================================
// ColorSpaces.swift — Core Color Space Types & Conversion Matrices
// ============================================================================
//
// Pure mathematical definitions of CIE colorimetric types and the 3×3 matrices
// that connect them to device-dependent RGB spaces.
//
// COLOR SCIENCE PRIMER
// --------------------
// The CIE (Commission Internationale de l'Éclairage) defined a system in 1931
// where any visible color can be described by three numbers (X, Y, Z) called
// tristimulus values. These correspond to the response of three hypothetical
// "standard observer" cone types. From XYZ we derive several useful forms:
//
//   xyY  — chromaticity (hue+saturation as x,y) separated from luminance (Y).
//          The familiar CIE chromaticity diagram lives in the x,y plane.
//
//   Lab  — Perceptually uniform space where equal numerical differences
//          approximate equal perceived differences. L* is lightness (0–100),
//          a* is green←→red, b* is blue←→yellow.
//
//   LCh  — Polar form of Lab: C* = chroma (saturation), h° = hue angle.
//
// To get from XYZ to an actual display's RGB values you need the display's
// primary chromaticities encoded as a 3×3 matrix, plus a transfer function
// (gamma curve). This file handles the matrix part; GammaFunctions.swift
// handles the nonlinear encoding.
//
// ============================================================================

import Foundation

// MARK: - CIE xyY (Chromaticity + Luminance)

/// CIE xyY color coordinates.
///
/// `x` and `y` are chromaticity coordinates derived from XYZ by normalizing
/// out the luminance: x = X/(X+Y+Z), y = Y/(X+Y+Z). The third coordinate
/// `Y` is absolute luminance (cd/m² when photometric, or relative 0–1).
///
/// The CIE 1931 chromaticity diagram is plotted in the x,y plane; every
/// visible monochromatic wavelength traces the horseshoe-shaped spectrum
/// locus, and all real colors lie inside it.
@frozen
public struct CIExyY: Sendable, Equatable {
    /// Chromaticity x coordinate (roughly corresponds to "redness").
    public var x: Double
    /// Chromaticity y coordinate (roughly corresponds to "greenness").
    public var y: Double
    /// Luminance (Y tristimulus value). Relative scale: 1.0 = reference white.
    public var Y: Double

    public init(x: Double, y: Double, Y: Double) {
        self.x = x
        self.y = y
        self.Y = Y
    }

    // MARK: xyY → XYZ

    /// Convert to CIE XYZ tristimulus values.
    ///
    /// The conversion uses:
    ///   X = (Y / y) * x
    ///   Z = (Y / y) * (1 - x - y)
    ///
    /// When y == 0 (the theoretical "zero luminance" singularity), all
    /// tristimulus values collapse to zero.
    public func toXYZ() -> CIEXYZ {
        guard y > 0 else {
            return CIEXYZ(X: 0, Y: 0, Z: 0)
        }
        let X = (Y / y) * x
        let Z = (Y / y) * (1.0 - x - y)
        return CIEXYZ(X: X, Y: Y, Z: Z)
    }
}

// MARK: - CIE XYZ (Tristimulus Values)

/// CIE 1931 XYZ tristimulus values — the universal interchange space for
/// all colorimetry.
///
/// Every color model eventually converts through XYZ. The Y component
/// equals luminance (it matches the photopic luminous efficiency function
/// V(λ)), while X and Z carry chromaticity information.
@frozen
public struct CIEXYZ: Sendable, Equatable {
    public var X: Double
    public var Y: Double
    public var Z: Double

    public init(X: Double, Y: Double, Z: Double) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }

    // MARK: XYZ → xyY

    /// Convert to CIE xyY chromaticity coordinates.
    ///
    /// Projects the 3D tristimulus value onto the 2D chromaticity plane
    /// by dividing out the sum X+Y+Z. Luminance Y passes through unchanged.
    public func toxyY() -> CIExyY {
        let sum = X + Y + Z
        guard sum > 0 else {
            return CIExyY(x: 0, y: 0, Y: 0)
        }
        return CIExyY(x: X / sum, y: Y / sum, Y: Y)
    }

    // MARK: XYZ → Lab

    /// Convert to CIE L*a*b* using the given reference white illuminant.
    ///
    /// Lab is designed to be perceptually uniform: a distance of 1.0 in Lab
    /// space should correspond to roughly the same perceived color difference
    /// regardless of where in the color space you are. (In practice this is
    /// approximate; Delta-E 2000 corrects remaining non-uniformities.)
    ///
    /// The conversion applies a cube-root compressive nonlinearity that
    /// mimics the human visual system's response, with a linear segment
    /// near black to avoid numerical instability:
    ///
    ///   f(t) = t^(1/3)              if t > (6/29)^3 ≈ 0.008856
    ///   f(t) = (t / 3δ²) + 4/29    otherwise
    ///
    /// where δ = 6/29.
    public func toLab(referenceWhite: CIEXYZ = CIELab.d65White) -> CIELab {
        // CIE constants for the piecewise f(t) function
        let epsilon = 216.0 / 24389.0  // (6/29)^3 ≈ 0.008856
        let kappa   = 24389.0 / 27.0   // (29/3)^3 ≈ 903.3

        func f(_ t: Double) -> Double {
            if t > epsilon {
                return pow(t, 1.0 / 3.0)
            } else {
                return (kappa * t + 16.0) / 116.0
            }
        }

        let fx = f(X / referenceWhite.X)
        let fy = f(Y / referenceWhite.Y)
        let fz = f(Z / referenceWhite.Z)

        let L = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let b = 200.0 * (fy - fz)

        return CIELab(L: L, a: a, b: b)
    }
}

// MARK: - CIE L*a*b* (Perceptually Uniform Color Space)

/// CIE 1976 L*a*b* color space — the workhorse of color difference calculations.
///
/// - `L` (L*): Lightness, 0 (black) to 100 (white).
/// - `a` (a*): Green (negative) to red (positive) axis.
/// - `b` (b*): Blue (negative) to yellow (positive) axis.
///
/// Lab is defined relative to a reference white point (illuminant).
/// The two most common are D65 (daylight, broadcast/web standard) and
/// D50 (horizon daylight, ICC profile connection space for print).
@frozen
public struct CIELab: Sendable, Equatable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    // MARK: Standard Illuminant Reference Whites (as XYZ)

    /// CIE Standard Illuminant D65 — average noon daylight (6504 K).
    /// Used by sRGB, Rec.709, Rec.2020, and most broadcast standards.
    /// These are the exact CIE values for the 2° standard observer.
    public static let d65White = CIEXYZ(X: 0.95047, Y: 1.00000, Z: 1.08883)

    /// CIE Standard Illuminant D50 — horizon daylight (5003 K).
    /// Used as the ICC Profile Connection Space (PCS) white point.
    /// Critical for print workflows and ICC color management.
    public static let d50White = CIEXYZ(X: 0.96422, Y: 1.00000, Z: 0.82521)

    // MARK: Lab → XYZ

    /// Convert back to CIE XYZ using the given reference white.
    ///
    /// This is the inverse of the XYZ→Lab transform, applying the inverse
    /// of the cube-root companding function:
    ///
    ///   f⁻¹(t) = t³                          if t > 6/29
    ///   f⁻¹(t) = 3 * (6/29)² * (t - 4/29)   otherwise
    public func toXYZ(referenceWhite: CIEXYZ = CIELab.d65White) -> CIEXYZ {
        let epsilon = 216.0 / 24389.0
        let kappa   = 24389.0 / 27.0

        let fy = (L + 16.0) / 116.0
        let fx = a / 500.0 + fy
        let fz = fy - b / 200.0

        let xr = fx * fx * fx > epsilon ? fx * fx * fx : (116.0 * fx - 16.0) / kappa
        let yr = L > kappa * epsilon ? pow((L + 16.0) / 116.0, 3.0) : L / kappa
        let zr = fz * fz * fz > epsilon ? fz * fz * fz : (116.0 * fz - 16.0) / kappa

        return CIEXYZ(
            X: xr * referenceWhite.X,
            Y: yr * referenceWhite.Y,
            Z: zr * referenceWhite.Z
        )
    }

    // MARK: Lab → LCh

    /// Convert to CIE LCh (polar form of Lab).
    ///
    /// Chroma C* = √(a² + b²) is the "saturation" — distance from the
    /// neutral axis. Hue angle h° = atan2(b, a) expressed in degrees [0, 360).
    /// This form is more intuitive for hue-based operations.
    public func toLCh() -> CIELCh {
        let C = sqrt(a * a + b * b)
        var h = atan2(b, a) * 180.0 / .pi
        if h < 0 { h += 360.0 }
        return CIELCh(L: L, C: C, h: h)
    }
}

// MARK: - CIE LCh (Polar Lab)

/// CIE L*C*h° — the polar (cylindrical) representation of Lab.
///
/// - `L` (L*): Lightness, identical to Lab L*.
/// - `C` (C*): Chroma — radial distance from the achromatic axis (saturation).
/// - `h` (h°): Hue angle in degrees, 0° = +a* axis (red), 90° = +b* axis
///   (yellow), 180° = −a* axis (green), 270° = −b* axis (blue).
///
/// LCh is especially useful for gamut mapping because you can reduce
/// chroma (desaturate) along a constant-hue line, which preserves the
/// perceived hue while bringing out-of-gamut colors into range.
@frozen
public struct CIELCh: Sendable, Equatable {
    public var L: Double
    public var C: Double
    /// Hue angle in degrees [0, 360).
    public var h: Double

    public init(L: Double, C: Double, h: Double) {
        self.L = L
        self.C = C
        self.h = h
    }

    // MARK: LCh → Lab

    /// Convert back to CIE L*a*b* (rectangular form).
    ///
    /// Simply decomposes the polar chroma/hue back to Cartesian a*, b*:
    ///   a* = C* × cos(h°)
    ///   b* = C* × sin(h°)
    public func toLab() -> CIELab {
        let hRad = h * .pi / 180.0
        let a = C * cos(hRad)
        let b = C * sin(hRad)
        return CIELab(L: L, a: a, b: b)
    }
}

// MARK: - Linear RGB (Scene-Linear, No Gamma)

/// Linear RGB values — light intensity proportional to photon count.
///
/// These are the RGB values BEFORE any gamma/transfer function is applied.
/// In a linear space, doubling a value doubles the physical light output.
/// This is the correct space for:
///   - Compositing and blending (alpha operations)
///   - Lighting calculations (physically based rendering)
///   - Color space conversions via matrix multiplication
///
/// After conversion, apply the appropriate transfer function (sRGB companding,
/// PQ, HLG, etc.) to get the encoded signal values sent to the display.
@frozen
public struct LinearRGB: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    // MARK: Linear RGB → XYZ

    /// Convert to CIE XYZ using the given color space's RGB-to-XYZ matrix.
    ///
    /// The matrix encodes where the space's R, G, B primaries sit in the
    /// CIE xy chromaticity diagram, scaled so the white point produces
    /// the correct XYZ. Each column of the matrix is the XYZ tristimulus
    /// value of one primary at unit intensity.
    public func toXYZ(colorSpace: ColorSpace = .sRGB) -> CIEXYZ {
        let m = colorSpace.rgbToXYZMatrix
        return CIEXYZ(
            X: m[0][0] * r + m[0][1] * g + m[0][2] * b,
            Y: m[1][0] * r + m[1][1] * g + m[1][2] * b,
            Z: m[2][0] * r + m[2][1] * g + m[2][2] * b
        )
    }

    // MARK: XYZ → Linear RGB (static factory)

    /// Create LinearRGB from CIE XYZ using the given color space's XYZ-to-RGB matrix.
    ///
    /// This is the inverse of `toXYZ()`. Note that the result may contain
    /// values outside [0, 1] if the input XYZ color lies outside the target
    /// color space's gamut. Gamut mapping should be applied before display.
    public static func fromXYZ(_ xyz: CIEXYZ, colorSpace: ColorSpace = .sRGB) -> LinearRGB {
        let m = colorSpace.xyzToRGBMatrix
        return LinearRGB(
            r: m[0][0] * xyz.X + m[0][1] * xyz.Y + m[0][2] * xyz.Z,
            g: m[1][0] * xyz.X + m[1][1] * xyz.Y + m[1][2] * xyz.Z,
            b: m[2][0] * xyz.X + m[2][1] * xyz.Y + m[2][2] * xyz.Z
        )
    }
}

// MARK: - 3×3 Matrix Type Alias

/// A 3×3 matrix stored as a row-major array of 3 rows, each containing 3 elements.
///
/// Row-major means `matrix[row][col]`, so `matrix[1][2]` is row 1, column 2.
/// All color space conversion matrices in this module use this layout.
public typealias Matrix3x3 = [[Double]]

// MARK: - ColorSpace (RGB Working Spaces)

/// Defines standard RGB color spaces by their 3×3 conversion matrices.
///
/// Each color space is defined by three primary chromaticities (red, green, blue
/// corners of its gamut triangle on the CIE diagram) and a white point. From
/// these, a pair of 3×3 matrices are derived:
///
///   RGB→XYZ: Converts linear RGB [0,1] to CIE XYZ tristimulus values.
///   XYZ→RGB: The inverse — converts XYZ back to linear RGB.
///
/// These matrices do NOT include any gamma/transfer function — they operate
/// purely in the linear-light domain.
public enum ColorSpace: Sendable, Equatable {

    // MARK: Cases

    /// sRGB / Rec.709 — the web and HD broadcast standard.
    /// Gamut covers ~35% of visible colors. Primaries are identical to Rec.709;
    /// the only difference is the transfer function (sRGB piecewise vs. Rec.709
    /// power law with linear tail — nearly identical in practice).
    /// White point: D65.
    case sRGB

    /// DCI-P3 — Digital Cinema Initiatives standard.
    /// ~25% larger gamut than sRGB, especially in reds and greens. Used by
    /// Apple displays, HDR content, and theatrical projection.
    /// Note: DCI-P3 as used in displays (Display P3) uses a D65 white point;
    /// the original DCI spec uses a greenish ~6300K white. These matrices
    /// are for the D65 variant (Display P3).
    case dciP3

    /// ITU-R BT.709 — identical primaries to sRGB but with a different
    /// transfer function (simple power law γ≈2.2 with linear tail).
    /// The broadcast HD standard worldwide.
    /// White point: D65.
    case rec709

    /// ITU-R BT.2020 — ultra-wide gamut for UHD/HDR broadcast.
    /// Covers ~75% of visible colors. Primaries are defined by single
    /// spectral wavelengths (630nm, 532nm, 467nm) giving the widest
    /// triangle achievable with monochromatic primaries.
    /// White point: D65.
    case rec2020

    // MARK: XYZ → Linear RGB Matrix

    /// The 3×3 matrix that converts CIE XYZ to linear RGB in this color space.
    ///
    /// Multiply [X, Y, Z] by this matrix to get [R_linear, G_linear, B_linear].
    /// Values outside [0,1] indicate the color is outside this space's gamut.
    public var xyzToRGBMatrix: Matrix3x3 {
        switch self {
        case .sRGB, .rec709:
            // IEC 61966-2-1 / ITU-R BT.709 (same primaries, same matrix)
            // Derived from the sRGB primary chromaticities and D65 white point.
            // Source: http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
            return [
                [ 3.2404542, -1.5371385, -0.4985314],
                [-0.9692660,  1.8760108,  0.0415560],
                [ 0.0556434, -0.2040259,  1.0572252]
            ]

        case .dciP3:
            // Display P3 (D65 white point variant used by Apple and modern HDR displays).
            // Derived from P3 primaries adapted to D65.
            return [
                [ 2.4934969, -0.9313836, -0.4027108],
                [-0.8294890,  1.7626641,  0.0236247],
                [ 0.0358458, -0.0761724,  0.9568845]
            ]

        case .rec2020:
            // ITU-R BT.2020 — ultra-wide gamut.
            // Primaries at spectral loci: R=630nm, G=532nm, B=467nm.
            return [
                [ 1.7166512, -0.3556708, -0.2533663],
                [-0.6666844,  1.6164812,  0.0157685],
                [ 0.0176399, -0.0427706,  0.9421031]
            ]
        }
    }

    // MARK: Linear RGB → XYZ Matrix

    /// The 3×3 matrix that converts linear RGB to CIE XYZ.
    ///
    /// This is the inverse of `xyzToRGBMatrix`. Each column represents the
    /// XYZ tristimulus values of one primary (R, G, or B) at unit intensity.
    /// The sum of each row's first three elements gives the white point's
    /// X, Y, Z respectively.
    public var rgbToXYZMatrix: Matrix3x3 {
        switch self {
        case .sRGB, .rec709:
            // IEC 61966-2-1 / ITU-R BT.709
            // Note: row 1 gives the luminance coefficients: 0.2126729 R + 0.7151522 G + 0.0721750 B
            // These are the familiar "luma" weights used throughout broadcast engineering.
            return [
                [0.4124564, 0.3575761, 0.1804375],
                [0.2126729, 0.7151522, 0.0721750],
                [0.0193339, 0.1191920, 0.9503041]
            ]

        case .dciP3:
            // Display P3 (D65 adapted)
            return [
                [0.4865709, 0.2656677, 0.1982173],
                [0.2289746, 0.6917385, 0.0792869],
                [0.0000000, 0.0451134, 1.0439444]
            ]

        case .rec2020:
            // ITU-R BT.2020
            // Luminance coefficients: 0.2627 R + 0.6780 G + 0.0593 B
            return [
                [0.6369580, 0.1446169, 0.1688810],
                [0.2627002, 0.6779981, 0.0593017],
                [0.0000000, 0.0280727, 1.0609851]
            ]
        }
    }
}

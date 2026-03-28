// ColorMathTests.swift — Comprehensive tests for the Domain color math layer
//
// Verifies color space conversions, Delta-E 2000, chromatic adaptation, and
// sRGB companding against published reference values and known roundtrip
// identities.

import Testing
@testable import Domain

// MARK: - Test Helpers

/// Asserts that two Double values are approximately equal within a tolerance.
private func expectApprox(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.0001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) < tolerance,
        "Expected \(expected), got \(actual), diff \(abs(actual - expected))",
        sourceLocation: sourceLocation
    )
}

// MARK: - XYZ <-> Lab Roundtrip Tests

@Suite("XYZ to Lab Conversion")
struct XYZToLabTests {

    @Test("D65 white point converts to Lab (100, 0, 0)")
    func d65WhiteToLab() {
        // The D65 white point in XYZ should produce Lab (100, 0, 0) by definition.
        let white = CIEXYZ(X: 0.95047, Y: 1.0, Z: 1.08883)
        let lab = white.toLab(referenceWhite: CIELab.d65White)

        expectApprox(lab.L, 100.0, tolerance: 0.001)
        expectApprox(lab.a, 0.0, tolerance: 0.001)
        expectApprox(lab.b, 0.0, tolerance: 0.001)
    }

    @Test("Pure black XYZ (0,0,0) converts to Lab L*=0")
    func blackXYZToLab() {
        let black = CIEXYZ(X: 0.0, Y: 0.0, Z: 0.0)
        let lab = black.toLab()

        expectApprox(lab.L, 0.0, tolerance: 0.001)
    }

    @Test("sRGB pure red through XYZ to Lab gives known values")
    func sRGBRedToLab() {
        // Pure red linear sRGB (1,0,0) -> XYZ -> Lab
        let red = LinearRGB(r: 1.0, g: 0.0, b: 0.0)
        let xyz = red.toXYZ(colorSpace: .sRGB)
        let lab = xyz.toLab()

        // Known reference values for sRGB red in Lab (D65)
        // L* ~ 53.233, a* ~ 80.109, b* ~ 67.220
        expectApprox(lab.L, 53.233, tolerance: 0.1)
        expectApprox(lab.a, 80.109, tolerance: 0.2)
        expectApprox(lab.b, 67.220, tolerance: 0.2)
    }

    @Test("XYZ -> Lab -> XYZ roundtrip preserves values")
    func xyzLabRoundtrip() {
        // Test several XYZ values for roundtrip accuracy
        let testCases: [(X: Double, Y: Double, Z: Double)] = [
            (0.95047, 1.0, 1.08883),   // D65 white
            (0.4124564, 0.2126729, 0.0193339),  // sRGB red
            (0.3575761, 0.7151522, 0.1191920),  // sRGB green
            (0.1804375, 0.0721750, 0.9503041),  // sRGB blue
            (0.5, 0.5, 0.5),           // Mid-gray-ish
        ]

        for tc in testCases {
            let original = CIEXYZ(X: tc.X, Y: tc.Y, Z: tc.Z)
            let lab = original.toLab()
            let recovered = lab.toXYZ()

            expectApprox(recovered.X, original.X, tolerance: 0.0001)
            expectApprox(recovered.Y, original.Y, tolerance: 0.0001)
            expectApprox(recovered.Z, original.Z, tolerance: 0.0001)
        }
    }

    @Test("Lab -> XYZ -> Lab roundtrip preserves values")
    func labXYZRoundtrip() {
        let testCases: [(L: Double, a: Double, b: Double)] = [
            (100.0, 0.0, 0.0),     // White
            (50.0, 0.0, 0.0),      // Mid-gray
            (0.0, 0.0, 0.0),       // Black
            (53.233, 80.109, 67.220),  // sRGB red
            (87.737, -86.185, 83.181), // sRGB green
        ]

        for tc in testCases {
            let original = CIELab(L: tc.L, a: tc.a, b: tc.b)
            let xyz = original.toXYZ()
            let recovered = xyz.toLab()

            expectApprox(recovered.L, original.L, tolerance: 0.001)
            expectApprox(recovered.a, original.a, tolerance: 0.001)
            expectApprox(recovered.b, original.b, tolerance: 0.001)
        }
    }
}

// MARK: - sRGB <-> XYZ Roundtrip Tests

@Suite("sRGB to XYZ Conversion")
struct SRGBToXYZTests {

    @Test("Pure red (1,0,0) maps to known XYZ")
    func pureRedToXYZ() {
        let red = LinearRGB(r: 1.0, g: 0.0, b: 0.0)
        let xyz = red.toXYZ(colorSpace: .sRGB)

        expectApprox(xyz.X, 0.4124564, tolerance: 0.0001)
        expectApprox(xyz.Y, 0.2126729, tolerance: 0.0001)
        expectApprox(xyz.Z, 0.0193339, tolerance: 0.0001)
    }

    @Test("Pure green (0,1,0) maps to known XYZ")
    func pureGreenToXYZ() {
        let green = LinearRGB(r: 0.0, g: 1.0, b: 0.0)
        let xyz = green.toXYZ(colorSpace: .sRGB)

        expectApprox(xyz.X, 0.3575761, tolerance: 0.0001)
        expectApprox(xyz.Y, 0.7151522, tolerance: 0.0001)
        expectApprox(xyz.Z, 0.1191920, tolerance: 0.0001)
    }

    @Test("Pure blue (0,0,1) maps to known XYZ")
    func pureBlueToXYZ() {
        let blue = LinearRGB(r: 0.0, g: 0.0, b: 1.0)
        let xyz = blue.toXYZ(colorSpace: .sRGB)

        expectApprox(xyz.X, 0.1804375, tolerance: 0.0001)
        expectApprox(xyz.Y, 0.0721750, tolerance: 0.0001)
        expectApprox(xyz.Z, 0.9503041, tolerance: 0.0001)
    }

    @Test("White (1,1,1) maps to approximately D65 white point")
    func pureWhiteToXYZ() {
        let white = LinearRGB(r: 1.0, g: 1.0, b: 1.0)
        let xyz = white.toXYZ(colorSpace: .sRGB)

        // Sum of the three columns should give the D65 white point
        expectApprox(xyz.X, 0.95047, tolerance: 0.001)
        expectApprox(xyz.Y, 1.0, tolerance: 0.001)
        expectApprox(xyz.Z, 1.08883, tolerance: 0.001)
    }

    @Test("Black (0,0,0) maps to XYZ (0,0,0)")
    func pureBlackToXYZ() {
        let black = LinearRGB(r: 0.0, g: 0.0, b: 0.0)
        let xyz = black.toXYZ(colorSpace: .sRGB)

        expectApprox(xyz.X, 0.0)
        expectApprox(xyz.Y, 0.0)
        expectApprox(xyz.Z, 0.0)
    }

    @Test("Linear RGB -> XYZ -> Linear RGB roundtrip")
    func rgbXYZRoundtrip() {
        let testColors: [(r: Double, g: Double, b: Double)] = [
            (1.0, 0.0, 0.0),
            (0.0, 1.0, 0.0),
            (0.0, 0.0, 1.0),
            (1.0, 1.0, 1.0),
            (0.5, 0.3, 0.7),
            (0.0, 0.0, 0.0),
            (0.2, 0.8, 0.4),
        ]

        for tc in testColors {
            let original = LinearRGB(r: tc.r, g: tc.g, b: tc.b)
            let xyz = original.toXYZ(colorSpace: .sRGB)
            let recovered = LinearRGB.fromXYZ(xyz, colorSpace: .sRGB)

            expectApprox(recovered.r, original.r, tolerance: 0.0001)
            expectApprox(recovered.g, original.g, tolerance: 0.0001)
            expectApprox(recovered.b, original.b, tolerance: 0.0001)
        }
    }

    @Test("XYZ -> Linear RGB -> XYZ roundtrip for DCI-P3")
    func xyzRoundtripDCIP3() {
        let original = CIEXYZ(X: 0.5, Y: 0.4, Z: 0.3)
        let rgb = LinearRGB.fromXYZ(original, colorSpace: .dciP3)
        let recovered = rgb.toXYZ(colorSpace: .dciP3)

        expectApprox(recovered.X, original.X, tolerance: 0.001)
        expectApprox(recovered.Y, original.Y, tolerance: 0.001)
        expectApprox(recovered.Z, original.Z, tolerance: 0.001)
    }

    @Test("XYZ -> Linear RGB -> XYZ roundtrip for Rec.2020")
    func xyzRoundtripRec2020() {
        let original = CIEXYZ(X: 0.5, Y: 0.4, Z: 0.3)
        let rgb = LinearRGB.fromXYZ(original, colorSpace: .rec2020)
        let recovered = rgb.toXYZ(colorSpace: .rec2020)

        expectApprox(recovered.X, original.X, tolerance: 0.001)
        expectApprox(recovered.Y, original.Y, tolerance: 0.001)
        expectApprox(recovered.Z, original.Z, tolerance: 0.001)
    }
}

// MARK: - Delta-E 2000 Tests

@Suite("Delta-E 2000 (CIEDE2000)")
struct DeltaE2000Tests {

    // Reference pairs from Sharma, Wu & Dalal (2005), Table 1
    // "The CIEDE2000 Color-Difference Formula: Implementation Notes,
    //  Supplementary Test Data, and Mathematical Observations."

    @Test("Sharma pair 1: dE = 2.0425")
    func sharmaPair1() {
        let lab1 = CIELab(L: 50.0, a: 2.6772, b: -79.7751)
        let lab2 = CIELab(L: 50.0, a: 0.0, b: -82.7485)
        let dE = deltaE2000(lab1, lab2)
        expectApprox(dE, 2.0425, tolerance: 0.001)
    }

    @Test("Sharma pair 2: dE = 2.8615")
    func sharmaPair2() {
        let lab1 = CIELab(L: 50.0, a: 3.1571, b: -77.2803)
        let lab2 = CIELab(L: 50.0, a: 0.0, b: -82.7485)
        let dE = deltaE2000(lab1, lab2)
        expectApprox(dE, 2.8615, tolerance: 0.001)
    }

    @Test("Sharma pair 3: dE = 3.4412")
    func sharmaPair3() {
        let lab1 = CIELab(L: 50.0, a: 2.8361, b: -74.0200)
        let lab2 = CIELab(L: 50.0, a: 0.0, b: -82.7485)
        let dE = deltaE2000(lab1, lab2)
        expectApprox(dE, 3.4412, tolerance: 0.001)
    }

    @Test("Sharma pair 4: dE = 1.0000")
    func sharmaPair4() {
        let lab1 = CIELab(L: 50.0, a: -1.3802, b: -84.2814)
        let lab2 = CIELab(L: 50.0, a: 0.0, b: -82.7485)
        let dE = deltaE2000(lab1, lab2)
        expectApprox(dE, 1.0000, tolerance: 0.001)
    }

    @Test("Sharma pair 5: near-neutral dE = 2.3669")
    func sharmaPair5() {
        let lab1 = CIELab(L: 50.0, a: 0.0, b: 0.0)
        let lab2 = CIELab(L: 50.0, a: -1.0, b: 2.0)
        let dE = deltaE2000(lab1, lab2)
        expectApprox(dE, 2.3669, tolerance: 0.001)
    }

    @Test("Identical colors produce dE = 0")
    func identicalColors() {
        let lab = CIELab(L: 50.0, a: 25.0, b: -10.0)
        let dE = deltaE2000(lab, lab)
        expectApprox(dE, 0.0, tolerance: 0.0001)
    }

    @Test("dE is symmetric: dE(a,b) == dE(b,a)")
    func symmetry() {
        let lab1 = CIELab(L: 50.0, a: 2.6772, b: -79.7751)
        let lab2 = CIELab(L: 50.0, a: 0.0, b: -82.7485)
        let dE_forward = deltaE2000(lab1, lab2)
        let dE_reverse = deltaE2000(lab2, lab1)
        expectApprox(dE_forward, dE_reverse, tolerance: 0.0001)
    }

    @Test("dE is non-negative")
    func nonNegative() {
        let lab1 = CIELab(L: 30.0, a: -20.0, b: 40.0)
        let lab2 = CIELab(L: 80.0, a: 30.0, b: -50.0)
        let dE = deltaE2000(lab1, lab2)
        #expect(dE >= 0.0, "Delta-E must be non-negative, got \(dE)")
    }

    @Test("CIE76 Euclidean distance for known pair")
    func deltaE76Known() {
        let lab1 = CIELab(L: 50.0, a: 0.0, b: 0.0)
        let lab2 = CIELab(L: 50.0, a: 3.0, b: 4.0)
        let dE = deltaE76(lab1, lab2)
        // sqrt(0 + 9 + 16) = 5.0
        expectApprox(dE, 5.0, tolerance: 0.0001)
    }
}

// MARK: - Bradford Chromatic Adaptation Tests

@Suite("Bradford Chromatic Adaptation")
struct BradfordAdaptationTests {

    @Test("D65 to D50 and back roundtrip preserves XYZ")
    func d65ToD50Roundtrip() {
        let original = CIEXYZ(X: 0.4124564, Y: 0.2126729, Z: 0.0193339)
        let adapted = bradfordAdapt(original, from: .d65, to: .d50)
        let recovered = bradfordAdapt(adapted, from: .d50, to: .d65)

        expectApprox(recovered.X, original.X, tolerance: 0.0001)
        expectApprox(recovered.Y, original.Y, tolerance: 0.0001)
        expectApprox(recovered.Z, original.Z, tolerance: 0.0001)
    }

    @Test("D65 white point adapts to D50 white point")
    func d65WhiteToD50White() {
        // Adapting the D65 white point to D50 should produce the D50 white point
        let d65White = Illuminant.d65.whitePoint
        let adapted = bradfordAdapt(d65White, from: .d65, to: .d50)
        let d50White = Illuminant.d50.whitePoint

        expectApprox(adapted.X, d50White.X, tolerance: 0.001)
        expectApprox(adapted.Y, d50White.Y, tolerance: 0.001)
        expectApprox(adapted.Z, d50White.Z, tolerance: 0.001)
    }

    @Test("Same illuminant returns input unchanged")
    func sameIlluminantIdentity() {
        let original = CIEXYZ(X: 0.5, Y: 0.4, Z: 0.3)
        let adapted = bradfordAdapt(original, from: .d65, to: .d65)

        // Should be exactly identical (no-op path)
        #expect(adapted.X == original.X)
        #expect(adapted.Y == original.Y)
        #expect(adapted.Z == original.Z)
    }

    @Test("Adaptation preserves Y=1 for white point transforms")
    func adaptationPreservesLuminance() {
        // Adapting any illuminant's white point to another should preserve Y=1
        let d65White = Illuminant.d65.whitePoint
        let adapted = bradfordAdapt(d65White, from: .d65, to: .d55)

        expectApprox(adapted.Y, 1.0, tolerance: 0.001)
    }

    @Test("Roundtrip through multiple illuminants returns to start")
    func multiHopRoundtrip() {
        let original = CIEXYZ(X: 0.3, Y: 0.4, Z: 0.5)
        let step1 = bradfordAdapt(original, from: .d65, to: .d50)
        let step2 = bradfordAdapt(step1, from: .d50, to: .a)
        let step3 = bradfordAdapt(step2, from: .a, to: .d55)
        let recovered = bradfordAdapt(step3, from: .d55, to: .d65)

        expectApprox(recovered.X, original.X, tolerance: 0.001)
        expectApprox(recovered.Y, original.Y, tolerance: 0.001)
        expectApprox(recovered.Z, original.Z, tolerance: 0.001)
    }

    @Test("bradfordAdaptationMatrix produces same result as bradfordAdapt")
    func matrixMatchesFunction() {
        let original = CIEXYZ(X: 0.4, Y: 0.3, Z: 0.6)
        let adapted = bradfordAdapt(original, from: .d65, to: .d50)

        let matrix = bradfordAdaptationMatrix(from: .d65, to: .d50)
        let matrixResult = CIEXYZ(
            X: matrix[0][0] * original.X + matrix[0][1] * original.Y + matrix[0][2] * original.Z,
            Y: matrix[1][0] * original.X + matrix[1][1] * original.Y + matrix[1][2] * original.Z,
            Z: matrix[2][0] * original.X + matrix[2][1] * original.Y + matrix[2][2] * original.Z
        )

        expectApprox(matrixResult.X, adapted.X, tolerance: 0.0001)
        expectApprox(matrixResult.Y, adapted.Y, tolerance: 0.0001)
        expectApprox(matrixResult.Z, adapted.Z, tolerance: 0.0001)
    }

    @Test("Black adapts to black under any illuminant pair")
    func blackRemainsBlack() {
        let black = CIEXYZ(X: 0.0, Y: 0.0, Z: 0.0)
        let adapted = bradfordAdapt(black, from: .d65, to: .a)

        expectApprox(adapted.X, 0.0, tolerance: 0.0001)
        expectApprox(adapted.Y, 0.0, tolerance: 0.0001)
        expectApprox(adapted.Z, 0.0, tolerance: 0.0001)
    }
}

// MARK: - sRGB Companding Tests

@Suite("sRGB Companding (Gamma Functions)")
struct SRGBCompandingTests {

    @Test("Linear 0.0 maps to sRGB 0.0")
    func linearZeroToSRGBZero() {
        expectApprox(sRGBCompand(0.0), 0.0)
    }

    @Test("Linear 1.0 maps to sRGB 1.0")
    func linearOneToSRGBOne() {
        expectApprox(sRGBCompand(1.0), 1.0)
    }

    @Test("Linear 0.5 maps to sRGB approximately 0.7354")
    func linearHalfToSRGB() {
        expectApprox(sRGBCompand(0.5), 0.7354, tolerance: 0.001)
    }

    @Test("sRGB 0.0 linearizes to 0.0")
    func srgbZeroToLinearZero() {
        expectApprox(sRGBLinearize(0.0), 0.0)
    }

    @Test("sRGB 1.0 linearizes to 1.0")
    func srgbOneToLinearOne() {
        expectApprox(sRGBLinearize(1.0), 1.0)
    }

    @Test("Roundtrip: linearize(compand(x)) approx x")
    func srgbRoundtrip() {
        let testValues = [0.0, 0.001, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
        for x in testValues {
            let roundtripped = sRGBLinearize(sRGBCompand(x))
            expectApprox(roundtripped, x, tolerance: 0.0001)
        }
    }

    @Test("Roundtrip: compand(linearize(x)) approx x")
    func srgbReverseRoundtrip() {
        let testValues = [0.0, 0.01, 0.04, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
        for x in testValues {
            let roundtripped = sRGBCompand(sRGBLinearize(x))
            expectApprox(roundtripped, x, tolerance: 0.0001)
        }
    }

    @Test("sRGB compand is monotonically increasing")
    func srgbMonotonicity() {
        var prev = sRGBCompand(0.0)
        for i in 1...100 {
            let x = Double(i) / 100.0
            let current = sRGBCompand(x)
            #expect(current >= prev, "sRGBCompand not monotonic at x=\(x)")
            prev = current
        }
    }

    @Test("Linear toe region uses linear formula")
    func linearToeRegion() {
        // Values in the linear segment (linear <= 0.0031308)
        let linear = 0.002
        let expected = 12.92 * linear
        expectApprox(sRGBCompand(linear), expected, tolerance: 0.0001)
    }

    @Test("Simple gamma encode/decode roundtrip")
    func simpleGammaRoundtrip() {
        let testValues = [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]
        let gammaValues = [1.8, 2.0, 2.2, 2.4, 2.6]

        for gamma in gammaValues {
            for x in testValues {
                let encoded = gammaEncode(x, gamma: gamma)
                let decoded = gammaDecode(encoded, gamma: gamma)
                expectApprox(decoded, x, tolerance: 0.0001)
            }
        }
    }

    @Test("Rec.709 encode/decode roundtrip")
    func rec709Roundtrip() {
        let testValues = [0.0, 0.001, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
        for x in testValues {
            let encoded = rec709Encode(x)
            let decoded = rec709Decode(encoded)
            expectApprox(decoded, x, tolerance: 0.001)
        }
    }
}

// MARK: - LCh Conversion Tests

@Suite("Lab to LCh Conversion")
struct LabLChTests {

    @Test("Achromatic Lab (a=0, b=0) gives C=0")
    func achromaticLabToLCh() {
        let lab = CIELab(L: 50.0, a: 0.0, b: 0.0)
        let lch = lab.toLCh()

        expectApprox(lch.L, 50.0)
        expectApprox(lch.C, 0.0)
    }

    @Test("Lab -> LCh -> Lab roundtrip")
    func labLChRoundtrip() {
        let testCases: [(L: Double, a: Double, b: Double)] = [
            (50.0, 30.0, 40.0),
            (80.0, -20.0, 60.0),
            (25.0, 50.0, -30.0),
            (100.0, 0.0, 0.0),
        ]

        for tc in testCases {
            let original = CIELab(L: tc.L, a: tc.a, b: tc.b)
            let lch = original.toLCh()
            let recovered = lch.toLab()

            expectApprox(recovered.L, original.L, tolerance: 0.0001)
            expectApprox(recovered.a, original.a, tolerance: 0.0001)
            expectApprox(recovered.b, original.b, tolerance: 0.0001)
        }
    }

    @Test("LCh hue angle is in [0, 360) range")
    func lchHueRange() {
        let testCases: [(a: Double, b: Double)] = [
            (1.0, 0.0),    // 0 degrees
            (0.0, 1.0),    // 90 degrees
            (-1.0, 0.0),   // 180 degrees
            (0.0, -1.0),   // 270 degrees
            (1.0, 1.0),    // 45 degrees
            (-1.0, -1.0),  // 225 degrees
        ]

        for tc in testCases {
            let lab = CIELab(L: 50.0, a: tc.a, b: tc.b)
            let lch = lab.toLCh()
            #expect(lch.h >= 0.0 && lch.h < 360.0,
                    "Hue \(lch.h) out of [0, 360) range for a=\(tc.a), b=\(tc.b)")
        }
    }
}

// MARK: - xyY Conversion Tests

@Suite("xyY and XYZ Conversion")
struct XYYConversionTests {

    @Test("D65 chromaticity converts correctly to XYZ")
    func d65ChromaticityToXYZ() {
        let xyy = CIExyY(x: 0.3127, y: 0.3290, Y: 1.0)
        let xyz = xyy.toXYZ()

        // X = (Y/y)*x = (1/0.329)*0.3127 ≈ 0.9505
        // Z = (Y/y)*(1-x-y) = (1/0.329)*(1-0.3127-0.329) ≈ 1.0890
        expectApprox(xyz.X, 0.9505, tolerance: 0.001)
        expectApprox(xyz.Y, 1.0, tolerance: 0.0001)
        expectApprox(xyz.Z, 1.0890, tolerance: 0.001)
    }

    @Test("XYZ -> xyY -> XYZ roundtrip")
    func xyzXYYRoundtrip() {
        let original = CIEXYZ(X: 0.5, Y: 0.4, Z: 0.3)
        let xyy = original.toxyY()
        let recovered = xyy.toXYZ()

        expectApprox(recovered.X, original.X, tolerance: 0.0001)
        expectApprox(recovered.Y, original.Y, tolerance: 0.0001)
        expectApprox(recovered.Z, original.Z, tolerance: 0.0001)
    }

    @Test("Zero XYZ produces zero xyY")
    func zeroXYZToxyY() {
        let zero = CIEXYZ(X: 0.0, Y: 0.0, Z: 0.0)
        let xyy = zero.toxyY()

        expectApprox(xyy.x, 0.0)
        expectApprox(xyy.y, 0.0)
        expectApprox(xyy.Y, 0.0)
    }

    @Test("Zero y in xyY produces zero XYZ")
    func zeroYChromaticity() {
        let xyy = CIExyY(x: 0.3, y: 0.0, Y: 1.0)
        let xyz = xyy.toXYZ()

        expectApprox(xyz.X, 0.0)
        expectApprox(xyz.Y, 0.0)
        expectApprox(xyz.Z, 0.0)
    }
}

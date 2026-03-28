// GammaModelTests.swift — Tests for TransferFunction, LUTGenerator, and BitDepthOptimizer
//
// Verifies transfer function encode/decode roundtrips, LUT generation correctness,
// and bit depth optimization properties (monotonicity, banding risk, near-black).

import Foundation
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

// MARK: - TransferFunction Power Law Tests

@Suite("TransferFunction Power Law")
struct TransferFunctionPowerLawTests {

    @Test("Power law encode/decode roundtrip")
    func powerLawRoundtrip() {
        let tf = TransferFunction.powerLaw(gamma: 2.2)
        let testValues = [0.0, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for x in testValues {
            let encoded = tf.encode(x)
            let decoded = tf.decode(encoded)
            expectApprox(decoded, x, tolerance: 0.0001)
        }
    }

    @Test("Power law decode: V^gamma for known values")
    func powerLawDecode() {
        let tf = TransferFunction.powerLaw(gamma: 2.0)

        // 0.5^2.0 = 0.25
        expectApprox(tf.decode(0.5), 0.25, tolerance: 0.0001)
        // 1.0^2.0 = 1.0
        expectApprox(tf.decode(1.0), 1.0)
        // 0.0^2.0 = 0.0
        expectApprox(tf.decode(0.0), 0.0)
    }

    @Test("Power law encode: V^(1/gamma) for known values")
    func powerLawEncode() {
        let tf = TransferFunction.powerLaw(gamma: 2.0)

        // 0.25^(1/2.0) = 0.5
        expectApprox(tf.encode(0.25), 0.5, tolerance: 0.0001)
        // 1.0^(1/2.0) = 1.0
        expectApprox(tf.encode(1.0), 1.0)
        // 0.0^(1/2.0) = 0.0
        expectApprox(tf.encode(0.0), 0.0)
    }

    @Test("Power law with gamma 1.0 is identity")
    func powerLawGammaOne() {
        let tf = TransferFunction.powerLaw(gamma: 1.0)
        let testValues = [0.0, 0.1, 0.5, 0.9, 1.0]

        for x in testValues {
            expectApprox(tf.decode(x), x, tolerance: 0.0001)
            expectApprox(tf.encode(x), x, tolerance: 0.0001)
        }
    }

    @Test("Power law with gamma 2.4 (BT.1886 standard)")
    func powerLawGamma24() {
        let tf = TransferFunction.powerLaw(gamma: 2.4)

        // 0.5^2.4 ≈ 0.18946
        expectApprox(tf.decode(0.5), pow(0.5, 2.4), tolerance: 0.0001)
    }

    @Test("Power law with various gammas roundtrip")
    func variousGammasRoundtrip() {
        let gammas = [1.8, 2.0, 2.2, 2.4, 2.6]
        for gamma in gammas {
            let tf = TransferFunction.powerLaw(gamma: gamma)
            let val = 0.42
            let roundtripped = tf.decode(tf.encode(val))
            expectApprox(roundtripped, val, tolerance: 0.0001)
        }
    }
}

// MARK: - TransferFunction BT.1886 Tests

@Suite("TransferFunction BT.1886")
struct TransferFunctionBT1886Tests {

    @Test("BT.1886 with zero black level matches power law 2.4")
    func bt1886ZeroBlackMatchesPowerLaw() {
        let bt1886 = TransferFunction.bt1886(blackLevel: 0.0, whiteLevel: 1.0)
        let power24 = TransferFunction.powerLaw(gamma: 2.4)

        let testValues = [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]
        for v in testValues {
            let bt1886Result = bt1886.decode(v)
            let powerResult = power24.decode(v)
            expectApprox(bt1886Result, powerResult, tolerance: 0.001)
        }
    }

    @Test("BT.1886 encode/decode roundtrip with zero black level")
    func bt1886RoundtripZeroBlack() {
        let tf = TransferFunction.bt1886(blackLevel: 0.0, whiteLevel: 1.0)
        let testValues = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for x in testValues {
            let encoded = tf.encode(x)
            let decoded = tf.decode(encoded)
            expectApprox(decoded, x, tolerance: 0.001)
        }
    }

    @Test("BT.1886 encode/decode roundtrip with non-zero black level")
    func bt1886RoundtripNonZeroBlack() {
        let tf = TransferFunction.bt1886(blackLevel: 0.005, whiteLevel: 1.0)
        let testValues = [0.005, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0]

        for x in testValues {
            let encoded = tf.encode(x)
            let decoded = tf.decode(encoded)
            expectApprox(decoded, x, tolerance: 0.001)
        }
    }

    @Test("BT.1886 decode(0) gives black level luminance")
    func bt1886DecodeZero() {
        let blackLevel = 0.005
        let tf = TransferFunction.bt1886(blackLevel: blackLevel, whiteLevel: 1.0)
        let result = tf.decode(0.0)
        // At signal 0, the output should be close to the black level
        expectApprox(result, blackLevel, tolerance: 0.001)
    }

    @Test("BT.1886 decode(1) gives white level luminance")
    func bt1886DecodeOne() {
        let tf = TransferFunction.bt1886(blackLevel: 0.0, whiteLevel: 1.0)
        let result = tf.decode(1.0)
        expectApprox(result, 1.0, tolerance: 0.001)
    }

    @Test("BT.1886 is monotonically increasing")
    func bt1886Monotonicity() {
        let tf = TransferFunction.bt1886(blackLevel: 0.005, whiteLevel: 1.0)
        var prev = tf.decode(0.0)

        for i in 1...100 {
            let v = Double(i) / 100.0
            let current = tf.decode(v)
            #expect(current >= prev, "BT.1886 not monotonic at v=\(v)")
            prev = current
        }
    }
}

// MARK: - TransferFunction sRGB Tests

@Suite("TransferFunction sRGB")
struct TransferFunctionSRGBTests {

    @Test("sRGB transfer function matches standalone sRGBCompand/sRGBLinearize")
    func srgbTFMatchesStandalone() {
        let tf = TransferFunction.sRGB
        let testValues = [0.0, 0.001, 0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for x in testValues {
            // encode (linear -> signal) should match sRGBCompand
            let tfEncoded = tf.encode(x)
            let standaloneEncoded = sRGBCompand(x)
            expectApprox(tfEncoded, standaloneEncoded, tolerance: 0.0001)

            // decode (signal -> linear) should match sRGBLinearize
            let tfDecoded = tf.decode(x)
            let standaloneDecoded = sRGBLinearize(x)
            expectApprox(tfDecoded, standaloneDecoded, tolerance: 0.0001)
        }
    }

    @Test("sRGB transfer function encode/decode roundtrip")
    func srgbTFRoundtrip() {
        let tf = TransferFunction.sRGB
        let testValues = [0.0, 0.001, 0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]

        for x in testValues {
            let roundtripped = tf.decode(tf.encode(x))
            expectApprox(roundtripped, x, tolerance: 0.0001)
        }
    }

    @Test("sRGB decode/encode roundtrip")
    func srgbTFReverseRoundtrip() {
        let tf = TransferFunction.sRGB
        let testValues = [0.0, 0.01, 0.04, 0.1, 0.5, 0.9, 1.0]

        for x in testValues {
            let roundtripped = tf.encode(tf.decode(x))
            expectApprox(roundtripped, x, tolerance: 0.0001)
        }
    }

    @Test("sRGB decode(0) = 0 and decode(1) = 1")
    func srgbTFBoundaries() {
        let tf = TransferFunction.sRGB
        expectApprox(tf.decode(0.0), 0.0)
        expectApprox(tf.decode(1.0), 1.0)
        expectApprox(tf.encode(0.0), 0.0)
        expectApprox(tf.encode(1.0), 1.0)
    }
}

// MARK: - TransferFunction PQ & HLG Tests

@Suite("TransferFunction PQ and HLG")
struct TransferFunctionPQHLGTests {

    @Test("PQ encode/decode roundtrip")
    func pqRoundtrip() {
        let tf = TransferFunction.pq
        let testValues = [0.0, 0.001, 0.01, 0.1, 0.5, 0.9, 1.0]

        for x in testValues {
            let encoded = tf.encode(x)
            let decoded = tf.decode(encoded)
            expectApprox(decoded, x, tolerance: 0.001)
        }
    }

    @Test("PQ boundaries: decode(0) = 0, decode(1) approx 1")
    func pqBoundaries() {
        let tf = TransferFunction.pq
        expectApprox(tf.decode(0.0), 0.0, tolerance: 0.0001)
        expectApprox(tf.decode(1.0), 1.0, tolerance: 0.001)
    }

    @Test("HLG encode/decode roundtrip")
    func hlgRoundtrip() {
        let tf = TransferFunction.hlg
        let testValues = [0.0, 0.001, 0.01, 0.05, 0.1, 0.5, 0.9, 1.0]

        for x in testValues {
            let encoded = tf.encode(x)
            let decoded = tf.decode(encoded)
            expectApprox(decoded, x, tolerance: 0.001)
        }
    }

    @Test("HLG boundaries")
    func hlgBoundaries() {
        let tf = TransferFunction.hlg
        expectApprox(tf.decode(0.0), 0.0, tolerance: 0.0001)
    }
}

// MARK: - LUT Generator Tests

@Suite("LUT Generator")
struct LUTGeneratorTests {

    @Test("Identity LUT passes through unchanged")
    func identityLUT() {
        let lut = LUTGenerator.generateIdentityLUT(size: 256)

        #expect(lut.size == 256)
        #expect(lut.red.count == 256)
        #expect(lut.green.count == 256)
        #expect(lut.blue.count == 256)

        for i in 0..<256 {
            let expected = Double(i) / 255.0
            expectApprox(lut.red[i], expected, tolerance: 0.0001)
            expectApprox(lut.green[i], expected, tolerance: 0.0001)
            expectApprox(lut.blue[i], expected, tolerance: 0.0001)
        }
    }

    @Test("Identity LUT starts at 0 and ends at 1")
    func identityLUTBounds() {
        let lut = LUTGenerator.generateIdentityLUT(size: 1024)

        expectApprox(lut.red[0], 0.0)
        expectApprox(lut.red[1023], 1.0)
        expectApprox(lut.green[0], 0.0)
        expectApprox(lut.green[1023], 1.0)
        expectApprox(lut.blue[0], 0.0)
        expectApprox(lut.blue[1023], 1.0)
    }

    @Test("Identity LUT is monotonically increasing")
    func identityLUTMonotonic() {
        let lut = LUTGenerator.generateIdentityLUT(size: 256)

        for i in 1..<256 {
            #expect(lut.red[i] >= lut.red[i - 1], "Red channel not monotonic at index \(i)")
        }
    }

    @Test("Gamma LUT with gamma 1.0 equals identity")
    func gammaLUTIdentity() {
        let gammaLUT = LUTGenerator.generateGammaLUT(gamma: 1.0, size: 256)
        let identityLUT = LUTGenerator.generateIdentityLUT(size: 256)

        for i in 0..<256 {
            expectApprox(gammaLUT.red[i], identityLUT.red[i], tolerance: 0.0001)
        }
    }

    @Test("Gamma LUT applies correct power law")
    func gammaLUTCorrectValues() {
        let gamma = 2.2
        let lut = LUTGenerator.generateGammaLUT(gamma: gamma, size: 256)

        // At index 128, normalized = 128/255 ≈ 0.50196
        // Output = 0.50196^(1/2.2) ≈ 0.7297
        let idx = 128
        let normalized = Double(idx) / 255.0
        let expected = pow(normalized, 1.0 / gamma)
        expectApprox(lut.red[idx], expected, tolerance: 0.0001)
    }

    @Test("Calibration LUT from same TF to same TF is identity")
    func calibrationLUTSameFunction() {
        let tf = TransferFunction.powerLaw(gamma: 2.2)
        let lut = LUTGenerator.generateCalibrationLUT(from: tf, to: tf, size: 256)

        for i in 0..<256 {
            let expected = Double(i) / 255.0
            expectApprox(lut.red[i], expected, tolerance: 0.001)
        }
    }

    @Test("Calibration LUT is monotonically increasing")
    func calibrationLUTMonotonic() {
        let source = TransferFunction.powerLaw(gamma: 2.0)
        let target = TransferFunction.powerLaw(gamma: 2.4)
        let lut = LUTGenerator.generateCalibrationLUT(from: source, to: target, size: 256)

        for i in 1..<256 {
            #expect(lut.red[i] >= lut.red[i - 1],
                    "Calibration LUT not monotonic at index \(i)")
        }
    }

    @Test("Calibration LUT preserves black and white")
    func calibrationLUTBounds() {
        let source = TransferFunction.powerLaw(gamma: 2.2)
        let target = TransferFunction.sRGB
        let lut = LUTGenerator.generateCalibrationLUT(from: source, to: target, size: 256)

        expectApprox(lut.red[0], 0.0, tolerance: 0.001)
        expectApprox(lut.red[255], 1.0, tolerance: 0.001)
    }

    @Test("LUT with small size (2 entries)")
    func lutMinimumSize() {
        let lut = LUTGenerator.generateIdentityLUT(size: 2)

        #expect(lut.size == 2)
        expectApprox(lut.red[0], 0.0)
        expectApprox(lut.red[1], 1.0)
    }

    @Test("All three channels of identity LUT are identical")
    func identityLUTChannelsMatch() {
        let lut = LUTGenerator.generateIdentityLUT(size: 64)

        for i in 0..<64 {
            #expect(lut.red[i] == lut.green[i])
            #expect(lut.green[i] == lut.blue[i])
        }
    }
}

// MARK: - BitDepthOptimizer Tests

@Suite("BitDepthOptimizer")
struct BitDepthOptimizerTests {

    @Test("Optimized ramp is monotonically increasing")
    func optimizedRampMonotonic() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.2,
            targetGamma: 2.4
        )

        #expect(ramp.count == 256)

        for i in 1..<ramp.count {
            #expect(ramp[i] >= ramp[i - 1],
                    "Optimized ramp not monotonic at index \(i): \(ramp[i-1]) -> \(ramp[i])")
        }
    }

    @Test("Optimized ramp values are in [0, 1]")
    func optimizedRampBounds() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.2,
            targetGamma: 2.4
        )

        for (i, value) in ramp.enumerated() {
            #expect(value >= 0.0 && value <= 1.0,
                    "Ramp value \(value) at index \(i) out of [0, 1]")
        }
    }

    @Test("Optimized ramp starts near 0 and ends near 1")
    func optimizedRampEndpoints() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.2,
            targetGamma: 2.4
        )

        expectApprox(ramp[0], 0.0, tolerance: 0.01)
        expectApprox(ramp[255], 1.0, tolerance: 0.01)
    }

    @Test("Banding risk of optimized ramp is lower than naive linear ramp")
    func bandingRiskLowerThanNaive() {
        let gamma = 2.4

        // Naive linear ramp: just divide [0,1] into 256 equal steps
        let naiveRamp = (0..<256).map { Double($0) / 255.0 }

        // Optimized ramp
        let optimizedRamp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: gamma,
            targetGamma: gamma
        )

        let naiveBanding = BitDepthOptimizer.bandingRisk(ramp: naiveRamp, gamma: gamma)
        let optimizedBanding = BitDepthOptimizer.bandingRisk(ramp: optimizedRamp, gamma: gamma)

        #expect(optimizedBanding < naiveBanding,
                "Optimized banding (\(optimizedBanding)) should be less than naive (\(naiveBanding))")
    }

    @Test("Near-black preservation ensures minimum steps in levels 0-10")
    func nearBlackPreservation() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.2,
            targetGamma: 2.4
        )

        // Check that near-black levels (0-10) have distinguishable steps
        let minimumStep = 0.001
        for i in 1...min(10, ramp.count - 1) {
            let step = ramp[i] - ramp[i - 1]
            #expect(step >= minimumStep,
                    "Near-black level \(i) step \(step) below minimum \(minimumStep)")
        }
    }

    @Test("preserveNearBlack nudges collapsed levels")
    func preserveNearBlackNudges() {
        // Create a ramp with collapsed near-black levels
        var ramp = [Double](repeating: 0.0, count: 256)
        for i in 0..<256 {
            ramp[i] = Double(i) / 255.0
        }
        // Collapse levels 1-5 to be identical to level 0
        for i in 1...5 {
            ramp[i] = 0.0
        }

        BitDepthOptimizer.preserveNearBlack(ramp: &ramp, minimumStep: 0.001)

        // After preservation, each level should be at least 0.001 above the previous
        for i in 1...min(10, ramp.count - 1) {
            let step = ramp[i] - ramp[i - 1]
            #expect(step >= 0.001,
                    "Level \(i) step \(step) below minimum after preservation")
        }
    }

    @Test("preserveNearBlack maintains monotonicity")
    func preserveNearBlackMonotonic() {
        var ramp = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.05, 0.1, 0.15, 0.2]

        BitDepthOptimizer.preserveNearBlack(ramp: &ramp, minimumStep: 0.001)

        for i in 1..<ramp.count {
            #expect(ramp[i] >= ramp[i - 1],
                    "Ramp not monotonic at index \(i) after preserveNearBlack")
        }
    }

    @Test("Banding risk of identity ramp is calculable")
    func bandingRiskIdentity() {
        let identityRamp = (0..<256).map { Double($0) / 255.0 }
        let risk = BitDepthOptimizer.bandingRisk(ramp: identityRamp, gamma: 2.2)

        // The risk should be a positive number
        #expect(risk > 0.0, "Identity ramp should have non-zero banding risk")
    }

    @Test("Banding risk returns 0 for single-entry ramp")
    func bandingRiskSingleEntry() {
        let risk = BitDepthOptimizer.bandingRisk(ramp: [0.5], gamma: 2.2)
        expectApprox(risk, 0.0)
    }

    @Test("Optimized ramp produces 256 entries")
    func optimizedRampSize() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.0,
            targetGamma: 2.4,
            blackLevel: 0.005,
            whiteLevel: 0.95
        )
        #expect(ramp.count == 256)
    }

    @Test("Optimized ramp with non-zero black level still monotonic")
    func optimizedRampBlackLevelMonotonic() {
        let ramp = BitDepthOptimizer.optimizeForPerceptualUniformity(
            nativeGamma: 2.2,
            targetGamma: 2.4,
            blackLevel: 0.01,
            whiteLevel: 0.95
        )

        for i in 1..<ramp.count {
            #expect(ramp[i] >= ramp[i - 1],
                    "Ramp not monotonic at index \(i) with non-zero black level")
        }
    }
}

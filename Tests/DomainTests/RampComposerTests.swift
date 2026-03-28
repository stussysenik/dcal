// RampComposerTests.swift — Tests for the gamma ramp composition pipeline

import Foundation
import Testing
@testable import Domain

// MARK: - Test Helpers

private func expectApprox(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.005,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) < tolerance,
        "Expected \(expected), got \(actual), diff \(abs(actual - expected))",
        sourceLocation: sourceLocation
    )
}

@Suite("Ramp Composer")
struct RampComposerTests {

    @Test("Neutral settings produce identity LUT")
    func neutralIsIdentity() {
        let lut = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 6500
        )
        #expect(lut.size == 256)
        for i in 0..<256 {
            let expected = Double(i) / 255.0
            expectApprox(lut.red[i], expected, tolerance: 0.02)
            expectApprox(lut.green[i], expected, tolerance: 0.02)
            expectApprox(lut.blue[i], expected, tolerance: 0.02)
        }
    }

    @Test("Brightness 50 halves the maximum output")
    func halfBrightness() {
        let lut = RampComposer.compose(
            brightness: 50, contrast: 50, whitePointKelvin: 6500
        )
        // Last entry should be ~0.5
        expectApprox(lut.red[255], 0.5, tolerance: 0.02)
        expectApprox(lut.green[255], 0.5, tolerance: 0.02)
        expectApprox(lut.blue[255], 0.5, tolerance: 0.02)
    }

    @Test("Brightness 0 produces all zeros")
    func zeroBrightness() {
        let lut = RampComposer.compose(
            brightness: 0, contrast: 50, whitePointKelvin: 6500
        )
        for i in 0..<256 {
            expectApprox(lut.red[i], 0, tolerance: 0.001)
            expectApprox(lut.green[i], 0, tolerance: 0.001)
            expectApprox(lut.blue[i], 0, tolerance: 0.001)
        }
    }

    @Test("High contrast produces steeper curve than neutral")
    func highContrastSteeper() {
        let neutral = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 6500
        )
        let high = RampComposer.compose(
            brightness: 100, contrast: 100, whitePointKelvin: 6500
        )
        // At midpoint (i=128), high contrast should be darker (steeper curve)
        #expect(high.red[128] < neutral.red[128],
                "High contrast midpoint should be darker than neutral")
    }

    @Test("Low contrast produces flatter curve than neutral")
    func lowContrastFlatter() {
        let neutral = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 6500
        )
        let low = RampComposer.compose(
            brightness: 100, contrast: 0, whitePointKelvin: 6500
        )
        // At midpoint, low contrast should be brighter (flatter curve)
        #expect(low.red[128] > neutral.red[128],
                "Low contrast midpoint should be brighter than neutral")
    }

    @Test("Warm white point has red > blue")
    func warmWhitePoint() {
        let lut = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 4000
        )
        // At the last entry (max output), red should exceed blue
        #expect(lut.red[255] > lut.blue[255],
                "At 4000K, red channel should be stronger than blue")
    }

    @Test("Cool white point has blue > red")
    func coolWhitePoint() {
        let lut = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 10000
        )
        #expect(lut.blue[255] > lut.red[255],
                "At 10000K, blue channel should be stronger than red")
    }

    @Test("All LUT values are in [0, 1]")
    func valuesInRange() {
        let testCases: [(Double, Double, Double)] = [
            (100, 50, 6500),
            (0, 0, 4000),
            (100, 100, 10000),
            (50, 75, 5000),
            (25, 25, 8000),
        ]
        for (b, c, wp) in testCases {
            let lut = RampComposer.compose(
                brightness: b, contrast: c, whitePointKelvin: wp
            )
            for i in 0..<lut.size {
                #expect(lut.red[i] >= 0 && lut.red[i] <= 1,
                        "Red[\(i)] out of range for b=\(b) c=\(c) wp=\(wp)")
                #expect(lut.green[i] >= 0 && lut.green[i] <= 1,
                        "Green[\(i)] out of range for b=\(b) c=\(c) wp=\(wp)")
                #expect(lut.blue[i] >= 0 && lut.blue[i] <= 1,
                        "Blue[\(i)] out of range for b=\(b) c=\(c) wp=\(wp)")
            }
        }
    }

    @Test("LUT is monotonically non-decreasing")
    func monotonic() {
        let testCases: [(Double, Double, Double)] = [
            (100, 50, 6500),
            (75, 80, 5500),
            (50, 20, 9000),
        ]
        for (b, c, wp) in testCases {
            let lut = RampComposer.compose(
                brightness: b, contrast: c, whitePointKelvin: wp
            )
            for i in 1..<lut.size {
                #expect(lut.red[i] >= lut.red[i - 1],
                        "Red not monotonic at \(i) for b=\(b) c=\(c) wp=\(wp)")
                #expect(lut.green[i] >= lut.green[i - 1],
                        "Green not monotonic at \(i) for b=\(b) c=\(c) wp=\(wp)")
                #expect(lut.blue[i] >= lut.blue[i - 1],
                        "Blue not monotonic at \(i) for b=\(b) c=\(c) wp=\(wp)")
            }
        }
    }

    @Test("LUT starts at 0")
    func startsAtZero() {
        let lut = RampComposer.compose(
            brightness: 100, contrast: 50, whitePointKelvin: 6500
        )
        expectApprox(lut.red[0], 0, tolerance: 0.001)
        expectApprox(lut.green[0], 0, tolerance: 0.001)
        expectApprox(lut.blue[0], 0, tolerance: 0.001)
    }
}

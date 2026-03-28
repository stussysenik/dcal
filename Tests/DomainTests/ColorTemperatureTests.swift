// ColorTemperatureTests.swift — Tests for Kelvin-to-RGB gains conversion

import Foundation
import Testing
@testable import Domain

// MARK: - Test Helpers

private func expectApprox(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.01,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(actual - expected) < tolerance,
        "Expected \(expected), got \(actual), diff \(abs(actual - expected))",
        sourceLocation: sourceLocation
    )
}

@Suite("Color Temperature Gains")
struct ColorTemperatureGainsTests {

    @Test("D65 (6500K) returns neutral gains (1, 1, 1)")
    func d65Neutral() {
        let gains = kelvinToRGBGains(6500)
        expectApprox(gains.red, 1.0, tolerance: 0.02)
        expectApprox(gains.green, 1.0, tolerance: 0.02)
        expectApprox(gains.blue, 1.0, tolerance: 0.02)
    }

    @Test("Warm temperature (4000K) has red > blue")
    func warmTemperature() {
        let gains = kelvinToRGBGains(4000)
        #expect(gains.red > gains.blue, "At 4000K red should dominate over blue")
        #expect(gains.red > gains.green, "At 4000K red should be the strongest channel")
    }

    @Test("Cool temperature (10000K) has blue > red")
    func coolTemperature() {
        let gains = kelvinToRGBGains(10000)
        #expect(gains.blue > gains.red, "At 10000K blue should dominate over red")
    }

    @Test("All gains are in [0, 1]")
    func gainsInRange() {
        for kelvin in stride(from: 4000.0, through: 10000.0, by: 500.0) {
            let gains = kelvinToRGBGains(kelvin)
            #expect(gains.red >= 0 && gains.red <= 1, "Red out of range at \(kelvin)K")
            #expect(gains.green >= 0 && gains.green <= 1, "Green out of range at \(kelvin)K")
            #expect(gains.blue >= 0 && gains.blue <= 1, "Blue out of range at \(kelvin)K")
        }
    }

    @Test("Maximum channel is always 1.0 (normalization)")
    func maxChannelIsOne() {
        for kelvin in stride(from: 4000.0, through: 10000.0, by: 500.0) {
            let gains = kelvinToRGBGains(kelvin)
            let maxGain = max(gains.red, gains.green, gains.blue)
            expectApprox(maxGain, 1.0, tolerance: 0.001)
        }
    }

    @Test("Blue gain increases monotonically with temperature")
    func blueMonotonic() {
        var previousBlue = 0.0
        for kelvin in stride(from: 4000.0, through: 10000.0, by: 500.0) {
            let gains = kelvinToRGBGains(kelvin)
            #expect(gains.blue >= previousBlue - 0.001,
                    "Blue should not decrease as temperature rises (at \(kelvin)K)")
            previousBlue = gains.blue
        }
    }

    @Test("Values are clamped at range boundaries")
    func clampedAtBoundaries() {
        let low = kelvinToRGBGains(2000) // below range — clamped to 4000
        let high = kelvinToRGBGains(20000) // above range — clamped to 10000
        #expect(low.red >= 0 && low.red <= 1)
        #expect(high.blue >= 0 && high.blue <= 1)
    }
}

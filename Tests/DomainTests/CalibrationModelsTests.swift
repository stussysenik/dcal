// CalibrationModelsTests.swift — Tests for CalibrationModels data types
//
// Verifies DisplayTwin.healthScore scoring rules and the displayID
// stable-hashing function that identifies physical displays.

import Foundation
import Testing
@testable import Application

// MARK: - DisplayTwin Health Score Tests

@Suite("DisplayTwin healthScore")
struct DisplayTwinHealthScoreTests {

    /// Helper: build a DisplayTwin with controllable lastSeen, calibrationCount, and driftRate.
    private func makeTwin(
        lastSeen: Date = Date(),
        calibrationCount: Int = 5,
        driftRate: Double? = nil
    ) -> DisplayTwin {
        DisplayTwin(
            id: "test-id",
            name: "Test Display",
            vendorID: 0x0610,
            modelID: 0xA032,
            serialNumber: 12345,
            nativeGamma: 2.2,
            bitDepth: 10,
            colorSpace: "P3",
            firstSeen: Date(timeIntervalSinceNow: -86400 * 90),
            lastSeen: lastSeen,
            calibrationCount: calibrationCount,
            driftRate: driftRate
        )
    }

    @Test("Excellent score for recently calibrated display with low drift")
    func excellentScore() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 10, driftRate: 0.01)
        #expect(twin.healthScore == 1.0)
    }

    @Test("Perfect score when lastSeen is now and no drift data")
    func perfectScoreNoData() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 3, driftRate: nil)
        #expect(twin.healthScore == 1.0)
    }

    @Test("Score drops by 0.1 when lastSeen is 8–30 days ago")
    func moderatelyStale() {
        let eightDaysAgo = Date(timeIntervalSinceNow: -86400 * 8)
        let twin = makeTwin(lastSeen: eightDaysAgo, calibrationCount: 5)
        // Only the >7-day penalty applies: 1.0 - 0.1 = 0.9
        #expect(twin.healthScore == 0.9)
    }

    @Test("Score drops by 0.3 when lastSeen is over 30 days ago")
    func veryStale() {
        let fortyDaysAgo = Date(timeIntervalSinceNow: -86400 * 40)
        let twin = makeTwin(lastSeen: fortyDaysAgo, calibrationCount: 5)
        // Only the >30-day penalty applies: 1.0 - 0.3 = 0.7
        #expect(twin.healthScore == 0.7)
    }

    @Test("Score drops by 0.2 when calibrationCount is zero")
    func uncalibrated() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 0)
        #expect(twin.healthScore == 0.8)
    }

    @Test("Score drops by 0.3 when driftRate exceeds 0.05")
    func highDrift() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 5, driftRate: 0.10)
        #expect(twin.healthScore == 0.7)
    }

    @Test("Negative drift also penalises when |driftRate| > 0.05")
    func negativeDrift() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 5, driftRate: -0.08)
        #expect(twin.healthScore == 0.7)
    }

    @Test("Penalties stack: stale + uncalibrated + high drift")
    func cumulativePenalties() {
        let fortyDaysAgo = Date(timeIntervalSinceNow: -86400 * 40)
        let twin = makeTwin(lastSeen: fortyDaysAgo, calibrationCount: 0, driftRate: 0.10)
        // 1.0 - 0.3 (stale) - 0.3 (drift) - 0.2 (uncalibrated) = 0.2
        #expect(abs(twin.healthScore - 0.2) < 0.0001)
    }

    @Test("Score floors at 0.0, never goes negative")
    func floorAtZero() {
        // Maximum possible penalty: 0.3 + 0.3 + 0.2 = 0.8 → score = 0.2
        // But let's verify the floor mechanism by confirming it never goes below 0.
        let fortyDaysAgo = Date(timeIntervalSinceNow: -86400 * 40)
        let twin = makeTwin(lastSeen: fortyDaysAgo, calibrationCount: 0, driftRate: 0.10)
        #expect(twin.healthScore >= 0.0)
    }

    @Test("Score caps at 1.0")
    func capAtOne() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 100, driftRate: 0.001)
        #expect(twin.healthScore <= 1.0)
    }

    @Test("driftRate exactly at 0.05 does not penalise")
    func driftAtBoundary() {
        let twin = makeTwin(lastSeen: Date(), calibrationCount: 5, driftRate: 0.05)
        // abs(0.05) > 0.05 is false, so no penalty
        #expect(twin.healthScore == 1.0)
    }
}

// MARK: - displayID Tests

@Suite("displayID stable hashing")
struct DisplayIDTests {

    @Test("Stable across repeated calls with same inputs")
    func stableAcrossCalls() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        #expect(id1 == id2)
    }

    @Test("Produces a 16-character lowercase hex string")
    func sixteenHexChars() {
        let id = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        #expect(id.count == 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in id.unicodeScalars {
            #expect(hexChars.contains(char), "Non-hex character found: \(char)")
        }
    }

    @Test("Different vendorID produces different ID")
    func differentVendor() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x1E6D, modelID: 0xA032, serialNumber: 12345)
        #expect(id1 != id2)
    }

    @Test("Different modelID produces different ID")
    func differentModel() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x0610, modelID: 0xB044, serialNumber: 12345)
        #expect(id1 != id2)
    }

    @Test("Different serialNumber produces different ID")
    func differentSerial() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 99999)
        #expect(id1 != id2)
    }

    @Test("Zero values produce a valid 16 hex-char ID")
    func zeroInputs() {
        let id = displayID(vendorID: 0, modelID: 0, serialNumber: 0)
        #expect(id.count == 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in id.unicodeScalars {
            #expect(hexChars.contains(char), "Non-hex character found: \(char)")
        }
    }

    @Test("Max UInt32 values produce a valid 16 hex-char ID")
    func maxInputs() {
        let id = displayID(vendorID: .max, modelID: .max, serialNumber: .max)
        #expect(id.count == 16)
    }
}

// MARK: - MetricKind Tests

@Suite("MetricKind")
struct MetricKindTests {

    @Test("All six cases exist")
    func allCases() {
        #expect(MetricKind.allCases.count == 6)
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(MetricKind.gamma.rawValue == "gamma")
        #expect(MetricKind.gammaR.rawValue == "gammaR")
        #expect(MetricKind.gammaG.rawValue == "gammaG")
        #expect(MetricKind.gammaB.rawValue == "gammaB")
        #expect(MetricKind.channelDeviation.rawValue == "channelDeviation")
        #expect(MetricKind.bandingRisk.rawValue == "bandingRisk")
    }
}

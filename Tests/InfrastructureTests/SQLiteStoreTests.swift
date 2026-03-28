// SQLiteStoreTests.swift -- Tests for the SQLite calibration store.
//
// All tests use in-memory databases (":memory:") for speed and isolation.
// Each test creates a fresh store so there's no shared state between tests.

import Foundation
import Testing
@testable import Application
@testable import Infrastructure

// MARK: - Test Helpers

/// Create a fresh in-memory SQLiteStore for each test.
private func makeStore() throws -> SQLiteStore {
    try SQLiteStore(path: ":memory:")
}

/// Build a DisplayInfo suitable for upserting into the store.
private func makeDisplayInfo(
    vendorID: UInt32 = 0x0610,
    modelID: UInt32 = 0xA032,
    serialNumber: UInt32 = 12345,
    name: String = "Test Display",
    bitDepth: Int = 10,
    colorSpace: String = "P3"
) -> DisplayInfo {
    DisplayInfo(
        id: 1,  // CGDirectDisplayID -- irrelevant for store ID
        name: name,
        resolution: (width: 2560, height: 1440),
        bitDepth: bitDepth,
        vendorID: vendorID,
        modelID: modelID,
        serialNumber: serialNumber,
        colorSpace: colorSpace,
        estimatedNativeGamma: 2.2
    )
}

/// Generate the stable display ID for the default test display.
private func testDisplayID(
    vendorID: UInt32 = 0x0610,
    modelID: UInt32 = 0xA032,
    serialNumber: UInt32 = 12345
) -> String {
    displayID(vendorID: vendorID, modelID: modelID, serialNumber: serialNumber)
}

/// Build a MeasurementRecord for testing.
private func makeMeasurement(
    displayID: String,
    timestamp: Date = Date(),
    gammaR: Double = 2.18,
    gammaG: Double = 2.20,
    gammaB: Double = 2.22,
    gamma: Double = 2.20
) -> MeasurementRecord {
    MeasurementRecord(
        id: "auto",
        displayID: displayID,
        timestamp: timestamp,
        gammaR: gammaR,
        gammaG: gammaG,
        gammaB: gammaB,
        gamma: gamma,
        channelDeviation: abs(gammaR - gammaB),
        bandingRisk: 0.1,
        rampHash: "abc123"
    )
}

/// Build a CalibrationRecord for testing.
private func makeCalibration(
    displayID: String,
    timestamp: Date = Date(),
    targetGamma: Double = 2.2,
    before: Double = 2.35,
    after: Double = 2.21,
    success: Bool = true
) -> CalibrationRecord {
    CalibrationRecord(
        id: "auto",
        displayID: displayID,
        timestamp: timestamp,
        targetGamma: targetGamma,
        measuredGammaBefore: before,
        measuredGammaAfter: after,
        success: success,
        method: "CGSetDisplayTransferByTable",
        durationSeconds: 0.5
    )
}

/// Build a TransformRecord for testing.
private func makeTransform(
    calibrationID: String = "auto",
    stepIndex: Int,
    transformType: String = "powerLaw",
    inputGamma: Double = 2.35,
    outputGamma: Double = 2.20
) -> TransformRecord {
    TransformRecord(
        id: "auto",
        calibrationID: calibrationID,
        timestamp: Date(),
        stepIndex: stepIndex,
        transformType: transformType,
        parameters: #"{"gamma": 2.2}"#,
        inputGamma: inputGamma,
        outputGamma: outputGamma
    )
}

// MARK: - Tests

@Suite("SQLiteStore")
struct SQLiteStoreTests {

    @Test("Schema is created on init without errors")
    func schemaCreation() throws {
        let store = try makeStore()
        // Verify tables exist by querying them.
        let displays = try store.allDisplays()
        #expect(displays.isEmpty)

        let did = testDisplayID()
        let measurements = try store.measurements(displayID: did, limit: 10)
        #expect(measurements.isEmpty)

        let calibrations = try store.calibrations(displayID: did, limit: 10)
        #expect(calibrations.isEmpty)

        let transforms = try store.transforms(calibrationID: 1)
        #expect(transforms.isEmpty)
    }

    @Test("Display upsert and retrieval")
    func displayUpsertAndRetrieval() throws {
        let store = try makeStore()
        let info = makeDisplayInfo()
        try store.upsertDisplay(info)

        let did = testDisplayID()
        let twin = try store.display(id: did)
        #expect(twin != nil)
        #expect(twin?.name == "Test Display")
        #expect(twin?.vendorID == 0x0610)
        #expect(twin?.modelID == 0xA032)
        #expect(twin?.serialNumber == 12345)
        #expect(twin?.bitDepth == 10)
        #expect(twin?.colorSpace == "P3")
        #expect(twin?.calibrationCount == 0)
        #expect(twin?.driftRate == nil)
    }

    @Test("Display upsert updates name and last_seen on conflict")
    func displayUpsertUpdate() throws {
        let store = try makeStore()
        let info1 = makeDisplayInfo(name: "Original Name")
        try store.upsertDisplay(info1)

        let info2 = makeDisplayInfo(name: "Updated Name")
        try store.upsertDisplay(info2)

        let did = testDisplayID()
        let all = try store.allDisplays()
        #expect(all.count == 1)
        #expect(all.first?.name == "Updated Name")

        let twin = try store.display(id: did)
        #expect(twin?.name == "Updated Name")
    }

    @Test("Measurement insert and query")
    func measurementInsertAndQuery() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()
        let m = makeMeasurement(displayID: did)
        let rowID = try store.insertMeasurement(m)
        #expect(rowID > 0)

        let results = try store.measurements(displayID: did, limit: 10)
        #expect(results.count == 1)
        #expect(results[0].displayID == did)
        #expect(abs(results[0].gammaR - 2.18) < 0.001)
        #expect(abs(results[0].gammaG - 2.20) < 0.001)
        #expect(abs(results[0].gammaB - 2.22) < 0.001)
        #expect(abs(results[0].gamma - 2.20) < 0.001)
    }

    @Test("Measurement limit is respected")
    func measurementLimit() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()
        for i in 0..<5 {
            let ts = Date(timeIntervalSinceNow: Double(i) * -60)
            let m = makeMeasurement(displayID: did, timestamp: ts, gamma: 2.2 + Double(i) * 0.01)
            try store.insertMeasurement(m)
        }

        let results = try store.measurements(displayID: did, limit: 3)
        #expect(results.count == 3)
    }

    @Test("Calibration with pre/post measurements")
    func calibrationWithMeasurements() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()

        // Insert pre-measurement
        let preMeasurement = makeMeasurement(displayID: did, gamma: 2.35)
        let preID = try store.insertMeasurement(preMeasurement)
        #expect(preID > 0)

        // Insert calibration
        let cal = makeCalibration(displayID: did, before: 2.35, after: 2.21)
        let calID = try store.insertCalibration(cal)
        #expect(calID > 0)

        // Insert post-measurement
        let postMeasurement = makeMeasurement(displayID: did, gamma: 2.21)
        let postID = try store.insertMeasurement(postMeasurement)
        #expect(postID > 0)

        // Verify calibration
        let cals = try store.calibrations(displayID: did, limit: 10)
        #expect(cals.count == 1)
        #expect(cals[0].success == true)
        #expect(cals[0].method == "CGSetDisplayTransferByTable")

        // Verify calibration count was incremented
        let twin = try store.display(id: did)
        #expect(twin?.calibrationCount == 1)
    }

    @Test("Transform recording and retrieval")
    func transformRecording() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()
        let calID = try store.insertCalibration(makeCalibration(displayID: did))

        let transforms = [
            makeTransform(stepIndex: 0, transformType: "measureGamma", inputGamma: 2.35, outputGamma: 2.35),
            makeTransform(stepIndex: 1, transformType: "powerLaw", inputGamma: 2.35, outputGamma: 2.20),
            makeTransform(stepIndex: 2, transformType: "applyLUT", inputGamma: 2.20, outputGamma: 2.20),
        ]

        try store.insertTransforms(transforms, calibrationID: calID)

        let fetched = try store.transforms(calibrationID: calID)
        #expect(fetched.count == 3)
        #expect(fetched[0].transformType == "measureGamma")
        #expect(fetched[1].transformType == "powerLaw")
        #expect(fetched[2].transformType == "applyLUT")
        #expect(fetched[0].stepIndex == 0)
        #expect(fetched[1].stepIndex == 1)
        #expect(fetched[2].stepIndex == 2)
    }

    @Test("Drift rate is nil with insufficient data")
    func driftRateNilInsufficient() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()

        // No measurements -> nil
        let rate0 = try store.computeDriftRate(displayID: did)
        #expect(rate0 == nil)

        // One measurement -> still nil
        try store.insertMeasurement(makeMeasurement(displayID: did))
        let rate1 = try store.computeDriftRate(displayID: did)
        #expect(rate1 == nil)
    }

    @Test("Drift rate computed with sufficient data")
    func driftRateComputed() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()

        // Insert two measurements one week apart with different gamma.
        let oneWeekAgo = Date(timeIntervalSinceNow: -7 * 24 * 3600)
        try store.insertMeasurement(makeMeasurement(displayID: did, timestamp: oneWeekAgo, gamma: 2.20))
        try store.insertMeasurement(makeMeasurement(displayID: did, timestamp: Date(), gamma: 2.25))

        let rate = try store.computeDriftRate(displayID: did)
        #expect(rate != nil)
        // Drift should be approximately 0.05 per week.
        #expect(abs(rate! - 0.05) < 0.01)
    }

    @Test("Raw SQL query works")
    func rawSQLQuery() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let rows = try store.query("SELECT id, name FROM displays")
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == "Test Display")

        let did = testDisplayID()
        #expect(rows[0]["id"] == did)
    }

    @Test("Multiple displays are tracked independently")
    func multipleDisplays() throws {
        let store = try makeStore()

        // Insert two different displays.
        let info1 = makeDisplayInfo(vendorID: 0x0610, modelID: 0xA032, serialNumber: 11111, name: "Display A")
        let info2 = makeDisplayInfo(vendorID: 0x1E6D, modelID: 0xB044, serialNumber: 22222, name: "Display B")
        try store.upsertDisplay(info1)
        try store.upsertDisplay(info2)

        let all = try store.allDisplays()
        #expect(all.count == 2)

        let did1 = testDisplayID(vendorID: 0x0610, modelID: 0xA032, serialNumber: 11111)
        let did2 = testDisplayID(vendorID: 0x1E6D, modelID: 0xB044, serialNumber: 22222)

        // Insert measurements for each.
        try store.insertMeasurement(makeMeasurement(displayID: did1, gamma: 2.20))
        try store.insertMeasurement(makeMeasurement(displayID: did2, gamma: 2.30))

        let m1 = try store.measurements(displayID: did1, limit: 10)
        let m2 = try store.measurements(displayID: did2, limit: 10)
        #expect(m1.count == 1)
        #expect(m2.count == 1)
        #expect(abs(m1[0].gamma - 2.20) < 0.001)
        #expect(abs(m2[0].gamma - 2.30) < 0.001)
    }

    @Test("Time series query returns filtered results")
    func timeSeriesQuery() throws {
        let store = try makeStore()
        try store.upsertDisplay(makeDisplayInfo())

        let did = testDisplayID()
        let now = Date()

        // Insert measurements at various times.
        for i in 0..<5 {
            let ts = Date(timeIntervalSince1970: now.timeIntervalSince1970 - Double(4 - i) * 3600)
            try store.insertMeasurement(makeMeasurement(
                displayID: did,
                timestamp: ts,
                gamma: 2.20 + Double(i) * 0.01
            ))
        }

        // Query since 3 hours ago -- should get last 3 measurements.
        let since = Date(timeIntervalSince1970: now.timeIntervalSince1970 - 2.5 * 3600)
        let series = try store.timeSeries(displayID: did, metric: .gamma, since: since)
        #expect(series.count == 3)
    }

    @Test("Display not found returns nil")
    func displayNotFound() throws {
        let store = try makeStore()
        let twin = try store.display(id: "nonexistent")
        #expect(twin == nil)
    }

    @Test("Ramp compression roundtrip")
    func rampCompressionRoundtrip() throws {
        let original: [Double] = (0..<256).map { Double($0) / 255.0 }
        let compressed = compressRamp(original)
        #expect(compressed != nil)
        #expect(compressed!.count < original.count * MemoryLayout<Double>.size)

        let decompressed = decompressRamp(compressed!)
        #expect(decompressed != nil)
        #expect(decompressed!.count == original.count)

        for (a, b) in zip(original, decompressed!) {
            #expect(abs(a - b) < 0.001)
        }
    }

    @Test("Ramp compression handles empty input")
    func rampCompressionEmpty() throws {
        let compressed = compressRamp([])
        #expect(compressed == nil)
    }

    @Test("Ramp decompression handles empty input")
    func rampDecompressionEmpty() throws {
        let decompressed = decompressRamp(Data())
        #expect(decompressed == nil)
    }
}

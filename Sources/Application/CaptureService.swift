/* Application Layer — CaptureService.
   Silently records display state to the calibration database on every CLI
   invocation.  All public methods swallow errors (try?) so capture never
   causes a command to fail — it is a passive observer only.

   Learner note: The `@discardableResult` attribute lets callers ignore the
   returned row ID when they don't need it (fire-and-forget logging). */

import Foundation

/// Silently records display state to the calibration database.
/// Every CLI command calls this — capture never causes command failure.
public struct CaptureService: Sendable {
    private let store: any CalibrationStoring

    public init(store: any CalibrationStoring) {
        self.store = store
    }

    /// Upsert all connected displays into the database.
    /// Each display is registered/updated independently so a single
    /// failure does not block the rest.
    public func captureDisplays(_ displays: [DisplayInfo]) {
        for display in displays {
            try? store.upsertDisplay(display)
        }
    }

    /// Record a gamma measurement snapshot.
    ///
    /// Builds a `MeasurementRecord` from the provided gamma analysis
    /// values and inserts it into the store.  Returns the row ID on
    /// success, or nil if the insert fails (silently).
    @discardableResult
    public func captureMeasurement(
        displayID: String,
        trigger: String,
        gammaR: Double,
        gammaG: Double,
        gammaB: Double,
        gammaAvg: Double,
        channelDeviation: Double,
        bandingRisk: Double
    ) -> Int64? {
        let record = MeasurementRecord(
            id: UUID().uuidString,
            displayID: displayID,
            timestamp: Date(),
            gammaR: gammaR,
            gammaG: gammaG,
            gammaB: gammaB,
            gamma: gammaAvg,
            channelDeviation: channelDeviation,
            bandingRisk: bandingRisk,
            rampHash: trigger
        )
        return try? store.insertMeasurement(record)
    }

    /// Record a calibration event.
    @discardableResult
    public func captureCalibration(_ record: CalibrationRecord) -> Int64? {
        return try? store.insertCalibration(record)
    }
}

/* Application Layer -- CalibrationStoring protocol.
   Defines the persistence contract for calibration data.  The Application
   layer depends only on this protocol; the Infrastructure layer provides
   the concrete SQLite implementation.

   Design notes:
   - All methods are synchronous and `throws` -- the SQLite implementation
     serialises access via a DispatchQueue, so async is unnecessary.
   - `@discardableResult` on insert methods lets callers ignore the row ID
     when they don't need it (e.g. fire-and-forget measurement logging).
   - The protocol extends `Sendable` so it can be safely shared across
     Swift 6.2 concurrency boundaries. */

import Foundation

/// Protocol for persisting and querying calibration data.
/// Application layer depends on this protocol; Infrastructure provides SQLite implementation.
public protocol CalibrationStoring: Sendable {
    /// Insert or update a display record from discovery info.
    func upsertDisplay(_ info: DisplayInfo) throws

    /// Fetch a single display by its stable hex ID.
    func display(id: String) throws -> DisplayTwin?

    /// Fetch all known displays, ordered by last_seen descending.
    func allDisplays() throws -> [DisplayTwin]

    /// Insert a gamma ramp measurement snapshot. Returns the autoincrement row ID.
    @discardableResult func insertMeasurement(_ m: MeasurementRecord) throws -> Int64

    /// Query measurements for a display, most recent first, up to `limit`.
    func measurements(displayID: String, limit: Int) throws -> [MeasurementRecord]

    /// Insert a calibration record. Returns the autoincrement row ID.
    @discardableResult func insertCalibration(_ c: CalibrationRecord) throws -> Int64

    /// Query calibrations for a display, most recent first, up to `limit`.
    func calibrations(displayID: String, limit: Int) throws -> [CalibrationRecord]

    /// Insert transform pipeline steps tied to a calibration.
    func insertTransforms(_ transforms: [TransformRecord], calibrationID: Int64) throws

    /// Fetch all transform steps for a calibration, ordered by step index.
    func transforms(calibrationID: Int64) throws -> [TransformRecord]

    /// Fetch a time series of a specific metric for a display since a given date.
    func timeSeries(displayID: String, metric: MetricKind, since: Date) throws -> [(date: Date, value: Double)]

    /// Compute the gamma drift rate (change per week) for a display.
    /// Returns nil when fewer than 2 measurements exist.
    func computeDriftRate(displayID: String) throws -> Double?

    /// Execute a raw SQL query (read-only). Each row is a dictionary of column name to string value.
    func query(_ sql: String) throws -> [[String: String]]
}

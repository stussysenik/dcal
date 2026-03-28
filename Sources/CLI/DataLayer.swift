/* CLI -- DataLayer factory.
   Provides a single entry point for CLI commands to obtain a CalibrationStoring
   instance.  Returns nil if the database cannot be opened (e.g. first run
   before any data has been collected). */

import Infrastructure
import Application

/// Factory for obtaining a CalibrationStoring instance backed by SQLite.
///
/// CLI commands call `DataLayer.store()` to get the persistence layer.
/// Returns `nil` when the database file does not yet exist or cannot be opened,
/// allowing commands to print a friendly "no data yet" message instead of
/// crashing.
enum DataLayer {
    /// Open the default SQLite store. Returns nil on failure.
    static func store() -> (any CalibrationStoring)? {
        try? SQLiteStore()
    }

    /// Create a CaptureService backed by the default store. Returns nil on failure.
    static func captureService() -> CaptureService? {
        guard let store = store() else { return nil }
        return CaptureService(store: store)
    }
}

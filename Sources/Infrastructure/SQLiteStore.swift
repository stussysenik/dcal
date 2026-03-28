/* Infrastructure Layer -- SQLite-backed calibration store.

   This file implements CalibrationStoring using the system sqlite3 C API
   (zero external dependencies).  Key design decisions:

   - **Serial DispatchQueue**: All database access is serialised through a
     single queue, making this class safe to share across threads while
     avoiding the overhead of actors for synchronous I/O.
   - **WAL mode**: Write-Ahead Logging allows concurrent readers (CLI and
     GUI can read while the daemon writes).
   - **Migration system**: A `schema_version` table tracks which migrations
     have been applied.  New migrations are added as numbered closures.
   - **@unchecked Sendable**: Safe because all mutable state (the db pointer)
     is accessed exclusively through the serial queue.

   Learner note: The sqlite3 C API uses opaque pointer types (OpaquePointer)
   in Swift.  Each `sqlite3_prepare_v2` call creates a statement that must
   be finalised with `sqlite3_finalize` to avoid memory leaks. */

import Foundation
import SQLite3
import Application
import Domain

// MARK: - SQLiteStore

/// Production implementation of `CalibrationStoring` backed by sqlite3.
///
/// Default database path: `~/.dcal/dcal.db`.  Pass `":memory:"` for tests.
public final class SQLiteStore: CalibrationStoring, @unchecked Sendable {

    // MARK: - Properties

    /// Opaque pointer to the sqlite3 database connection.
    private var db: OpaquePointer?

    /// Serial queue that serialises all database access.
    private let queue = DispatchQueue(label: "com.dcal.sqlite-store", qos: .userInitiated)

    /// ISO 8601 formatter matching SQLite's strftime output.
    /// `nonisolated(unsafe)` is safe here because ISO8601DateFormatter is
    /// initialised once and never mutated after creation.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback formatter without fractional seconds.
    nonisolated(unsafe) private static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Initialiser

    /// Open or create a database at the given path.
    ///
    /// - Parameter path: File path for the database.  Use `":memory:"` for
    ///   ephemeral in-memory databases (ideal for testing).  Defaults to
    ///   `~/.dcal/dcal.db`.
    public init(path: String = defaultPath()) throws {
        // Ensure the directory exists for file-based databases.
        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true
            )
        }

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw SQLiteError.openFailed(msg)
        }

        // Enable WAL mode for concurrent CLI/GUI access.
        try execute("PRAGMA journal_mode=WAL")
        // Enable foreign keys.
        try execute("PRAGMA foreign_keys=ON")

        try runMigrations()
    }

    deinit {
        sqlite3_close(db)
    }

    /// Default database file path: `~/.dcal/dcal.db`.
    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.dcal/dcal.db"
    }

    // MARK: - Migration System

    /// Each migration is a numbered closure that receives the db pointer.
    /// Migrations are run in order; already-applied migrations are skipped.
    private func runMigrations() throws {
        // Create the version tracking table if it doesn't exist.
        try execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
            """)

        let currentVersion = try currentSchemaVersion()
        let migrations: [(Int, String)] = [
            (1, migration1_createTables),
        ]

        for (version, sql) in migrations {
            if version > currentVersion {
                try execute(sql)
                try execute("INSERT INTO schema_version (version) VALUES (\(version))")
            }
        }
    }

    private func currentSchemaVersion() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            let v = sqlite3_column_int64(stmt, 0)
            return Int(v)
        }
        return 0
    }

    // MARK: - Schema (Migration 1)

    private let migration1_createTables = """
        CREATE TABLE IF NOT EXISTS displays (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            vendor_id INTEGER,
            model_id INTEGER,
            serial_number INTEGER DEFAULT 0,
            native_gamma REAL DEFAULT 2.2,
            bit_depth INTEGER DEFAULT 8,
            color_space TEXT DEFAULT 'sRGB',
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            calibration_count INTEGER DEFAULT 0,
            drift_rate REAL
        );

        CREATE TABLE IF NOT EXISTS measurements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            display_id TEXT NOT NULL REFERENCES displays(id),
            timestamp TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            trigger TEXT NOT NULL,
            gamma_r REAL,
            gamma_g REAL,
            gamma_b REAL,
            gamma_avg REAL,
            channel_deviation REAL,
            banding_risk REAL,
            ramp_data BLOB,
            sample_count INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_measurements_display_time
            ON measurements(display_id, timestamp DESC);

        CREATE TABLE IF NOT EXISTS calibrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            display_id TEXT NOT NULL REFERENCES displays(id),
            timestamp TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            target TEXT NOT NULL,
            target_gamma REAL NOT NULL,
            table_gamma_r REAL,
            table_gamma_g REAL,
            table_gamma_b REAL,
            pre_measurement_id INTEGER REFERENCES measurements(id),
            post_measurement_id INTEGER REFERENCES measurements(id),
            end_to_end_gamma REAL,
            delta_e REAL,
            passed INTEGER,
            method TEXT NOT NULL,
            algorithm_version TEXT DEFAULT '0.1.0'
        );
        CREATE INDEX IF NOT EXISTS idx_calibrations_display_time
            ON calibrations(display_id, timestamp DESC);

        CREATE TABLE IF NOT EXISTS transforms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            calibration_id INTEGER NOT NULL REFERENCES calibrations(id),
            step_order INTEGER NOT NULL,
            transform_type TEXT NOT NULL,
            inputs TEXT,
            outputs TEXT,
            duration_ms REAL
        );
        CREATE INDEX IF NOT EXISTS idx_transforms_calibration
            ON transforms(calibration_id, step_order);
        """

    // MARK: - CalibrationStoring Implementation

    public func upsertDisplay(_ info: DisplayInfo) throws {
        try queue.sync {
            let id = displayID(
                vendorID: info.vendorID,
                modelID: info.modelID,
                serialNumber: info.serialNumber
            )
            let now = Self.formatDate(Date())

            let sql = """
                INSERT INTO displays (id, name, vendor_id, model_id, serial_number,
                    native_gamma, bit_depth, color_space, first_seen, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    native_gamma = excluded.native_gamma,
                    bit_depth = excluded.bit_depth,
                    color_space = excluded.color_space,
                    last_seen = excluded.last_seen
                """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)

            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (info.name as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 3, Int64(info.vendorID))
            sqlite3_bind_int64(stmt, 4, Int64(info.modelID))
            sqlite3_bind_int64(stmt, 5, Int64(info.serialNumber))
            sqlite3_bind_double(stmt, 6, info.estimatedNativeGamma)
            sqlite3_bind_int(stmt, 7, Int32(info.bitDepth))
            sqlite3_bind_text(stmt, 8, (info.colorSpace as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 9, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 10, (now as NSString).utf8String, -1, nil)

            try stepOrThrow(stmt)
        }
    }

    public func display(id: String) throws -> DisplayTwin? {
        try queue.sync {
            let sql = "SELECT * FROM displays WHERE id = ?"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readDisplayTwin(from: stmt)
        }
    }

    public func allDisplays() throws -> [DisplayTwin] {
        try queue.sync {
            let sql = "SELECT * FROM displays ORDER BY last_seen DESC"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)

            var results: [DisplayTwin] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readDisplayTwin(from: stmt))
            }
            return results
        }
    }

    @discardableResult
    public func insertMeasurement(_ m: MeasurementRecord) throws -> Int64 {
        try queue.sync {
            let sql = """
                INSERT INTO measurements
                    (display_id, timestamp, trigger, gamma_r, gamma_g, gamma_b,
                     gamma_avg, channel_deviation, banding_risk, ramp_data, sample_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)

            sqlite3_bind_text(stmt, 1, nsUTF8(m.displayID), -1, nil)
            sqlite3_bind_text(stmt, 2, nsUTF8(Self.formatDate(m.timestamp)), -1, nil)
            sqlite3_bind_text(stmt, 3, nsUTF8(m.rampHash), -1, nil)  // trigger = rampHash
            sqlite3_bind_double(stmt, 4, m.gammaR)
            sqlite3_bind_double(stmt, 5, m.gammaG)
            sqlite3_bind_double(stmt, 6, m.gammaB)
            sqlite3_bind_double(stmt, 7, m.gamma)
            sqlite3_bind_double(stmt, 8, m.channelDeviation)
            sqlite3_bind_double(stmt, 9, m.bandingRisk)
            // ramp_data: store the rampHash as trigger info (no raw ramp data in MeasurementRecord)
            sqlite3_bind_null(stmt, 10)
            sqlite3_bind_null(stmt, 11)

            try stepOrThrow(stmt)
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func measurements(displayID: String, limit: Int) throws -> [MeasurementRecord] {
        try queue.sync {
            let sql = """
                SELECT * FROM measurements
                WHERE display_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_text(stmt, 1, nsUTF8(displayID), -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [MeasurementRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readMeasurementRecord(from: stmt))
            }
            return results
        }
    }

    @discardableResult
    public func insertCalibration(_ c: CalibrationRecord) throws -> Int64 {
        try queue.sync {
            let sql = """
                INSERT INTO calibrations
                    (display_id, timestamp, target, target_gamma,
                     table_gamma_r, table_gamma_g, table_gamma_b,
                     end_to_end_gamma, delta_e, passed, method)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)

            sqlite3_bind_text(stmt, 1, nsUTF8(c.displayID), -1, nil)
            sqlite3_bind_text(stmt, 2, nsUTF8(Self.formatDate(c.timestamp)), -1, nil)
            sqlite3_bind_text(stmt, 3, nsUTF8("gamma_\(c.targetGamma)"), -1, nil)
            sqlite3_bind_double(stmt, 4, c.targetGamma)
            sqlite3_bind_double(stmt, 5, c.measuredGammaBefore)
            sqlite3_bind_double(stmt, 6, c.measuredGammaBefore)
            sqlite3_bind_double(stmt, 7, c.measuredGammaBefore)
            sqlite3_bind_double(stmt, 8, c.measuredGammaAfter)
            sqlite3_bind_null(stmt, 9) // delta_e
            sqlite3_bind_int(stmt, 10, c.success ? 1 : 0)
            sqlite3_bind_text(stmt, 11, nsUTF8(c.method), -1, nil)

            try stepOrThrow(stmt)

            let calID = sqlite3_last_insert_rowid(db)

            // Increment display calibration count.
            let updateSQL = """
                UPDATE displays SET calibration_count = calibration_count + 1
                WHERE id = ?
                """
            var updateStmt: OpaquePointer?
            defer { sqlite3_finalize(updateStmt) }
            try prepareOrThrow(updateSQL, &updateStmt)
            sqlite3_bind_text(updateStmt, 1, nsUTF8(c.displayID), -1, nil)
            try stepOrThrow(updateStmt)

            return calID
        }
    }

    public func calibrations(displayID: String, limit: Int) throws -> [CalibrationRecord] {
        try queue.sync {
            let sql = """
                SELECT * FROM calibrations
                WHERE display_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_text(stmt, 1, nsUTF8(displayID), -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [CalibrationRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readCalibrationRecord(from: stmt))
            }
            return results
        }
    }

    public func insertTransforms(_ transforms: [TransformRecord], calibrationID: Int64) throws {
        try queue.sync {
            let sql = """
                INSERT INTO transforms
                    (calibration_id, step_order, transform_type, inputs, outputs, duration_ms)
                VALUES (?, ?, ?, ?, ?, ?)
                """

            for t in transforms {
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                try prepareOrThrow(sql, &stmt)

                sqlite3_bind_int64(stmt, 1, calibrationID)
                sqlite3_bind_int(stmt, 2, Int32(t.stepIndex))
                sqlite3_bind_text(stmt, 3, nsUTF8(t.transformType), -1, nil)
                sqlite3_bind_text(stmt, 4, nsUTF8(t.parameters), -1, nil)
                sqlite3_bind_double(stmt, 5, t.outputGamma)
                sqlite3_bind_double(stmt, 6, 0)  // duration_ms not tracked in TransformRecord

                try stepOrThrow(stmt)
            }
        }
    }

    public func transforms(calibrationID: Int64) throws -> [TransformRecord] {
        try queue.sync {
            let sql = """
                SELECT * FROM transforms
                WHERE calibration_id = ?
                ORDER BY step_order ASC
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_int64(stmt, 1, calibrationID)

            var results: [TransformRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(readTransformRecord(from: stmt))
            }
            return results
        }
    }

    public func timeSeries(displayID: String, metric: MetricKind, since: Date) throws -> [(date: Date, value: Double)] {
        try queue.sync {
            let column: String
            switch metric {
            case .gamma: column = "gamma_avg"
            case .gammaR: column = "gamma_r"
            case .gammaG: column = "gamma_g"
            case .gammaB: column = "gamma_b"
            case .channelDeviation: column = "channel_deviation"
            case .bandingRisk: column = "banding_risk"
            }

            let sql = """
                SELECT timestamp, \(column) FROM measurements
                WHERE display_id = ? AND timestamp >= ?
                ORDER BY timestamp ASC
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_text(stmt, 1, nsUTF8(displayID), -1, nil)
            sqlite3_bind_text(stmt, 2, nsUTF8(Self.formatDate(since)), -1, nil)

            var results: [(date: Date, value: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dateStr = String(cString: sqlite3_column_text(stmt, 0))
                let value = sqlite3_column_double(stmt, 1)
                if let date = Self.parseDate(dateStr) {
                    results.append((date: date, value: value))
                }
            }
            return results
        }
    }

    public func computeDriftRate(displayID: String) throws -> Double? {
        try queue.sync {
            // Need at least 2 measurements to compute drift.
            let sql = """
                SELECT timestamp, gamma_avg FROM measurements
                WHERE display_id = ?
                ORDER BY timestamp ASC
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)
            sqlite3_bind_text(stmt, 1, nsUTF8(displayID), -1, nil)

            var points: [(time: Double, gamma: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dateStr = String(cString: sqlite3_column_text(stmt, 0))
                let gamma = sqlite3_column_double(stmt, 1)
                if let date = Self.parseDate(dateStr) {
                    points.append((time: date.timeIntervalSince1970, gamma: gamma))
                }
            }

            guard points.count >= 2 else { return nil }

            // Linear regression: slope = change in gamma per second, convert to per week.
            let first = points.first!
            let last = points.last!
            let dt = last.time - first.time
            guard dt > 0 else { return nil }

            let dGamma = last.gamma - first.gamma
            let slopePerSecond = dGamma / dt
            let secondsPerWeek = 7.0 * 24.0 * 3600.0
            let driftPerWeek = slopePerSecond * secondsPerWeek

            // Update the display's drift_rate.
            let updateSQL = "UPDATE displays SET drift_rate = ? WHERE id = ?"
            var updateStmt: OpaquePointer?
            defer { sqlite3_finalize(updateStmt) }
            try prepareOrThrow(updateSQL, &updateStmt)
            sqlite3_bind_double(updateStmt, 1, driftPerWeek)
            sqlite3_bind_text(updateStmt, 2, nsUTF8(displayID), -1, nil)
            try stepOrThrow(updateStmt)

            return driftPerWeek
        }
    }

    public func query(_ sql: String) throws -> [[String: String]] {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            try prepareOrThrow(sql, &stmt)

            var results: [[String: String]] = []
            let colCount = sqlite3_column_count(stmt)

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: String] = [:]
                for i in 0..<colCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    if let text = sqlite3_column_text(stmt, i) {
                        row[name] = String(cString: text)
                    } else {
                        row[name] = ""
                    }
                }
                results.append(row)
            }
            return results
        }
    }

    // MARK: - Row Readers

    private func readDisplayTwin(from stmt: OpaquePointer?) -> DisplayTwin {
        let id = columnText(stmt, 0)
        let name = columnText(stmt, 1)
        let vendorID = UInt32(sqlite3_column_int64(stmt, 2))
        let modelID = UInt32(sqlite3_column_int64(stmt, 3))
        let serialNumber = UInt32(sqlite3_column_int64(stmt, 4))
        let nativeGamma = sqlite3_column_double(stmt, 5)
        let bitDepth = Int(sqlite3_column_int(stmt, 6))
        let colorSpace = columnText(stmt, 7)
        let firstSeen = Self.parseDate(columnText(stmt, 8)) ?? Date()
        let lastSeen = Self.parseDate(columnText(stmt, 9)) ?? Date()
        let calibrationCount = Int(sqlite3_column_int(stmt, 10))
        let driftRate: Double? = sqlite3_column_type(stmt, 11) == SQLITE_NULL
            ? nil : sqlite3_column_double(stmt, 11)

        return DisplayTwin(
            id: id,
            name: name,
            vendorID: vendorID,
            modelID: modelID,
            serialNumber: serialNumber,
            nativeGamma: nativeGamma,
            bitDepth: bitDepth,
            colorSpace: colorSpace,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            calibrationCount: calibrationCount,
            driftRate: driftRate
        )
    }

    private func readMeasurementRecord(from stmt: OpaquePointer?) -> MeasurementRecord {
        let id = String(sqlite3_column_int64(stmt, 0))
        let displayID = columnText(stmt, 1)
        let timestamp = Self.parseDate(columnText(stmt, 2)) ?? Date()
        let trigger = columnText(stmt, 3)
        let gammaR = sqlite3_column_double(stmt, 4)
        let gammaG = sqlite3_column_double(stmt, 5)
        let gammaB = sqlite3_column_double(stmt, 6)
        let gamma = sqlite3_column_double(stmt, 7)
        let channelDeviation = sqlite3_column_double(stmt, 8)
        let bandingRisk = sqlite3_column_double(stmt, 9)

        return MeasurementRecord(
            id: id,
            displayID: displayID,
            timestamp: timestamp,
            gammaR: gammaR,
            gammaG: gammaG,
            gammaB: gammaB,
            gamma: gamma,
            channelDeviation: channelDeviation,
            bandingRisk: bandingRisk,
            rampHash: trigger
        )
    }

    private func readCalibrationRecord(from stmt: OpaquePointer?) -> CalibrationRecord {
        let id = String(sqlite3_column_int64(stmt, 0))
        let displayIDVal = columnText(stmt, 1)
        let timestamp = Self.parseDate(columnText(stmt, 2)) ?? Date()
        // target col 3, target_gamma col 4
        let targetGamma = sqlite3_column_double(stmt, 4)
        let tableGammaR = sqlite3_column_double(stmt, 5)
        // end_to_end_gamma col 10
        let endToEndGamma = sqlite3_column_double(stmt, 10)
        let passed = sqlite3_column_int(stmt, 12) != 0
        let method = columnText(stmt, 13)

        return CalibrationRecord(
            id: id,
            displayID: displayIDVal,
            timestamp: timestamp,
            targetGamma: targetGamma,
            measuredGammaBefore: tableGammaR,
            measuredGammaAfter: endToEndGamma,
            success: passed,
            method: method,
            durationSeconds: 0
        )
    }

    private func readTransformRecord(from stmt: OpaquePointer?) -> TransformRecord {
        let id = String(sqlite3_column_int64(stmt, 0))
        let calibrationID = String(sqlite3_column_int64(stmt, 1))
        let stepOrder = Int(sqlite3_column_int(stmt, 2))
        let transformType = columnText(stmt, 3)
        let inputs = columnText(stmt, 4)
        let outputs = sqlite3_column_double(stmt, 5)

        return TransformRecord(
            id: id,
            calibrationID: calibrationID,
            timestamp: Date(),
            stepIndex: stepOrder,
            transformType: transformType,
            parameters: inputs,
            inputGamma: 0,
            outputGamma: outputs
        )
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        if let text = sqlite3_column_text(stmt, index) {
            return String(cString: text)
        }
        return ""
    }

    private func nsUTF8(_ string: String) -> UnsafePointer<CChar>? {
        (string as NSString).utf8String
    }

    private func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw SQLiteError.executionFailed(msg)
        }
    }

    private func prepareOrThrow(_ sql: String, _ stmt: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(msg)
        }
    }

    private func stepOrThrow(_ stmt: OpaquePointer?) throws {
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.stepFailed(msg)
        }
    }

    static func formatDate(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    static func parseDate(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFrac.date(from: string)
    }
}

// MARK: - Error Types

/// Errors thrown by SQLiteStore operations.
public enum SQLiteError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): "SQLite open failed: \(msg)"
        case .executionFailed(let msg): "SQLite execution failed: \(msg)"
        case .prepareFailed(let msg): "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): "SQLite step failed: \(msg)"
        }
    }
}

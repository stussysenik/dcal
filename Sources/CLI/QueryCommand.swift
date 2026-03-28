/* CLI -- Query command.
   Executes raw SQL against the calibration database and displays results.
   
   Learner note: Exposing raw SQL is a power-user feature for debugging and
   ad-hoc analysis.  The CalibrationStoring.query() method is read-only
   (SELECT only) to prevent accidental data corruption.  Results are
   formatted as either an aligned ASCII table or CSV for piping into
   other tools.
   
   Usage:
     dcal query "SELECT * FROM displays"
     dcal query "SELECT count(*) FROM measurements" --csv
     dcal query "SELECT * FROM calibrations ORDER BY timestamp DESC LIMIT 5" */

import ArgumentParser
import Foundation
import Application
import Infrastructure

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute raw SQL query against calibration database."
    )

    @Argument(help: "SQL query string.")
    var sql: String

    @Flag(name: .long, help: "Output as CSV instead of table.")
    var csv = false

    func run() throws {
        guard let store = DataLayer.store() else {
            print("  No calibration database found. Run 'dcal status' first.")
            return
        }

        let results: [[String: String]]
        do {
            results = try store.query(sql)
        } catch {
            print("  SQL error: \(error)")
            return
        }

        if results.isEmpty {
            print("  (no rows returned)")
            return
        }

        // Determine column order from the first row's keys.
        // Sort alphabetically for consistent output.
        let columns = results[0].keys.sorted()

        if csv {
            Self.printCSV(columns: columns, rows: results)
        } else {
            Self.printTable(columns: columns, rows: results)
        }
    }

    /// Print results as CSV to stdout.
    ///
    /// Each field is quoted if it contains a comma, quote, or newline.
    /// This follows RFC 4180 conventions for maximum compatibility with
    /// spreadsheet tools and Unix pipelines.
    static func printCSV(columns: [String], rows: [[String: String]]) {
        print(columns.map { csvEscape($0) }.joined(separator: ","))
        for row in rows {
            let values = columns.map { csvEscape(row[$0] ?? "") }
            print(values.joined(separator: ","))
        }
    }

    /// Print results as an aligned ASCII table.
    ///
    /// Column widths are computed from the maximum value length (capped
    /// at 40 characters to prevent terminal overflow).  The table uses
    /// Unicode box-drawing characters for a clean look.
    static func printTable(columns: [String], rows: [[String: String]]) {
        // Compute column widths: max of header and all values, capped at 40.
        var widths = columns.map { $0.count }
        for row in rows {
            for (i, col) in columns.enumerated() {
                let len = (row[col] ?? "").count
                widths[i] = min(40, max(widths[i], len))
            }
        }

        // Header.
        let header = columns.enumerated().map { (i, col) in
            col.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: " | ")
        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")

        print(header)
        print(separator)

        // Rows.
        for row in rows {
            let line = columns.enumerated().map { (i, col) in
                let val = row[col] ?? ""
                let display = val.count > widths[i] ? String(val.prefix(widths[i] - 1)) + "…" : val
                return display.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }.joined(separator: " | ")
            print(line)
        }

        print("")
        print("  \(rows.count) row\(rows.count == 1 ? "" : "s") returned.")
    }

    /// Escape a string for CSV output per RFC 4180.
    static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

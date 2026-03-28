/* CLI -- History command.
   Displays a timeline of calibration events from the SQLite database.
   
   Learner note: This command demonstrates querying a protocol-based store
   and formatting results as an aligned ASCII table.  The --display flag
   filters by display name, and --limit caps the number of rows shown.
   
   Usage:
     dcal history                     # all displays, last 20 calibrations
     dcal history --display "LG 27"   # filter by display name
     dcal history --limit 50          # show more entries */

import ArgumentParser
import Foundation
import Application
import Infrastructure

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show calibration history timeline."
    )

    @Option(name: .long, help: "Filter by display name.")
    var display: String?

    @Option(name: .shortAndLong, help: "Max entries to show.")
    var limit: Int = 20

    func run() throws {
        guard let store = DataLayer.store() else {
            print("  No calibration database found. Run 'dcal status' first.")
            return
        }

        let displays = try store.allDisplays()
        if displays.isEmpty {
            print("  No calibration data yet. Run 'dcal status' to start collecting.")
            return
        }

        // Filter displays if --display was provided.
        let filtered: [DisplayTwin]
        if let nameFilter = display {
            let lowered = nameFilter.lowercased()
            filtered = displays.filter { $0.name.lowercased().contains(lowered) }
            if filtered.isEmpty {
                print("  No display matching '\(nameFilter)'.")
                print("  Known displays: \(displays.map(\.name).joined(separator: ", "))")
                return
            }
        } else {
            filtered = displays
        }

        // Date formatter for human-readable timestamps.
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"

        print("dcal -- Calibration History")
        print("════════════════════════════════════════════════════════════════════════")

        var totalShown = 0

        for twin in filtered {
            // Query calibrations for this display, up to the remaining limit.
            let remaining = limit - totalShown
            guard remaining > 0 else { break }
            let calibrations = try store.calibrations(displayID: twin.id, limit: remaining)

            if calibrations.isEmpty { continue }

            print("")
            print("  \(twin.name) [\(twin.id.prefix(8))...]")
            print("  ┌──────────────────┬────────┬────────┬────────┬──────────┐")
            print("  │ Timestamp        │ Target │ Before │ After  │ Status   │")
            print("  ├──────────────────┼────────┼────────┼────────┼──────────┤")

            for cal in calibrations {
                let ts = dateFmt.string(from: cal.timestamp)
                let target = String(format: "γ%.2f", cal.targetGamma)
                let before = String(format: "%.3f", cal.measuredGammaBefore)
                let after  = String(format: "%.3f", cal.measuredGammaAfter)
                let deltaE = abs(cal.measuredGammaAfter - cal.targetGamma)
                let status: String
                if !cal.success {
                    status = "FAILED"
                } else if deltaE < 0.02 {
                    status = "OK"
                } else {
                    status = String(format: "ΔE %.3f", deltaE)
                }
                print("  │ \(ts) │ \(target) │ \(before) │ \(after) │ \(status.padding(toLength: 8, withPad: " ", startingAt: 0)) │")
                totalShown += 1
            }

            print("  └──────────────────┴────────┴────────┴────────┴──────────┘")
        }

        if totalShown == 0 {
            print("  No calibrations recorded yet. Run 'dcal calibrate' first.")
        } else {
            print("")
            print("  \(totalShown) calibration\(totalShown == 1 ? "" : "s") shown.")
        }
    }
}

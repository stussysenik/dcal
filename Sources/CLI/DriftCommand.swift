/* CLI -- Drift command.
   Shows gamma drift over time as an ASCII sparkline chart.
   
   Learner note: This command queries the time-series data from the store
   and renders a sparkline using Unicode block elements (▁▂▃▄▅▆▇█).
   Sparklines are a compact way to visualise trends in a terminal -- each
   character maps to a value bucket within the min/max range.
   
   Usage:
     dcal drift                         # all displays, last 30 days
     dcal drift --display "LG 27"       # specific display
     dcal drift --days 90               # longer time window
     dcal drift --metric gammaR         # specific channel */

import ArgumentParser
import Foundation
import Application
import Infrastructure

struct Drift: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show gamma drift over time as ASCII sparkline."
    )

    @Option(name: .long, help: "Filter by display name.")
    var display: String?

    @Option(name: .shortAndLong, help: "Number of days to look back.")
    var days: Int = 30

    @Option(name: .shortAndLong, help: "Metric to chart: gamma, gammaR, gammaG, gammaB, channelDeviation, bandingRisk.")
    var metric: String = "gamma"

    func run() throws {
        guard let store = DataLayer.store() else {
            print("  No calibration database found. Run 'dcal status' first.")
            return
        }

        // Parse the metric kind from the string argument.
        guard let metricKind = MetricKind(rawValue: metric) else {
            print("  Unknown metric '\(metric)'.")
            print("  Available: \(MetricKind.allCases.map(\.rawValue).joined(separator: ", "))")
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
                return
            }
        } else {
            filtered = displays
        }

        let since = Date().addingTimeInterval(-Double(days) * 86400)

        print("dcal -- Gamma Drift (\(metricKind.rawValue), last \(days) days)")
        print("════════════════════════════════════════════════════════════")

        for twin in filtered {
            let series = try store.timeSeries(
                displayID: twin.id,
                metric: metricKind,
                since: since
            )

            print("")
            print("  \(twin.name) [\(twin.id.prefix(8))...]")

            if series.isEmpty {
                print("  (no measurements in this period)")
                continue
            }

            let values = series.map(\.value)
            let sparkline = Self.sparkline(values)
            let minVal = values.min()!
            let maxVal = values.max()!
            let avg = values.reduce(0.0, +) / Double(values.count)

            // Compute drift rate from store if available.
            let driftRate = try store.computeDriftRate(displayID: twin.id)

            print("  \(sparkline)")
            print("  min: \(String(format: "%.4f", minVal))  max: \(String(format: "%.4f", maxVal))  avg: \(String(format: "%.4f", avg))  samples: \(values.count)")

            if let rate = driftRate {
                let direction = rate > 0 ? "rising" : (rate < 0 ? "falling" : "stable")
                print("  drift: \(String(format: "%+.4f", rate))/week (\(direction))")
            } else {
                print("  drift: insufficient data (need 2+ measurements)")
            }
        }

        print("")
    }

    /// Render an array of Double values as a sparkline using block characters.
    ///
    /// The 8 block elements ▁▂▃▄▅▆▇█ map to equal-sized buckets within
    /// the [min, max] range.  If all values are identical, a flat mid-height
    /// bar (▄) is shown for each sample.
    static func sparkline(_ values: [Double]) -> String {
        let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        guard let minVal = values.min(), let maxVal = values.max() else {
            return ""
        }
        let range = maxVal - minVal
        return String(values.map { value in
            if range == 0 { return blocks[3] }  // Flat line at mid-height.
            let normalised = (value - minVal) / range
            let index = min(7, Int(normalised * 7.999))
            return blocks[index]
        })
    }
}

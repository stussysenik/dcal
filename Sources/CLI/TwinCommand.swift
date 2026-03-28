/* CLI -- Twin command.
   Shows the digital twin summary for each connected display.
   
   Learner note: A "digital twin" is a software representation of a physical
   device that tracks its state, history, and health over time.  In dcal,
   each display's twin stores calibration count, drift rate, and a computed
   health score.  This pattern is borrowed from industrial IoT where digital
   twins of factory equipment predict maintenance needs.
   
   Usage:
     dcal twin                     # summary of all displays
     dcal twin --display "LG 27"   # specific display */

import ArgumentParser
import Foundation
import Application
import Infrastructure

struct Twin: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show digital twin summary for connected displays."
    )

    @Option(name: .long, help: "Filter by display name.")
    var display: String?

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
                return
            }
        } else {
            filtered = displays
        }

        // Date formatter for first/last seen.
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"

        print("dcal -- Digital Twin Summary")
        print("════════════════════════════════════════════════════════════")

        for twin in filtered {
            let healthPct = Int(twin.healthScore * 100)
            let healthBar = Self.healthBar(twin.healthScore)
            let healthLabel = Self.healthLabel(twin.healthScore)

            print("")
            print("  \(twin.name)")
            print("  ┌─────────────────────────────────────────────────────")
            print("  │ ID              \(twin.id)")
            print("  │ Vendor/Model    0x\(String(twin.vendorID, radix: 16, uppercase: true)) / 0x\(String(twin.modelID, radix: 16, uppercase: true))")
            print("  │ Native Gamma    \(String(format: "%.2f", twin.nativeGamma))")
            print("  │ Bit Depth       \(twin.bitDepth)-bit")
            print("  │ Color Space     \(twin.colorSpace)")
            print("  │ First Seen      \(dateFmt.string(from: twin.firstSeen))")
            print("  │ Last Seen       \(dateFmt.string(from: twin.lastSeen))")
            print("  │")
            print("  │ Calibrations    \(twin.calibrationCount)")
            if let drift = twin.driftRate {
                let direction = drift > 0 ? "rising" : (drift < 0 ? "falling" : "stable")
                print("  │ Drift Rate      \(String(format: "%+.4f", drift))/week (\(direction))")
            } else {
                print("  │ Drift Rate      -- (insufficient data)")
            }
            print("  │")
            print("  │ Health          \(healthBar) \(healthPct)% \(healthLabel)")
            print("  └─────────────────────────────────────────────────────")
        }

        print("")
        print("  \(filtered.count) display\(filtered.count == 1 ? "" : "s") tracked.")
    }

    /// Render a 10-segment health bar using Unicode block characters.
    ///
    /// Score 0.0 = all empty (░), score 1.0 = all filled (█).
    /// Intermediate scores fill proportionally.
    static func healthBar(_ score: Double) -> String {
        let filled = Int((score * 10).rounded())
        let empty = 10 - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    /// Human-readable label for a health score.
    static func healthLabel(_ score: Double) -> String {
        switch score {
        case 0.8...1.0: return "(excellent)"
        case 0.6..<0.8: return "(good)"
        case 0.4..<0.6: return "(fair)"
        default:        return "(needs attention)"
        }
    }
}

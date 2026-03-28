/* DisplayStateModel — @Observable state for the menu bar popover.
   Bridges the Infrastructure layer (DisplayDetector, GammaAdapter)
   into SwiftUI's observation system.

   Refresh cycle:
   1. DisplayDetector enumerates all connected displays via CoreGraphics
   2. GammaAdapter reads the gamma ramp from the selected display
   3. analyzeGamma fits a power-law curve to extract per-channel gamma
   4. SwiftUI observes the published properties and re-renders */

import SwiftUI
import Application
import Infrastructure

@MainActor
@Observable
final class DisplayStateModel {
    var displays: [DisplayInfo] = []
    var selectedIndex: Int = 0

    // Gamma analysis results — extracted from the display's gamma ramp
    var gammaR: Double = 0
    var gammaG: Double = 0
    var gammaB: Double = 0
    var gammaAvg: Double = 0
    var channelDeviation: Double = 0

    var isCalibrating = false

    /// The currently selected display, if any.
    var selectedDisplay: DisplayInfo? {
        guard selectedIndex >= 0, selectedIndex < displays.count else { return nil }
        return displays[selectedIndex]
    }

    /// Refresh display list and gamma data from hardware.
    func refresh() {
        let detector = DisplayDetector()
        let gamma = GammaAdapter()

        Task {
            do {
                displays = try await detector.connectedDisplays()
                if let display = selectedDisplay,
                   let ramp = gamma.readGamma(displayID: display.id) {
                    let analysis = gamma.analyzeGamma(ramp)
                    gammaR = analysis.redGamma
                    gammaG = analysis.greenGamma
                    gammaB = analysis.blueGamma
                    gammaAvg = analysis.averageGamma
                    channelDeviation = analysis.channelDeviation
                }
            } catch {
                // Display enumeration failed — leave state unchanged
            }
        }
    }
}

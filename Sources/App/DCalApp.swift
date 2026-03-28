/* DCalApp — Menu bar entry point.
   Runs as a macOS menu bar extra (no dock icon, no main window).
   The popover displays real-time display calibration data from
   the Infrastructure layer's DisplayDetector and GammaAdapter. */

import SwiftUI

@main
struct DCalApp: App {
    @State private var state = DisplayStateModel()

    var body: some Scene {
        MenuBarExtra {
            DCalPopover()
                .environment(state)
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}

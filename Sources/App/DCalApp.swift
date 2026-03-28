/* DCalApp — Menu bar entry point.
   Runs as a macOS menu bar extra (no dock icon, no main window).
   The popover displays real-time display calibration data from
   the Infrastructure layer's DisplayDetector and GammaAdapter. */

import SwiftUI
import Infrastructure

@main
struct DCalApp: App {
    @State private var state = DisplayStateModel()

    init() {
        // Restore the system's default gamma table on any exit path
        // (Cmd-Q, SIGTERM, etc.) so the display isn't left modified.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            GammaAdapter().restoreDefaults()
        }
    }

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

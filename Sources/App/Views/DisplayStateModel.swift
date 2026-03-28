/* DisplayStateModel — @Observable state for the menu bar popover.
   Bridges the Infrastructure layer (DisplayDetector, GammaAdapter)
   into SwiftUI's observation system.

   Refresh cycle:
   1. DisplayDetector enumerates all connected displays via CoreGraphics
   2. GammaAdapter reads the gamma ramp from the selected display
   3. analyzeGamma fits a power-law curve to extract per-channel gamma
   4. SwiftUI observes the published properties and re-renders

   Slider pipeline:
   1. User drags a slider → sliderChanged() debounces (50ms)
   2. applyGamma() composes brightness + contrast + white point into a LUT
   3. LUT is written to the display via GammaAdapter.writeGamma()
   4. Gamma readout is updated from the applied ramp */

import SwiftUI
import Domain
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

    // Slider state — drives the gamma ramp applied to the display
    var brightness: Double = 100
    var contrast: Double = 50
    var whitePointKelvin: Double = 6500
    var selectedPreset: CalibrationPreset = .rec709

    private var applyTask: Task<Void, Never>?

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

    /// Called when any slider value changes. Debounces rapid updates
    /// to avoid hammering CoreGraphics during drag.
    func sliderChanged() {
        applyTask?.cancel()
        applyTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            applyGamma()
        }
    }

    /// Set slider values to match a calibration preset.
    func applyPreset(_ preset: CalibrationPreset) {
        switch preset {
        case .rec709:
            brightness = 100
            contrast = 55
            whitePointKelvin = 6500
        case .dciP3:
            brightness = 100
            contrast = 63
            whitePointKelvin = 6300
        case .sRGB:
            brightness = 100
            contrast = 50
            whitePointKelvin = 6500
        }
        sliderChanged()
    }

    /// Compose the current slider values into a gamma ramp and apply it.
    private func applyGamma() {
        guard let display = selectedDisplay else { return }

        let lut = RampComposer.compose(
            brightness: brightness,
            contrast: contrast,
            whitePointKelvin: whitePointKelvin
        )

        let ramp = GammaRamp(red: lut.red, green: lut.green, blue: lut.blue)
        let gamma = GammaAdapter()
        let success = gamma.writeGamma(displayID: display.id, ramp: ramp)

        if success {
            if let readBack = gamma.readGamma(displayID: display.id) {
                let analysis = gamma.analyzeGamma(readBack)
                gammaR = analysis.redGamma
                gammaG = analysis.greenGamma
                gammaB = analysis.blueGamma
                gammaAvg = analysis.averageGamma
                channelDeviation = analysis.channelDeviation
            }
        }
    }
}

/* DCalPopover — Main menu bar popover view.
   340pt-wide panel with real display data from the Infrastructure layer.

   Visual hierarchy (top to bottom):
   1. Header — display name, resolution badge, color space
   2. Gamma readout — per-channel R/G/B values + average
   3. Adjustment sliders — brightness, contrast, white point
   4. Preset picker — calibration target (Rec.709, DCI-P3, sRGB)
   5. Calibrate button
   6. Footer — Settings, Quit

   Aesthetic: DaVinci Resolve / professional film equipment.
   Dark achromatic surfaces, chromatic color only for data. */

import SwiftUI
import Application

struct DCalPopover: View {
    @Environment(DisplayStateModel.self) private var state

    // Local slider state — not wired to hardware yet (future task)
    @State private var brightness: Double = 50
    @State private var contrast: Double = 50
    @State private var whitePoint: Double = 6500
    @State private var selectedPreset: CalibrationPreset = .rec709

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection

            Divider()
                .background(Color.dcSurface3)

            ScrollView {
                VStack(spacing: DCLayout.sectionSpacing) {
                    // MARK: - Gamma Readout
                    GammaReadout(
                        redGamma: state.gammaR,
                        greenGamma: state.gammaG,
                        blueGamma: state.gammaB,
                        averageGamma: state.gammaAvg,
                        channelDeviation: state.channelDeviation
                    )

                    // MARK: - Adjustment Sliders
                    adjustmentSection

                    // MARK: - Preset Picker
                    PresetPicker(selection: $selectedPreset)

                    // MARK: - Calibrate Button
                    calibrateButton
                }
                .padding(DCLayout.contentPadding)
            }

            Divider()
                .background(Color.dcSurface3)

            // MARK: - Footer
            footerSection
        }
        .frame(width: DCLayout.panelWidth)
        .background(Color.dcSurface1)
        .onAppear {
            state.refresh()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let display = state.selectedDisplay {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.dcHeading)
                            .foregroundStyle(Color.dcTextPrimary)
                            .lineLimit(1)

                        Text(display.colorSpace)
                            .font(.dcCaption)
                            .foregroundStyle(Color.dcTextTertiary)
                    }
                    Spacer()
                    // Resolution + bit depth badge
                    metadataBadge(display: display)
                }
            } else {
                Text("No display detected")
                    .font(.dcLabel)
                    .foregroundStyle(Color.dcTextSecondary)
            }

            // Display picker when multiple displays are connected
            if state.displays.count > 1 {
                displayPicker
            }
        }
        .padding(DCLayout.contentPadding)
    }

    private func metadataBadge(display: DisplayInfo) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(display.resolution.width)x\(display.resolution.height)")
                .font(.dcNumericSmall)
                .foregroundStyle(Color.dcTextSecondary)
            Text("\(display.bitDepth)-bit  \(display.controlMethod.rawValue)")
                .font(.dcCaption)
                .foregroundStyle(Color.dcTextTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.dcSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @MainActor
    private var displayPicker: some View {
        Picker("Display", selection: Bindable(state).selectedIndex) {
            ForEach(Array(state.displays.enumerated()), id: \.offset) { index, display in
                Text(display.name).tag(index)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onChange(of: state.selectedIndex) {
            state.refresh()
        }
    }

    // MARK: - Adjustments

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADJUSTMENTS")
                .font(.dcSectionHeader)
                .foregroundStyle(Color.dcTextTertiary)

            SliderControl(label: "Brightness", value: $brightness)
            SliderControl(label: "Contrast", value: $contrast)
            SliderControl(
                label: "White Point (K)",
                value: $whitePoint,
                range: 4000...10000,
                format: "%.0f"
            )
        }
        .padding(DCLayout.contentPadding)
        .background(Color.dcSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Calibrate Button

    private var calibrateButton: some View {
        Button(action: {
            state.isCalibrating.toggle()
        }) {
            HStack {
                if state.isCalibrating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
                Text(state.isCalibrating ? "Calibrating..." : "Calibrate")
                    .font(.dcLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.dcSurface3)
        .disabled(state.selectedDisplay == nil)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Settings") {
                // Future: open settings window
            }
            .buttonStyle(.plain)
            .font(.dcLabel)
            .foregroundStyle(Color.dcTextSecondary)

            Spacer()

            Button("Refresh") {
                state.refresh()
            }
            .buttonStyle(.plain)
            .font(.dcLabel)
            .foregroundStyle(Color.dcTextSecondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.dcLabel)
            .foregroundStyle(Color.dcTextSecondary)
        }
        .padding(.horizontal, DCLayout.contentPadding)
        .padding(.vertical, 10)
    }
}

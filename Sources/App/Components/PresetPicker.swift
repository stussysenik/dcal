/* PresetPicker — Segmented control for calibration target presets.
   Each preset represents a standard color space / transfer function
   combination used in professional color workflows.

   - Rec.709: HD broadcast (gamma 2.4, BT.709 primaries)
   - DCI-P3:  Digital cinema (gamma 2.6, DCI-P3 primaries)
   - sRGB:    Web/general use (sRGB EOTF ~2.2, sRGB primaries) */

import SwiftUI

/// Available calibration target presets.
enum CalibrationPreset: String, CaseIterable, Identifiable {
    case rec709 = "Rec.709"
    case dciP3  = "DCI-P3"
    case sRGB   = "sRGB"

    var id: String { rawValue }
}

struct PresetPicker: View {
    @Binding var selection: CalibrationPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TARGET")
                .font(.dcSectionHeader)
                .foregroundStyle(Color.dcTextTertiary)
            Picker("Target", selection: $selection) {
                ForEach(CalibrationPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

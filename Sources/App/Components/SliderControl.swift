/* SliderControl — Labeled slider with numeric readout.
   Standard control for brightness, contrast, and white point adjustments.

   Layout:
   ┌──────────────────────────────────┐
   │ Brightness            75%       │
   │ ═══════════════════○─────────── │
   └──────────────────────────────────┘ */

import SwiftUI

struct SliderControl: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let isEnabled: Bool

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...100,
        format: String = "%.0f",
        isEnabled: Bool = true
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.isEnabled = isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.dcLabel)
                    .foregroundStyle(isEnabled ? Color.dcTextSecondary : Color.dcTextTertiary)
                Spacer()
                Text(String(format: format, value))
                    .font(.dcNumericSmall)
                    .foregroundStyle(isEnabled ? Color.dcTextPrimary : Color.dcTextTertiary)
            }
            Slider(value: $value, in: range)
                .tint(isEnabled ? Color.dcTextTertiary : Color.dcSurface3)
                .disabled(!isEnabled)
        }
    }
}

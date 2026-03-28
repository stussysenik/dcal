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

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...100,
        format: String = "%.0f"
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.dcLabel)
                    .foregroundStyle(Color.dcTextSecondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.dcNumericSmall)
                    .foregroundStyle(Color.dcTextPrimary)
            }
            Slider(value: $value, in: range)
                .tint(Color.dcTextTertiary)
        }
    }
}

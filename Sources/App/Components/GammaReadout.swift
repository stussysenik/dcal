/* GammaReadout — Displays per-channel gamma values (R/G/B) and
   the weighted average. Each channel gets a colored dot indicator
   (the only chromatic elements in the achromatic UI).

   Layout:
   ┌─────────────────────────────────┐
   │  GAMMA           avg: 2.20     │
   │  ● R 2.19  ● G 2.20  ● B 2.21 │
   │  deviation: 0.01               │
   └─────────────────────────────────┘ */

import SwiftUI

struct GammaReadout: View {
    let redGamma: Double
    let greenGamma: Double
    let blueGamma: Double
    let averageGamma: Double
    let channelDeviation: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header + average readout
            HStack {
                Text("GAMMA")
                    .font(.dcSectionHeader)
                    .foregroundStyle(Color.dcTextTertiary)
                Spacer()
                Text(String(format: "%.2f", averageGamma))
                    .font(.dcNumericLarge)
                    .foregroundStyle(Color.dcTextPrimary)
            }

            // Per-channel values with colored dot indicators
            HStack(spacing: 16) {
                channelValue(color: .dcChannelR, label: "R", value: redGamma)
                channelValue(color: .dcChannelG, label: "G", value: greenGamma)
                channelValue(color: .dcChannelB, label: "B", value: blueGamma)
            }

            // Channel deviation — indicates how balanced R/G/B are
            HStack {
                Text("deviation")
                    .font(.dcCaption)
                    .foregroundStyle(Color.dcTextTertiary)
                Text(String(format: "%.3f", channelDeviation))
                    .font(.dcNumericSmall)
                    .foregroundStyle(
                        channelDeviation < 0.02
                            ? Color.dcPass
                            : Color.dcWarn
                    )
            }
        }
        .padding(DCLayout.contentPadding)
        .background(Color.dcSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func channelValue(color: Color, label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.dcCaption)
                .foregroundStyle(Color.dcTextTertiary)
            Text(String(format: "%.2f", value))
                .font(.dcNumericMedium)
                .foregroundStyle(Color.dcTextPrimary)
        }
    }
}

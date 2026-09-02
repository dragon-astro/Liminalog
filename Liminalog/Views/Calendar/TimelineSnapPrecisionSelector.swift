import SwiftUI

struct TimelineSnapPrecisionSelector: View {
    @Binding var precision: TimelineSnapPrecision

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LiminalTheme.accent)

                Text("移動・長さ調整の間隔")
                    .font(.body)
                    .foregroundStyle(LiminalTheme.text)

                Spacer(minLength: 0)

                Text("\(precision.shortLabel)分")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()
            }

            Slider(
                value: precisionIndex,
                in: 0...Double(TimelineSnapPrecision.sliderOptions.count - 1),
                step: 1
            )
            .tint(LiminalTheme.accent)
            .accessibilityLabel("予定調整の刻み幅")
            .accessibilityValue("\(precision.minutes)分")

            HStack(spacing: 0) {
                ForEach(TimelineSnapPrecision.sliderOptions) { option in
                    Text("\(option.shortLabel)分")
                        .font(.caption2.weight(precision == option ? .bold : .medium))
                        .foregroundStyle(precision == option ? LiminalTheme.accent : LiminalTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
        }
        .accessibilityHint("予定の移動と長さ調整に使う刻み幅を変更")
        .accessibilityIdentifier("timeline-snap-selector")
    }

    private var precisionIndex: Binding<Double> {
        Binding(
            get: {
                Double(TimelineSnapPrecision.sliderOptions.firstIndex(of: precision) ?? 0)
            },
            set: { proposedIndex in
                let index = min(
                    TimelineSnapPrecision.sliderOptions.count - 1,
                    max(0, Int(proposedIndex.rounded()))
                )
                let newPrecision = TimelineSnapPrecision.sliderOptions[index]
                guard precision != newPrecision else { return }
                precision = newPrecision
                LiminalHaptics.selection()
            }
        )
    }
}

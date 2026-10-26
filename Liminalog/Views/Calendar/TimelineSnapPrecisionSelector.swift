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

            DiscreteSettingSlider(selection: precisionIndex,
                count: TimelineSnapPrecision.sliderOptions.count,
                labels: TimelineSnapPrecision.sliderOptions.map { "\($0.minutes)分" },
                accessibilityTitle: "予定調整の刻み幅", accessibilityText: "\(precision.minutes)分")
                .accessibilityIdentifier("timeline-snap-selector")
        }
        .accessibilityHint("予定の移動と長さ調整に使う刻み幅を変更")
    }

    private var precisionIndex: Binding<Int> {
        Binding(
            get: {
                TimelineSnapPrecision.sliderOptions.firstIndex(of: precision) ?? 0
            },
            set: { proposedIndex in
                let index = min(
                    TimelineSnapPrecision.sliderOptions.count - 1,
                    max(0, proposedIndex)
                )
                let newPrecision = TimelineSnapPrecision.sliderOptions[index]
                guard precision != newPrecision else { return }
                precision = newPrecision
            }
        )
    }
}

import SwiftUI

struct TimelineSnapPrecisionSelector: View {
    @Binding var precision: TimelineSnapPrecision

    var body: some View {
        Menu {
            ForEach(TimelineSnapPrecision.allCases) { option in
                Button {
                    guard precision != option else { return }
                    precision = option
                    LiminalHaptics.selection()
                } label: {
                    HStack {
                        Text(option.accessibilityLabel)
                        if precision == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("timeline-snap-\(option.minutes)")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiminalTheme.accent)

                Text("\(precision.shortLabel)分")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LiminalTheme.text)
                    .monospacedDigit()

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 64, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Capsule(style: .continuous)
                .fill(LiminalTheme.surface.opacity(0.96))
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: LiminalTheme.dusk.opacity(0.18), radius: 5, y: 2)
        .accessibilityLabel("予定調整の刻み幅、\(precision.minutes)分")
        .accessibilityHint("予定の移動と長さ調整に使う刻み幅を変更")
        .accessibilityIdentifier("timeline-snap-selector")
    }
}

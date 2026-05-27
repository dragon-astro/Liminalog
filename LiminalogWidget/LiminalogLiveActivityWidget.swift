import AppIntents
import ActivityKit
import SwiftUI
import WidgetKit

struct LiminalogLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiminalogActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color(hex: context.state.colorHex).opacity(0.16))
                .activitySystemActionForegroundColor(Color(hex: context.state.colorHex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CurrentCategoryBadge(state: context.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let startedAt = context.state.startedAt {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityCategoryControls(state: context.state)
                }
            } compactLeading: {
                CategoryIcon(state: context.state, size: 22)
            } compactTrailing: {
                if let startedAt = context.state.startedAt {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 42)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
            } minimal: {
                CategoryIcon(state: context.state, size: 18)
            }
            .keylineTint(Color(hex: context.state.colorHex))
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let state: LiminalogActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(state: state, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.categoryName ?? "記録中")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(state.categorySetName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            if let startedAt = state.startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct CurrentCategoryBadge: View {
    let state: LiminalogActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(state: state, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.categoryName ?? "記録中")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("記録中")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 128, alignment: .leading)
    }
}

private struct LiveActivityCategoryControls: View {
    let state: LiminalogActivityAttributes.ContentState

    var body: some View {
        if state.categories.isEmpty {
            HStack(spacing: 8) {
                Label(state.categorySetName, systemImage: "square.grid.2x2")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                Label(state.isPublic ? "公開" : "非公開", systemImage: state.isPublic ? "eye" : "eye.slash")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        } else {
            HStack(spacing: 8) {
                ForEach(state.categories) { category in
                    Button(intent: StartChapterIntent(categoryID: category.id.uuidString)) {
                        DynamicIslandCategoryButton(
                            category: category,
                            isActive: category.id == state.activeCategoryID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct DynamicIslandCategoryButton: View {
    let category: LiminalogActivityAttributes.IslandCategory
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(hex: category.colorHex).opacity(isActive ? 1 : 0.24))
                    .frame(width: 20, height: 20)
                Image(systemName: category.icon ?? "circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isActive ? .white : Color(hex: category.colorHex))
            }

            Text(category.name)
                .font(.caption2.weight(isActive ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: 72)
        .background(
            Capsule()
                .fill(Color(hex: category.colorHex).opacity(isActive ? 0.22 : 0.1))
        )
    }
}

private struct CategoryIcon: View {
    let state: LiminalogActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: state.colorHex))

            Image(systemName: state.icon ?? "circle.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 0x8E
            green = 0x8E
            blue = 0x93
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}

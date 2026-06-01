import AppIntents
import ActivityKit
import SwiftUI
import WidgetKit

struct LiminalogLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiminalogActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color.cachedHex(context.state.colorHex).opacity(0.16))
                .activitySystemActionForegroundColor(Color.cachedHex(context.state.colorHex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCurrentActivityHeader(state: context.state)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityCategoryControls(state: context.state)
                }
            } compactLeading: {
                CategoryIcon(state: context.state, size: 15)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                if let startedAt = context.state.startedAt {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            } minimal: {
                CategoryIcon(state: context.state, size: 12)
            }
            .keylineTint(Color.cachedHex(context.state.colorHex))
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

private struct ExpandedCurrentActivityHeader: View {
    let state: LiminalogActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(state: state, size: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.categoryName ?? "記録中")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(state.categorySetName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            if let startedAt = state.startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 22)
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
            LazyVGrid(columns: columns, spacing: 8) {
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
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    }
}

private struct DynamicIslandCategoryButton: View {
    let category: LiminalogActivityAttributes.IslandCategory
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.cachedHex(category.colorHex).opacity(isActive ? 1 : 0.24))
                    .frame(width: 18, height: 18)
                Image(systemName: category.icon ?? "circle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? .white : Color.cachedHex(category.colorHex))
            }

            Text(category.name)
                .font(.system(size: 9, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.cachedHex(category.colorHex) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(
            Capsule()
                .fill(Color.cachedHex(category.colorHex).opacity(isActive ? 0.22 : 0.1))
        )
        .overlay {
            if isActive {
                Capsule()
                    .stroke(Color.cachedHex(category.colorHex).opacity(0.85), lineWidth: 1)
            }
        }
        .contentShape(Capsule())
        .accessibilityLabel(category.name)
    }
}

private struct CategoryIcon: View {
    let state: LiminalogActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cachedHex(state.colorHex))

            Image(systemName: state.icon ?? "circle.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

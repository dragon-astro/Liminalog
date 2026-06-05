import SwiftUI
import SwiftData

struct CurrentChapterCard: View {
    @Environment(ChapterStore.self) private var store
    @Query private var activeChapters: [Chapter]
    @Query private var todayPlans: [PlanBlock]
    @State private var clock = TickClock()
    @State private var operationError: String?

    init() {
        let boundary = DayBoundary(date: Date(), calendar: .japanese)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        _activeChapters = Query(
            filter: #Predicate<Chapter> { $0.endTime == nil },
            sort: [SortDescriptor(\.startTime, order: .reverse)]
        )
        _todayPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < dayEnd && $0.endTime > dayStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    var body: some View {
        Group {
            if let chapter = activeChapter, let category = chapter.category {
                activeCard(chapter: chapter, category: category, currentPlan: currentPlan)
            } else if let currentPlan {
                planContextCard(plan: currentPlan)
            } else {
                placeholderCard
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentPlan == nil ? 48 : 76)
        .liminalSectionCard(cornerRadius: 16, padding: 8)
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK") {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var activeChapter: Chapter? {
        activeChapters.first
    }

    private var currentPlans: [PlanBlock] {
        let now = clock.now
        return todayPlans.filter { plan in
            !plan.isAllDay && plan.startTime <= now && now < plan.endTime
        }
    }

    private var currentPlan: PlanBlock? {
        currentPlans.first
    }

    private func activeCard(chapter: Chapter, category: Category, currentPlan: PlanBlock?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                CurrentRibbonLabel(text: "実績", tint: category.displayColor, style: .filled)

                Circle()
                    .fill(category.displayColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: category.displayColor.opacity(0.4), radius: 4, x: 0, y: 2)

                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(formatDuration(clock.now.timeIntervalSince(chapter.startTime)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)

                Button {
                    guard store.endActiveChapter() else {
                        operationError = "記録を終了できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(category.displayColor)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("記録を終了")

                Button {
                    guard store.setChapterVisibility(chapter, isPublic: !chapter.isPublic) else {
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                } label: {
                    Image(systemName: chapter.isPublic ? "eye" : "eye.slash")
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            if let currentPlan {
                planContextRow(
                    plan: currentPlan,
                    actualCategory: category,
                    showsExtraCount: currentPlans.count > 1
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, currentPlan == nil ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liminalCanvasChip(tint: category.displayColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

    private func planContextCard(plan: PlanBlock) -> some View {
        let tint = planTint(plan)
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                CurrentRibbonLabel(text: "実績", tint: LiminalTheme.secondaryText, style: .muted)

                Image(systemName: "pause.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)

                Text("未記録")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)

                Spacer()
            }

            planContextRow(plan: plan, actualCategory: nil, showsExtraCount: currentPlans.count > 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liminalCanvasChip(tint: tint, in: RoundedRectangle(cornerRadius: 12))
    }

    private func planContextRow(plan: PlanBlock, actualCategory: Category?, showsExtraCount: Bool) -> some View {
        let tint = planTint(plan)
        let isMatched = actualCategory?.id == plan.category?.id
        return HStack(spacing: 8) {
            CurrentRibbonLabel(text: "予定", tint: tint, style: .outlined)

            Image(systemName: plan.category?.icon ?? "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(planDisplayTitle(plan))
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(planTimeRange(plan))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)

            if isMatched {
                Label("一致", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .labelStyle(.titleAndIcon)
            }

            if showsExtraCount {
                Text("+\(currentPlans.count - 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholderCard: some View {
        Text("カテゴリをタップして記録を開始")
            .font(.caption)
            .foregroundStyle(LiminalTheme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planTint(_ plan: PlanBlock) -> Color {
        plan.category?.displayColor ?? LiminalTheme.accent
    }

    private func planDisplayTitle(_ plan: PlanBlock) -> String {
        let trimmed = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return plan.category?.name ?? "予定"
    }

    private func planTimeRange(_ plan: PlanBlock) -> String {
        "\(plan.startTime.shortTime)-\(plan.endTime.shortTime)"
    }
}

private struct CurrentRibbonLabel: View {
    enum Style {
        case filled
        case outlined
        case muted
    }

    let text: String
    let tint: Color
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(background, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(border, lineWidth: style == .outlined ? 1 : 0)
            )
            .lineLimit(1)
    }

    private var foreground: Color {
        switch style {
        case .filled:
            return .white
        case .outlined:
            return tint
        case .muted:
            return LiminalTheme.secondaryText
        }
    }

    private var background: Color {
        switch style {
        case .filled:
            return tint
        case .outlined:
            return tint.opacity(0.1)
        case .muted:
            return LiminalTheme.elevated
        }
    }

    private var border: Color {
        style == .outlined ? tint.opacity(0.35) : .clear
    }
}

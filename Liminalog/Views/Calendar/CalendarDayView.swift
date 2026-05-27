import SwiftUI

struct CalendarDayView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var editingChapter: Chapter?
    @State private var editingPlan: PlanBlock?
    @State private var pendingCreateDate: Date
    @State private var pendingPlanStartsAsImportant = false
    @State private var showingPlanSheet = false

    private let highlightedPlanID: UUID?

    init(date: Date, highlightedPlanID: UUID? = nil) {
        self.highlightedPlanID = highlightedPlanID
        _date = State(initialValue: date)
        _pendingCreateDate = State(initialValue: date)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dayHeader
                scoreArea
                importantPlanArea
                timelineArea
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                dayVisibilityMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        pendingCreateDate = Calendar.japanese.startOfDay(for: date)
                        pendingPlanStartsAsImportant = true
                        showingPlanSheet = true
                    } label: {
                        Label("重要な予定を追加", systemImage: "star")
                    }

                    if canCreateTimedPlansForDay {
                        Button {
                            pendingCreateDate = defaultChapterStart
                            pendingPlanStartsAsImportant = false
                            showingPlanSheet = true
                        } label: {
                            Label("時間つき予定を追加", systemImage: "calendar.badge.plus")
                        }
                    } else {
                        Label("今日以前の時間つき予定は追加できません", systemImage: "lock.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -50 {
                        shiftDay(1)
                    } else if value.translation.width > 50 {
                        shiftDay(-1)
                    }
                }
        )
        .sheet(item: $editingChapter) { chapter in
            ChapterEditSheet(chapter: chapter)
        }
        .sheet(item: $editingPlan) { plan in
            PlanCreateSheet(plan: plan)
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsImportant)
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(date.japaneseMonthDayWeekday)
                    .font(.title3.bold())
                Text(daySummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .id(store.revision)
    }

    private var scoreArea: some View {
        let summary = store.scoreSummary(on: date)
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("スコア", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.gradeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(scoreText(summary))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(summary))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(scoreColor(summary).opacity(summary.plannedDuration > 0 ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(scoreColor(summary).opacity(summary.plannedDuration > 0 ? 0.2 : 0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スコア \(scoreText(summary)) \(summary.gradeText)")
    }

    private var importantPlanArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                Text("重要な予定")
                    .font(.headline)
            }

            if importantPlans.isEmpty {
                Button {
                    pendingCreateDate = Calendar.japanese.startOfDay(for: date)
                    pendingPlanStartsAsImportant = true
                    showingPlanSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("重要な予定を追加")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(importantPlans) { plan in
                    Button {
                        editingPlan = plan
                    } label: {
                        ImportantPlanRow(plan: plan, isHighlighted: plan.id == highlightedPlanID)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingPlan = plan
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        if store.isPlanScheduleLocked(plan) {
                            Label("今日以前の予定は削除できません", systemImage: "lock.fill")
                        } else {
                            Button(role: .destructive) {
                                store.deletePlanBlock(plan)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .id(store.revision)
    }

    private var timelineArea: some View {
        TimelineView(
            date: date,
            title: "タイムライン",
            compactEmptyState: true,
            editingChapter: $editingChapter,
            allowsChapterCreation: false,
            focusedPlanID: highlightedPlanID
        )
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var importantPlans: [PlanBlock] {
        store.plannedBlocks(on: date)
            .filter { $0.isAllDay || $0.isImportant }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private var timedPlans: [PlanBlock] {
        store.plannedBlocks(on: date).filter { !$0.isAllDay }
    }

    private var daySummaryText: String {
        "重要 \(importantPlans.count)件 / 時間つき予定 \(timedPlans.count)件"
    }

    private var canCreateTimedPlansForDay: Bool {
        store.canCreatePlan(startTime: date, isAllDay: false)
    }

    private func scoreText(_ summary: ScoreSummary) -> String {
        summary.plannedDuration > 0 ? "\(Int(summary.totalScore.rounded()))" : "--"
    }

    private func scoreColor(_ summary: ScoreSummary) -> Color {
        guard summary.plannedDuration > 0 else { return .secondary }
        switch summary.totalScore {
        case 85...:
            return .green
        case 65..<85:
            return .teal
        case 40..<65:
            return .orange
        case 1..<40:
            return .red
        default:
            return .secondary
        }
    }

    /// 日単位の公開設定メニュー。今日のチャプター全体に対して一括で操作する。
    /// アイコンは「全公開: eye」「全非公開: eye.slash」「混在: eye.fill (アクセントカラー)」で表現。
    private var dayVisibilityMenu: some View {
        let dayChapters = store.chapters(on: date)
        let allPublic = !dayChapters.isEmpty && dayChapters.allSatisfy(\.isPublic)
        let allPrivate = !dayChapters.isEmpty && dayChapters.allSatisfy { !$0.isPublic }
        let isMixed = !dayChapters.isEmpty && !allPublic && !allPrivate

        return Menu {
            if dayChapters.isEmpty {
                Text("この日にチャプターはありません")
            } else {
                if isMixed {
                    Text("公開/非公開が混在しています")
                        .font(.caption)
                }
                Button {
                    store.setChaptersVisibility(dayChapters, isPublic: true)
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    store.setChaptersVisibility(dayChapters, isPublic: false)
                } label: {
                    Label("すべて非公開", systemImage: "eye.slash")
                }
                .disabled(allPrivate)

                Divider()
                Text("\(dayChapters.count)件のチャプター")
                    .font(.caption)
            }
        } label: {
            Image(systemName: allPrivate ? "eye.slash" : (isMixed ? "eye.fill" : "eye"))
                .foregroundStyle(isMixed ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("この日の公開設定")
        .disabled(dayChapters.isEmpty)
    }

    private var defaultChapterStart: Date {
        let calendar = Calendar.japanese
        let now = Date()
        if calendar.isDateInToday(date) {
            return now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func shiftDay(_ value: Int) {
        date = Calendar.japanese.date(byAdding: .day, value: value, to: date) ?? date
    }
}

private struct ImportantPlanRow: View {
    let plan: PlanBlock
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 5)

            Image(systemName: plan.category?.icon ?? "star.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(dateRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? color.opacity(0.18) : color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHighlighted ? color.opacity(0.55) : color.opacity(0.16), lineWidth: isHighlighted ? 1.5 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        plan.category?.color ?? Color.accentColor
    }

    private var dateRangeText: String {
        let calendar = Calendar.japanese
        if !plan.isAllDay {
            return "\(plan.startTime.shortTime) - \(plan.endTime.shortTime)"
        }
        let planStart = calendar.startOfDay(for: plan.startTime)
        let inclusiveEnd = calendar.startOfDay(for: plan.endTime.addingTimeInterval(-1))
        if calendar.isDate(planStart, inSameDayAs: inclusiveEnd) {
            return planStart.japaneseMonthDayShortWeekday
        }
        return "\(planStart.japaneseMonthDayShortWeekday) - \(inclusiveEnd.japaneseMonthDayShortWeekday)"
    }
}

#Preview("Day") {
    NavigationStack {
        CalendarDayView(date: Date())
    }
    .liminalogPreviewEnvironment()
}

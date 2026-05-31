import SwiftUI
import SwiftData

struct CalendarDayView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var queriedPlans: [PlanBlock]
    @Query private var queriedChapters: [Chapter]

    @State private var date: Date
    @State private var editingChapter: Chapter?
    @State private var editingPlan: PlanBlock?
    @State private var pendingCreateDate: Date
    @State private var pendingPlanStartsAsImportant = false
    @State private var showingPlanSheet = false
    @State private var clock = TickClock(interval: 60)

    private let highlightedPlanID: UUID?
    private let showsNavigationControls: Bool
    private let allowsDayNavigation: Bool
    private let contentPadding: CGFloat
    private let showsPlanningStatus: Bool

    init(
        date: Date,
        highlightedPlanID: UUID? = nil,
        showsNavigationControls: Bool = true,
        allowsDayNavigation: Bool = true,
        contentPadding: CGFloat = 16,
        showsPlanningStatus: Bool = false
    ) {
        self.highlightedPlanID = highlightedPlanID
        self.showsNavigationControls = showsNavigationControls
        self.allowsDayNavigation = allowsDayNavigation
        self.contentPadding = contentPadding
        self.showsPlanningStatus = showsPlanningStatus
        _date = State(initialValue: date)
        _pendingCreateDate = State(initialValue: date)

        let boundary = DayBoundary(date: date, calendar: .japanese)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let chapterLookbackStart = Calendar.japanese.date(byAdding: .day, value: -14, to: dayStart) ?? dayStart
        _queriedPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < dayEnd && $0.endTime > dayStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
        _queriedChapters = Query(
            filter: #Predicate<Chapter> {
                $0.startTime >= chapterLookbackStart && $0.startTime < dayEnd
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsPlanningStatus {
                    planningDeadlineCard
                }
                dayHeader
                scoreArea
                importantPlanArea
                timelineArea
            }
            .padding(contentPadding)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
        .toolbar {
            if showsNavigationControls {
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
        }
        .modifier(DayNavigationGestureModifier(isEnabled: allowsDayNavigation, shiftDay: shiftDay(_:)))
        .sheet(item: $editingChapter) { chapter in
            ChapterEditSheet(chapter: chapter)
        }
        .sheet(item: $editingPlan) { plan in
            PlanCreateSheet(plan: plan)
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsImportant)
        }
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            if allowsDayNavigation {
                Button {
                    shiftDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(headerTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 7) {
                    DayHeaderPill(systemImage: "star.fill", text: "重要 \(importantPlans.count)", tint: Color.yellow)
                    DayHeaderPill(systemImage: "calendar.badge.clock", text: "予定 \(timedPlans.count)", tint: Color.accentColor)
                    DayHeaderPill(systemImage: "stopwatch.fill", text: compactRemainingDuration(scoreSummary.recordedDuration), tint: headerAccentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if allowsDayNavigation {
                Button {
                    shiftDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: headerAccentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(headerAccentColor.opacity(0.14), lineWidth: 1)
        )
    }

    private var planningDeadlineCard: some View {
        let coverage = planningCoverage
        let tint = coverage.hasActionableGap ? Color.orange : Color.green
        return HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption.weight(.bold))
            Text("残り \(planningDeadlineText)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Spacer(minLength: 10)
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(coverage.hasActionableGap ? "空きあり" : "見通しあり")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .accessibilityLabel("明日の予定づくりの残り時間")
            .accessibilityValue("\(planningDeadlineText)、\(coverage.hasActionableGap ? "空きあり" : "見通しあり")")
    }

    private var scoreArea: some View {
        let summary = scoreSummary
        return DayScoreCard(
            summary: summary,
            scoreText: scoreText(summary),
            color: scoreColor(summary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スコア \(scoreText(summary)) \(summary.gradeText)")
    }

    private var importantPlanArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 24, height: 24)
                    .background(Color.yellow.opacity(0.14), in: Circle())
                Text("重要な予定")
                    .font(.headline)
                Spacer()
                if !importantPlans.isEmpty {
                    Text("\(importantPlans.count)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
    }

    private var importantPlans: [PlanBlock] {
        plannedBlocks(on: date)
            .filter { $0.isAllDay || $0.isImportant }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private var timedPlans: [PlanBlock] {
        plannedBlocks(on: date).filter { !$0.isAllDay }
    }

    private var dayChapters: [Chapter] {
        chapters(on: date)
    }

    private var scoreSummary: ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: plannedBlocks(on: date),
            chapters: dayChapters,
            calendar: .japanese,
            now: clock.now
        )
    }

    private var daySummaryText: String {
        "重要 \(importantPlans.count)件 / 時間つき予定 \(timedPlans.count)件"
    }

    private var headerAccentColor: Color {
        importantPlans.first?.category?.color ?? scoreColor(scoreSummary)
    }

    private var headerTitle: String {
        date.japaneseMonthDayWeekday
    }

    private var planningCoverage: PlanCoverageSummary {
        PlanCoverageSummary.make(date: date, plans: plannedBlocks(on: date))
    }

    private var planningDeadlineText: String {
        let deadline = DayBoundary.dayStart(for: date, calendar: .japanese)
        let remaining = deadline.timeIntervalSince(clock.now)
        guard remaining > 0 else { return "調整中" }
        return compactRemainingDuration(remaining)
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
        let visibleDayChapters = dayChapters
        let allPublic = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy(\.isPublic)
        let allPrivate = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy { !$0.isPublic }
        let isMixed = !visibleDayChapters.isEmpty && !allPublic && !allPrivate

        return Menu {
            if visibleDayChapters.isEmpty {
                Text("この日にチャプターはありません")
            } else {
                if isMixed {
                    Text("公開/非公開が混在しています")
                        .font(.caption)
                }
                Button {
                    store.setChaptersVisibility(visibleDayChapters, isPublic: true)
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    store.setChaptersVisibility(visibleDayChapters, isPublic: false)
                } label: {
                    Label("すべて非公開", systemImage: "eye.slash")
                }
                .disabled(allPrivate)

                Divider()
                Text("\(visibleDayChapters.count)件のチャプター")
                    .font(.caption)
            }
        } label: {
            Image(systemName: allPrivate ? "eye.slash" : (isMixed ? "eye.fill" : "eye"))
                .foregroundStyle(isMixed ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("この日の公開設定")
        .disabled(visibleDayChapters.isEmpty)
    }

    private func plannedBlocks(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return queriedPlans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.startTime < rhs.startTime
            }
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return queriedChapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clock.now) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
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

    private func compactRemainingDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return remainingHours > 0 ? "\(days)日\(remainingHours)時間" : "\(days)日"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)時間\(minutes)分"
        }
        if hours > 0 {
            return "\(hours)時間"
        }
        return "\(minutes)分"
    }
}

private struct DayNavigationGestureModifier: ViewModifier {
    let isEnabled: Bool
    let shiftDay: (Int) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            shiftDay(1)
                        } else if value.translation.width > 50 {
                            shiftDay(-1)
                        }
                    }
            )
        } else {
            content
        }
    }
}

private struct DayHeaderPill: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct DayScoreCard: View {
    let summary: ScoreSummary
    let scoreText: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DayScoreRing(score: summary.totalScore, hasScore: summary.plannedDuration > 0, color: color)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .frame(width: 22, height: 22)
                        .background(color.opacity(0.14), in: Circle())

                    Text("予定との重なり")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(summary.gradeText)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 8) {
                    DayScoreMetric(title: "予定", value: compactDuration(summary.plannedDuration), tint: Color.accentColor)
                    DayScoreMetric(title: "一致", value: compactDuration(summary.matchedDuration), tint: color)
                    DayScoreMetric(title: "実績", value: compactDuration(summary.recordedDuration), tint: Color(hex: "#6C5CE7"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(summary.plannedDuration > 0 ? 0.28 : 0.12), lineWidth: 1)
        )
    }

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h\(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

private struct DayScoreRing: View {
    let score: Double
    let hasScore: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemGroupedBackground), lineWidth: 10)

            Circle()
                .trim(from: 0, to: hasScore ? min(max(score / 100, 0), 1) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(hasScore ? "\(Int(score.rounded()))" : "--")
                    .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("pt")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .shadow(color: color.opacity(hasScore ? 0.2 : 0), radius: 10, y: 4)
    }
}

private struct DayScoreMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

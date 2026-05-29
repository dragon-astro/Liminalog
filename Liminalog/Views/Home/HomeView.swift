import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @Query private var queriedPlans: [PlanBlock]
    @State private var selectedPage: TodayPage = .today
    @State private var editingChapter: Chapter? = nil
    @State private var showingAddSheet = false
    @State private var addSheetStart = Date()

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedPage) {
                YesterdayReviewPage(date: relativeDate(-1))
                    .tag(TodayPage.yesterday)

                TodayRecordPage(
                    editingChapter: $editingChapter
                )
                .tag(TodayPage.today)

                TomorrowPlanPage(date: relativeDate(1))
                    .tag(TodayPage.tomorrow)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedPage == .today {
                        Button {
                            addSheetStart = defaultAddStart
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    } else {
                        Color.clear
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                }
                ToolbarItem(placement: .principal) {
                    TodayPageTextTabs(
                        selection: $selectedPage,
                        showsTomorrowIndicator: tomorrowCoverage.hasActionableGap
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: CategorySettingsView()) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $editingChapter) { chapter in
                ChapterEditSheet(chapter: chapter)
            }
            .sheet(isPresented: $showingAddSheet) {
                ChapterCreateSheet(initialDate: addSheetStart)
            }
            .onAppear {
                selectedPage = .today
                store.seedDefaultCategorySetsIfNeeded()
                store.syncLiveActivityWithActiveChapter()
            }
        }
    }

    private var defaultAddStart: Date {
        let now = Date()
        return Calendar.japanese.date(byAdding: .minute, value: -30, to: now) ?? now
    }

    private func relativeDate(_ dayOffset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var tomorrowCoverage: PlanCoverageSummary {
        PlanCoverageSummary.make(date: relativeDate(1), plans: queriedPlans)
    }
}

private enum TodayPage: String, CaseIterable, Identifiable {
    case yesterday
    case today
    case tomorrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yesterday: "昨日"
        case .today: "今日"
        case .tomorrow: "明日"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .yesterday: "昨日の振り返り"
        case .today: "今日の記録"
        case .tomorrow: "明日の予定"
        }
    }
}

private struct TodayPageTextTabs: View {
    @Binding var selection: TodayPage
    let showsTomorrowIndicator: Bool
    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 28) {
            ForEach(TodayPage.allCases) { page in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selection = page
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Text(page.title)
                                .font(.headline.weight(selection == page ? .bold : .semibold))
                                .foregroundStyle(selection == page ? Color.primary : Color.secondary.opacity(0.68))
                                .lineLimit(1)

                            if page == .tomorrow, showsTomorrowIndicator {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 8, y: -1)
                                    .accessibilityHidden(true)
                            }
                        }

                        ZStack {
                            Capsule()
                                .fill(Color.clear)
                                .frame(width: 22, height: 3)
                            if selection == page {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "today-page-underline", in: underlineNamespace)
                                    .frame(width: 22, height: 3)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityAddTraits(selection == page ? .isSelected : [])
            }
        }
        .frame(maxWidth: 220)
    }
}

private struct TodayRecordPage: View {
    @Binding var editingChapter: Chapter?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CurrentChapterCard()
                // CategoryGrid 内のチェブロンで折りたたみを行う。
                CategoryGrid()
                Divider()
                TimelineView(
                    date: Date(),
                    title: "",
                    editingChapter: $editingChapter
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

private struct TomorrowPlanPage: View {
    let date: Date

    var body: some View {
        CalendarDayView(
            date: date,
            showsNavigationControls: false,
            allowsDayNavigation: false,
            contentPadding: 16,
            showsPlanningStatus: true
        )
    }
}

private struct YesterdayReviewPage: View {
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @State private var clock = TickClock(interval: 60)

    let date: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                YesterdayScoreCard(summary: scoreSummary)
                YesterdayInsightCard(
                    summary: scoreSummary,
                    chapterCount: dayChapters.count,
                    topCategoryName: topCategory?.category.name
                )
                YesterdaySummaryStrip(
                    chapterCount: dayChapters.count,
                    recordedDuration: recordedDuration,
                    publicCount: dayChapters.filter(\.isPublic).count
                )
                YesterdayCategoryBreakdown(rows: categoryRows)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
    }

    private var dayBoundary: DayBoundary {
        DayBoundary(date: date, calendar: .japanese)
    }

    private var dayPlans: [PlanBlock] {
        queriedPlans
            .filter { $0.startTime < dayBoundary.dayEnd && $0.endTime > dayBoundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var dayChapters: [Chapter] {
        queriedChapters
            .filter { $0.startTime < dayBoundary.dayEnd && ($0.endTime ?? clock.now) > dayBoundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var scoreSummary: ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: dayPlans,
            chapters: dayChapters,
            calendar: .japanese,
            now: clock.now
        )
    }

    private var recordedDuration: TimeInterval {
        dayChapters.reduce(0) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? clock.now, dayBoundary.dayEnd)
            return partial + max(end.timeIntervalSince(start), 0)
        }
    }

    private var categoryRows: [(category: Category, duration: TimeInterval)] {
        let grouped = Dictionary(grouping: dayChapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? clock.now, dayBoundary.dayEnd)
            return (category, max(end.timeIntervalSince(start), 0))
        }, by: { $0.0.id })

        return grouped.compactMap { _, values in
            guard let category = values.first?.0 else { return nil }
            return (category, values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.duration > $1.duration }
    }

    private var topCategory: (category: Category, duration: TimeInterval)? {
        categoryRows.first
    }
}

private struct YesterdayScoreCard: View {
    let summary: ScoreSummary

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("昨日のスコア", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary.gradeText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(scoreColor)
            }

            Spacer(minLength: 12)

            Text(scoreText)
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundStyle(scoreColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(scoreColor.opacity(summary.plannedDuration > 0 ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(scoreColor.opacity(summary.plannedDuration > 0 ? 0.22 : 0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var scoreText: String {
        summary.plannedDuration > 0 ? "\(Int(summary.totalScore.rounded()))" : "-"
    }

    private var scoreColor: Color {
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
}

private struct YesterdayInsightCard: View {
    let summary: ScoreSummary
    let chapterCount: Int
    let topCategoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("インサイト", systemImage: "sparkles")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var message: String {
        if chapterCount == 0 {
            return "昨日の記録はまだありません。今日の記録が積み重なると、ここで1日を受け取れるようになります。"
        }

        if summary.plannedDuration == 0 {
            if let topCategoryName {
                return "昨日は\(topCategoryName)の時間が一番長い日でした。明日の予定を先に置いておくと、スコアでも振り返れます。"
            }
            return "昨日は記録があります。予定がない日はスコアではなく、カテゴリの偏りを中心に振り返ります。"
        }

        if summary.totalScore >= 75 {
            return "昨日は予定とのズレが少なく、かなり整った1日でした。今日も同じリズムを少しだけ再現できると強いです。"
        }

        if let topCategoryName {
            return "昨日は\(topCategoryName)に時間が寄っています。予定との差分を見て、今日は1つだけ整えるとよさそうです。"
        }

        return "昨日は予定と実績に少しズレがありました。ズレた理由を一言だけ覚えておくと、明日の予定が組みやすくなります。"
    }
}

private struct YesterdaySummaryStrip: View {
    let chapterCount: Int
    let recordedDuration: TimeInterval
    let publicCount: Int

    var body: some View {
        HStack(spacing: 10) {
            ReviewMetricTile(title: "記録", value: "\(chapterCount)")
            ReviewMetricTile(title: "合計", value: friendlyDuration(recordedDuration))
            ReviewMetricTile(title: "公開", value: "\(publicCount)")
        }
    }
}

private struct ReviewMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct YesterdayCategoryBreakdown: View {
    let rows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("カテゴリ別")
                    .font(.headline)
                Spacer()
                Text(rows.isEmpty ? "0件" : "\(rows.count)件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text("記録が入ると、昨日どこに時間を使ったかがここに出ます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(rows.prefix(5), id: \.category.id) { row in
                    YesterdayCategoryRow(row: row, maxDuration: maxDuration)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var maxDuration: TimeInterval {
        max(rows.map(\.duration).max() ?? 1, 1)
    }
}

private struct YesterdayCategoryRow: View {
    let row: (category: Category, duration: TimeInterval)
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: row.category.icon ?? "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(row.category.color)
                    .frame(width: 18)
                Text(row.category.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(friendlyDuration(row.duration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(row.category.color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(row.category.color)
                            .frame(width: proxy.size.width * progress)
                    }
            }
            .frame(height: 7)
        }
    }

    private var progress: Double {
        min(max(row.duration / maxDuration, 0), 1)
    }
}

private func friendlyDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(Int(seconds / 60), 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0, minutes > 0 {
        return "\(hours)時間\(minutes)分"
    } else if hours > 0 {
        return "\(hours)時間"
    } else {
        return "\(minutes)分"
    }
}

#Preview("Home") {
    HomeView()
        .liminalogPreviewEnvironment()
}

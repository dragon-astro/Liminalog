import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPage: TodayPage = .today
    @State private var scrolledPage: TodayPage? = .today
    @State private var editingChapter: Chapter? = nil
    @State private var showingAddSheet = false
    @State private var addSheetStart = Date()
    @State private var clock = TickClock(interval: 60)
    @State private var tomorrowHasActionableGap = false

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                // 表示中のページだけ生成・@Query購読させる。データ変更時の save カスケードで
                // 昨日/明日の重いページまで再描画されるのを防ぐ（表示中ページのみ再描画）。
                LazyHStack(spacing: 0) {
                    ForEach(TodayPage.allCases) { page in
                        dayPage(page)
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledPage, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .onChange(of: scrolledPage) { _, newValue in
                if let newValue, newValue != selectedPage {
                    selectedPage = newValue
                }
            }
            .onChange(of: selectedPage) { _, newValue in
                if scrolledPage != newValue {
                    scrolledPage = newValue
                }
                refreshTomorrowCoverage()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedPage == .today {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            addSheetStart = defaultAddStart
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    TodayPageTextTabs(
                        selection: $selectedPage,
                        showsTomorrowIndicator: tomorrowHasActionableGap
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
                clock.start()
                selectedPage = .today
                scrolledPage = .today
                store.seedDefaultCategorySetsIfNeeded()
                store.syncLiveActivityWithActiveChapter()
                refreshTomorrowCoverage()
            }
            .onDisappear {
                clock.stop()
            }
        }
    }

    @ViewBuilder
    private func dayPage(_ page: TodayPage) -> some View {
        switch page {
        case .yesterday:
            YesterdayReviewPage(date: yesterdayDate)
                .id(dayID(for: yesterdayDate))
        case .today:
            TodayRecordPage(date: todayDate, editingChapter: $editingChapter)
                .id(dayID(for: todayDate))
        case .tomorrow:
            TomorrowPlanPage(date: tomorrowDate)
                .id(dayID(for: tomorrowDate))
        }
    }

    private var defaultAddStart: Date {
        let now = clock.now
        return Calendar.japanese.date(byAdding: .minute, value: -30, to: now) ?? now
    }

    private var todayDate: Date {
        dayID(for: clock.now)
    }

    private var yesterdayDate: Date {
        relativeDate(-1)
    }

    private var tomorrowDate: Date {
        relativeDate(1)
    }

    private func relativeDate(_ dayOffset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: dayOffset, to: todayDate) ?? todayDate
    }

    private func dayID(for date: Date) -> Date {
        DayBoundary.dayStart(for: date, calendar: .japanese)
    }

    private func refreshTomorrowCoverage() {
        let boundary = DayBoundary(date: tomorrowDate, calendar: .japanese)
        let plans = ScoreSnapshotLoader.plannedBlocks(
            in: DateInterval(start: boundary.dayStart, end: boundary.dayEnd),
            modelContext: modelContext
        )
        tomorrowHasActionableGap = PlanCoverageSummary.make(date: tomorrowDate, plans: plans).hasActionableGap
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
    let date: Date
    @Binding var editingChapter: Chapter?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CurrentChapterCard()
                // CategoryGrid 内のチェブロンで折りたたみを行う。
                CategoryGrid()
                Divider()
                TimelineView(
                    date: date,
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

    let date: Date

    init(date: Date) {
        self.date = date
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
            VStack(spacing: 14) {
                YesterdayScoreCard(
                    date: date,
                    summary: scoreSummary,
                    chapters: dayChapters,
                    dayBoundary: dayBoundary,
                    topCategory: topCategory
                )
                YesterdaySummaryStrip(
                    chapterCount: dayChapters.count,
                    recordedDuration: recordedDuration,
                    publicCount: dayChapters.filter(\.isPublic).count,
                    topCategory: topCategory?.category
                )
                YesterdayCategoryBreakdown(rows: categoryRows)
                YesterdayInsightCard(
                    summary: scoreSummary,
                    chapterCount: dayChapters.count,
                    topCategoryName: topCategory?.category.name
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
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
        let now = Date()
        return queriedChapters
            .filter { $0.startTime < dayBoundary.dayEnd && ($0.endTime ?? now) > dayBoundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var scoreSummary: ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: dayPlans,
            chapters: dayChapters,
            calendar: .japanese,
            now: Date()
        )
    }

    private var recordedDuration: TimeInterval {
        let now = Date()
        return dayChapters.reduce(0) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
            return partial + max(end.timeIntervalSince(start), 0)
        }
    }

    private var categoryRows: [(category: Category, duration: TimeInterval)] {
        let now = Date()
        let grouped = Dictionary(grouping: dayChapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
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
    let date: Date
    let summary: ScoreSummary
    let chapters: [Chapter]
    let dayBoundary: DayBoundary
    let topCategory: (category: Category, duration: TimeInterval)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ReviewScoreRing(score: summary.totalScore, hasScore: summary.plannedDuration > 0, color: scoreColor)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreColor)
                            .frame(width: 22, height: 22)
                            .background(scoreColor.opacity(0.14), in: Circle())

                        Text(date.japaneseMonthDayWeekday)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(summary.gradeText)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }

            YesterdayChapterRibbon(
                chapters: chapters,
                dayBoundary: dayBoundary,
                fallbackColor: scoreColor
            )
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .bottom) {
                    ReviewRhythmStrip(color: scoreColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor)
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(16)
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scoreColor.opacity(summary.plannedDuration > 0 ? 0.22 : 0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var scoreColor: Color {
        reviewScoreColor(summary)
    }

    private var heroSubtitle: String {
        if summary.plannedDuration == 0 {
            if let topCategory {
                return "\(topCategory.category.name)が一番長い昨日でした"
            }
            return "予定がある日ほど振り返りが育ちます"
        }
        if let topCategory {
            return "\(topCategory.category.name)を中心に過ごした1日"
        }
        return "予定と実績の重なりを振り返ります"
    }
}

private struct ReviewScoreRing: View {
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
                Text(hasScore ? "\(Int(score.rounded()))" : "-")
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                Text("pt")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .shadow(color: color.opacity(hasScore ? 0.2 : 0), radius: 10, y: 4)
    }
}

private struct YesterdayChapterRibbon: View {
    let chapters: [Chapter]
    let dayBoundary: DayBoundary
    let fallbackColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))

                    ForEach(chapters) { chapter in
                        if let segment = segment(for: chapter, width: width) {
                            Rectangle()
                                .fill(chapter.category?.color ?? fallbackColor)
                                .frame(width: max(segment.width, 2), height: 18)
                                .offset(x: segment.x)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 18)

            HStack {
                Text("0")
                Spacer()
                Text("12")
                Spacer()
                Text("24")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("昨日の24時間リズム")
    }

    private func segment(for chapter: Chapter, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
        let start = max(chapter.startTime, dayBoundary.dayStart)
        guard end > start else { return nil }
        let total = dayBoundary.dayEnd.timeIntervalSince(dayBoundary.dayStart)
        guard total > 0 else { return nil }
        let x = width * CGFloat(start.timeIntervalSince(dayBoundary.dayStart) / total)
        let segmentWidth = width * CGFloat(end.timeIntervalSince(start) / total)
        return (max(0, x), max(0, segmentWidth))
    }
}

private struct ReviewRhythmStrip: View {
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            color.opacity(0.35)
                .frame(width: 46)
            Color.clear
                .frame(width: 18)
            color.opacity(0.18)
                .frame(width: 72)
            Color.clear
                .frame(width: 28)
            color.opacity(0.28)
                .frame(width: 40)
            Color.clear
            color.opacity(0.22)
                .frame(width: 84)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.85)
    }
}

private struct YesterdayInsightCard: View {
    let summary: ScoreSummary
    let chapterCount: Int
    let topCategoryName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                Text("インサイト")
                    .font(.headline)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
    let topCategory: Category?

    var body: some View {
        HStack(spacing: 10) {
            ReviewMetricTile(title: "記録", value: "\(chapterCount)", systemImage: "list.bullet.clipboard.fill", tint: Color(hex: "#6C5CE7"))
            ReviewMetricTile(title: "合計", value: friendlyDuration(recordedDuration), systemImage: "clock.fill", tint: Color.accentColor)
            ReviewMetricTile(title: "公開", value: "\(publicCount)", systemImage: "eye.fill", tint: topCategory?.color ?? Color(hex: "#27AE60"))
        }
    }
}

private struct ReviewMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())

            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct YesterdayCategoryBreakdown: View {
    let rows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    Text("カテゴリ別")
                        .font(.headline)
                }
                Spacer()
                Text(rows.isEmpty ? "0件" : "\(rows.count)件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text("記録が入ると、どこに時間を使ったかがここに出ます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(rows.prefix(5), id: \.category.id) { row in
                    YesterdayCategoryRow(row: row, totalDuration: totalDuration)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var totalDuration: TimeInterval {
        max(rows.reduce(0) { $0 + $1.duration }, 1)
    }
}

private struct YesterdayCategoryRow: View {
    let row: (category: Category, duration: TimeInterval)
    let totalDuration: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
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
                Text("\(Int((share * 100).rounded()))%")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(row.category.color)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(row.category.color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(row.category.color)
                            .frame(width: proxy.size.width * share)
                    }
            }
            .frame(height: 6)
        }
    }

    private var share: Double {
        min(max(row.duration / totalDuration, 0), 1)
    }
}

private func reviewScoreColor(_ summary: ScoreSummary) -> Color {
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

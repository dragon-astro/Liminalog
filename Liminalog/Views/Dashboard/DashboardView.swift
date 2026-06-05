import SwiftUI
import SwiftData

struct DashboardView: View {
    @State private var period: DashboardPeriod = .week
    @State private var anchorDate = Date()
    @State private var isShowingPeriodPicker = false
    @State private var isShowingCustomizeSheet = false
    @State private var clock = TickClock(interval: 60)

    var body: some View {
        // Today と同じ構造: 各期間ページが NavigationStack { ScrollView } を直下に持ち、
        // 期間タブはシステムナビバー(principal)へ。ZStack のグラデ backdrop でバー裏の白を消す。
        ZStack {
            LiminalTheme.canvasGradient.ignoresSafeArea()

            TabView(selection: $period) {
                ForEach(DashboardPeriod.allCases) { item in
                    NavigationStack {
                        DashboardPeriodContent(
                            period: item,
                            anchorDate: anchorDate,
                            clockNow: clock.now,
                            onPickDate: { isShowingPeriodPicker = true }
                        )
                        .background(LiminalTheme.canvasGradient)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { dashboardToolbar }
                    }
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
        .sheet(isPresented: $isShowingPeriodPicker) {
            DashboardPeriodSelectionSheet(period: period, anchorDate: $anchorDate)
        }
        .sheet(isPresented: $isShowingCustomizeSheet) {
            DashboardCustomizeSheet(period: period)
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            DashboardPeriodTextTabs(period: $period)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingCustomizeSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("カードを編集")
        }
    }
}

struct DashboardPeriodContent: View {
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]

    let period: DashboardPeriod
    let anchorDate: Date
    let clockNow: Date
    let onPickDate: () -> Void
    private let interval: DateInterval

    init(period: DashboardPeriod, anchorDate: Date, clockNow: Date, onPickDate: @escaping () -> Void) {
        self.period = period
        self.anchorDate = anchorDate
        self.clockNow = clockNow
        self.onPickDate = onPickDate

        let interval = period.dateInterval(containing: anchorDate, calendar: .japanese)
        self.interval = interval
        let previousInterval = period.previousDateInterval(before: interval, calendar: .japanese)
        let queryStart = min(previousInterval.start, interval.start)
        let chapterLookbackStart = Calendar.japanese.date(byAdding: .day, value: -14, to: queryStart) ?? queryStart
        let intervalEnd = interval.end
        _queriedChapters = Query(
            filter: #Predicate<Chapter> {
                $0.startTime >= chapterLookbackStart && $0.startTime < intervalEnd
            },
            sort: [SortDescriptor(\.startTime)]
        )
        _queriedPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < intervalEnd && $0.endTime > queryStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    var body: some View {
        let snapshot = DashboardPeriodSnapshot(
            period: period,
            interval: interval,
            clockNow: clockNow,
            queriedChapters: queriedChapters,
            queriedPlans: queriedPlans
        )

        ScrollView {
            VStack(spacing: 14) {
                ForEach(cardKeys) { key in
                    cardView(for: key, snapshot: snapshot)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        // 日付セレクタはナビバー直下に固定（スクロールしても流れない）。
        // ScrollView 自体は NavigationStack 直下のままなのでバー橋渡しは維持。
        .safeAreaInset(edge: .top, spacing: 0) {
            DashboardDateChip(
                title: period.displayRange(at: anchorDate, calendar: .japanese),
                onTap: onPickDate
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var cardKeys: [DashboardCardKey] {
        DashboardCardKey.visibleDisplayOrder(
            from: settingsList.first?.dashboardCardOrder ?? [],
            hiddenKeys: settingsList.first?.dashboardHiddenCardKeys ?? [],
            for: period
        )
    }

    @ViewBuilder
    private func cardView(for key: DashboardCardKey, snapshot: DashboardPeriodSnapshot) -> some View {
        switch key {
        case .hero:
            DashboardHeroCard(
                period: period,
                anchorDate: anchorDate,
                summary: snapshot.periodSummary,
                scoreSummaries: snapshot.periodScoreSummaries,
                totalDuration: snapshot.totalDuration,
                recordedDayCount: snapshot.recordedDayCount,
                topCategory: snapshot.topCategoryStat
            )
        case .metrics:
            DashboardMetricRow(
                totalDuration: snapshot.totalDuration,
                chapterCount: snapshot.chapters.count,
                recordedDayCount: snapshot.recordedDayCount
            )
        case .scoreBreakdown:
            ScoreBreakdownCard(summary: snapshot.periodSummary)
        case .periodDelta:
            DashboardPeriodDeltaCard(summary: snapshot.periodDeltaSummary)
        case .categoryShare:
            CategoryShareCard(chapters: snapshot.chapters)
        case .hourRhythm:
            HourRhythmCard(chapters: snapshot.chapters)
        case .scoreTrend:
            ScoreTrendCard(period: period, summaries: snapshot.periodScoreSummaries)
        case .recentTrend:
            RecentTrendCard(chapters: snapshot.recentChapters)
        }
    }
}

private struct DashboardPeriodSnapshot {
    let chapters: [Chapter]
    let periodScoreSummaries: [ScoreSummary]
    let periodSummary: DashboardScoreAggregate
    let totalDuration: TimeInterval
    let recordedDayCount: Int
    let topCategoryStat: DashboardCategoryStat?
    let recentChapters: [Chapter]
    let periodDeltaSummary: DashboardPeriodDeltaSummary

    init(
        period: DashboardPeriod,
        interval: DateInterval,
        clockNow: Date,
        queriedChapters: [Chapter],
        queriedPlans: [PlanBlock]
    ) {
        let chapters = queriedChapters
            .filter { $0.startTime < interval.end && ($0.endTime ?? clockNow) > interval.start }
            .sorted { $0.startTime < $1.startTime }
        self.chapters = chapters

        let calendar = Calendar.japanese
        let summaries = StatsEngine.dailyScoreSummaries(
            in: interval,
            chapters: chapters,
            plans: queriedPlans,
            now: clockNow,
            calendar: calendar
        )
        let previousInterval = period.previousDateInterval(before: interval, calendar: calendar)
        let previousChapters = queriedChapters
            .filter { $0.startTime < previousInterval.end && ($0.endTime ?? clockNow) > previousInterval.start }
            .sorted { $0.startTime < $1.startTime }
        let previousSummaries = StatsEngine.dailyScoreSummaries(
            in: previousInterval,
            chapters: previousChapters,
            plans: queriedPlans,
            now: clockNow,
            calendar: calendar
        )

        self.periodScoreSummaries = summaries
        self.periodSummary = DashboardScoreAggregate(summaries: summaries)
        self.totalDuration = chapters.reduce(0) { $0 + max(0, ($1.endTime ?? clockNow).timeIntervalSince($1.startTime)) }
        self.recordedDayCount = Set(chapters.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        self.topCategoryStat = DashboardCategoryStat.stats(from: chapters, now: clockNow).first
        self.recentChapters = Array(chapters.sorted { $0.startTime > $1.startTime }.prefix(30))
        self.periodDeltaSummary = StatsEngine.periodDeltaSummary(
            currentSummaries: summaries,
            previousSummaries: previousSummaries
        )
    }
}

private struct DashboardPeriodTextTabs: View {
    @Binding var period: DashboardPeriod
    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 24) {
            ForEach(DashboardPeriod.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        period = item
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(item.title)
                            .font(.headline.weight(period == item ? .bold : .semibold))
                            .foregroundStyle(period == item ? LiminalTheme.text : LiminalTheme.secondaryText.opacity(0.68))
                            .lineLimit(1)

                        ZStack {
                            Capsule()
                                .fill(Color.clear)
                                .frame(width: 22, height: 3)
                            if period == item {
                                Capsule()
                                    .fill(LiminalTheme.accent)
                                    .matchedGeometryEffect(id: "dashboard-period-underline", in: underlineNamespace)
                                    .frame(width: 22, height: 3)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(period == item ? .isSelected : [])
            }
        }
        .frame(maxWidth: 240)
    }
}

private struct DashboardDateChip: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(LiminalTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(LiminalTheme.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct DashboardPeriodSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let period: DashboardPeriod
    @Binding var anchorDate: Date
    @State private var selectedDate: Date
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private let calendar = Calendar.japanese

    init(period: DashboardPeriod, anchorDate: Binding<Date>) {
        let date = anchorDate.wrappedValue
        let calendar = Calendar.japanese
        self.period = period
        self._anchorDate = anchorDate
        self._selectedDate = State(initialValue: date)
        self._selectedYear = State(initialValue: calendar.component(.year, from: date))
        self._selectedMonth = State(initialValue: calendar.component(.month, from: date))
    }

    var body: some View {
        NavigationStack {
            pickerContent
                .padding(.horizontal, 12)
                .navigationTitle(pickerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            applySelection()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.height(300)])
    }

    @ViewBuilder
    private var pickerContent: some View {
        switch period {
        case .today, .week:
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        case .month:
            HStack(spacing: 0) {
                yearPicker
                monthPicker
            }
        case .year:
            yearPicker
        }
    }

    private var yearPicker: some View {
        Picker("年", selection: $selectedYear) {
            ForEach(Array(yearRange), id: \.self) { year in
                Text(verbatim: "\(year)年").tag(year)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private var monthPicker: some View {
        Picker("月", selection: $selectedMonth) {
            ForEach(1...12, id: \.self) { month in
                Text("\(month)月").tag(month)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 5)...(currentYear + 1)
    }

    private var pickerTitle: String {
        switch period {
        case .today:
            "日付を選択"
        case .week:
            "週を選択"
        case .month:
            "年月を選択"
        case .year:
            "年を選択"
        }
    }

    private func applySelection() {
        switch period {
        case .today, .week:
            anchorDate = calendar.startOfDay(for: selectedDate)
        case .month:
            anchorDate = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? anchorDate
        case .year:
            anchorDate = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? anchorDate
        }
    }
}

#Preview("Dashboard") {
    DashboardView()
        .liminalogPreviewEnvironment()
}

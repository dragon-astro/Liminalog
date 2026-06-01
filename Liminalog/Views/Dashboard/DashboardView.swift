import SwiftUI
import SwiftData

struct DashboardView: View {
    @State private var period: DashboardPeriod = .week
    @State private var anchorDate = Date()
    @State private var isShowingPeriodPicker = false
    @State private var isShowingCustomizeSheet = false
    @State private var clock = TickClock(interval: 60)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DashboardPeriodPicker(period: $period)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                HStack(spacing: 10) {
                    Button {
                        isShowingPeriodPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(period.displayRange(at: anchorDate, calendar: .japanese))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingCustomizeSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("カードを編集")
                }
                .padding(.bottom, 10)

                TabView(selection: $period) {
                    ForEach(DashboardPeriod.allCases) { item in
                        DashboardPeriodContent(
                            period: item,
                            anchorDate: anchorDate,
                            clockNow: clock.now
                        )
                        .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(LiminalTheme.canvasGradient)
            .toolbar(.hidden, for: .navigationBar)
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
    }
}

struct DashboardPeriodContent: View {
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]

    let period: DashboardPeriod
    let anchorDate: Date
    let clockNow: Date
    private let interval: DateInterval

    init(period: DashboardPeriod, anchorDate: Date, clockNow: Date) {
        self.period = period
        self.anchorDate = anchorDate
        self.clockNow = clockNow

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
            .padding(.bottom, 28)
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
        case .timeOfDayTrend:
            DashboardTimeOfDayTrendCard(summary: snapshot.timeOfDaySummary)
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
    let timeOfDaySummary: DashboardTimeOfDaySummary
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
        self.timeOfDaySummary = StatsEngine.timeOfDaySummary(
            chapters: chapters,
            interval: interval,
            calendar: calendar,
            now: clockNow
        )
        self.periodDeltaSummary = StatsEngine.periodDeltaSummary(
            currentSummaries: summaries,
            previousSummaries: previousSummaries
        )
    }
}

struct DashboardPeriodPicker: View {
    @Binding var period: DashboardPeriod

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DashboardPeriod.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        period = item
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbolName)
                            .font(.caption.weight(.bold))
                        Text(item.title)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(period == item ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if period == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
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

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @State private var period: DashboardPeriod = .today
    @State private var anchorDate = Date()
    @State private var isShowingPeriodPicker = false
    @State private var clock = TickClock(interval: 60)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DashboardPeriodPicker(period: $period)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

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
                .padding(.bottom, 10)

                TabView(selection: $period) {
                    ForEach(DashboardPeriod.allCases) { item in
                        DashboardPeriodContent(
                            period: item,
                            anchorDate: anchorDate,
                            clockNow: clock.now,
                            queriedChapters: queriedChapters,
                            queriedPlans: queriedPlans
                        )
                        .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
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
        }
    }
}

struct DashboardPeriodContent: View {
    let period: DashboardPeriod
    let anchorDate: Date
    let clockNow: Date
    let queriedChapters: [Chapter]
    let queriedPlans: [PlanBlock]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardHeroCard(
                    period: period,
                    anchorDate: anchorDate,
                    summary: periodSummary,
                    scoreSummaries: periodScoreSummaries,
                    totalDuration: totalDuration,
                    recordedDayCount: recordedDayCount,
                    topCategory: topCategoryStat
                )

                DashboardMetricRow(
                    totalDuration: totalDuration,
                    chapterCount: chapters.count,
                    publicCount: chapters.filter(\.isPublic).count,
                    recordedDayCount: recordedDayCount
                )

                ScoreBreakdownCard(summary: periodSummary)
                CategoryShareCard(chapters: chapters)
                HourRhythmCard(chapters: chapters)
                if period != .today {
                    ScoreTrendCard(period: period, summaries: periodScoreSummaries)
                }
                RecentTrendCard(chapters: recentChapters(limit: 30))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var chapters: [Chapter] {
        let interval = period.dateInterval(containing: anchorDate, calendar: .japanese)
        return queriedChapters
            .filter { $0.startTime < interval.end && ($0.endTime ?? clockNow) > interval.start }
            .sorted { $0.startTime < $1.startTime }
    }

    private var periodDates: [Date] {
        let calendar = Calendar.japanese
        let interval = period.dateInterval(containing: anchorDate, calendar: calendar)
        var dates: [Date] = []
        var cursor = DayBoundary.dayStart(for: interval.start, calendar: calendar)
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private var periodScoreSummaries: [ScoreSummary] {
        periodDates.map(scoreSummary(on:))
    }

    private var periodSummary: DashboardScoreAggregate {
        DashboardScoreAggregate(summaries: periodScoreSummaries)
    }

    private var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + max(0, $1.durationLive) }
    }

    private var recordedDayCount: Int {
        Set(chapters.map { DayBoundary.dayStart(for: $0.startTime, calendar: .japanese) }).count
    }

    private var topCategoryStat: DashboardCategoryStat? {
        DashboardCategoryStat.stats(from: chapters).first
    }

    private func plans(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return queriedPlans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return queriedChapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clockNow) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: plans(on: date),
            chapters: chapters(on: date),
            now: clockNow
        )
    }

    private func recentChapters(limit: Int) -> [Chapter] {
        Array(queriedChapters.sorted { $0.startTime > $1.startTime }.prefix(limit))
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

struct DashboardHeroCard: View {
    let period: DashboardPeriod
    let anchorDate: Date
    let summary: DashboardScoreAggregate
    let scoreSummaries: [ScoreSummary]
    let totalDuration: TimeInterval
    let recordedDayCount: Int
    let topCategory: DashboardCategoryStat?

    private var score: Double {
        summary.totalScore
    }

    private var scoreColor: Color {
        DashboardScorePalette.color(for: score, hasScore: summary.hasScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                DashboardScoreRing(score: score, hasScore: summary.hasScore, color: scoreColor)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: period.symbolName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreColor)
                            .frame(width: 22, height: 22)
                            .background(scoreColor.opacity(0.14), in: Circle())

                        Text(period.displayRange(at: anchorDate, calendar: .japanese))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(summary.gradeText)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }

            if period == .today {
                Color.clear
                    .frame(height: 42)
                    .accessibilityHidden(true)
            } else {
                DashboardMiniSparkline(summaries: scoreSummaries, color: scoreColor)
                    .frame(height: 42)
            }

            HStack(spacing: 10) {
                DashboardHeroPill(title: "記録時間", value: formatDashboardDuration(totalDuration), tint: Color.accentColor)
                DashboardHeroPill(title: "記録日", value: "\(recordedDayCount)日", tint: Color(hex: "#27AE60"))
                DashboardHeroPill(title: "主役", value: topCategory?.name ?? "-", tint: topCategory?.color ?? Color.secondary)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .bottom) {
                    DashboardRhythmStrip(color: scoreColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor)
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(16)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scoreColor.opacity(summary.hasScore ? 0.38 : 0.14), lineWidth: 1)
        }
    }

    private var heroSubtitle: String {
        if !summary.hasScore {
            return period == .today ? "今日の予定を組むとスコアが育ちます" : "予定がある日のスコアを集計します"
        }
        if let topCategory {
            return "\(topCategory.name)が一番長い期間です"
        }
        return "記録が増えるほど傾向が見えてきます"
    }
}

struct DashboardScoreRing: View {
    let score: Double
    let hasScore: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemGroupedBackground), lineWidth: 12)

            Circle()
                .trim(from: 0, to: hasScore ? min(max(score / 100, 0), 1) : 0)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(hasScore ? "\(Int(score.rounded()))" : "-")
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                Text("pt")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .shadow(color: color.opacity(hasScore ? 0.22 : 0), radius: 12, y: 5)
        .accessibilityLabel("スコア")
        .accessibilityValue(hasScore ? "\(Int(score.rounded()))点" : "未計算")
    }
}

struct DashboardMiniSparkline: View {
    let summaries: [ScoreSummary]
    let color: Color

    private var plottedScores: [Double] {
        summaries.map { $0.plannedDuration > 0 ? $0.totalScore : 0 }
    }

    var body: some View {
        GeometryReader { proxy in
            let values = plottedScores
            let step = values.count > 1 ? proxy.size.width / CGFloat(values.count - 1) : proxy.size.width
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: max(2, min(7, step * 0.16))) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(value > 0 ? color.opacity(0.82) : Color(.tertiarySystemGroupedBackground))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(5, proxy.size.height * CGFloat(value / 100)))
                    }
                }

                Rectangle()
                    .fill(Color(.separator).opacity(0.16))
                    .frame(height: 1)
                    .offset(y: -proxy.size.height * 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct DashboardHeroPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DashboardRhythmStrip: View {
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            color.opacity(0.35)
                .frame(width: 48)
            Color.clear
                .frame(width: 18)
            color.opacity(0.18)
                .frame(width: 88)
            Color.clear
                .frame(width: 24)
            color.opacity(0.28)
                .frame(width: 44)
            Color.clear
            color.opacity(0.22)
                .frame(width: 96)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.9)
    }
}

struct DashboardMetricRow: View {
    let totalDuration: TimeInterval
    let chapterCount: Int
    let publicCount: Int
    let recordedDayCount: Int

    var body: some View {
        HStack(spacing: 10) {
            DashboardMetricTile(title: "合計", value: formatDashboardDuration(totalDuration), systemImage: "clock.fill", tint: Color.accentColor)
            DashboardMetricTile(title: "記録", value: "\(chapterCount)", systemImage: "list.bullet.clipboard.fill", tint: Color(hex: "#6C5CE7"))
            DashboardMetricTile(title: "公開", value: "\(publicCount)", systemImage: "eye.fill", tint: Color(hex: "#27AE60"))
            DashboardMetricTile(title: "日数", value: "\(recordedDayCount)", systemImage: "calendar.badge.checkmark", tint: Color(hex: "#F2994A"))
        }
    }
}

struct DashboardMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct ScoreBreakdownCard: View {
    let summary: DashboardScoreAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "スコア内訳", systemImage: "target", tint: Color.accentColor)

            if !summary.hasScore {
                EmptyStatText(text: "予定と実績がそろうと内訳が見えます")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardScoreFactorRow(
                        title: "カテゴリ",
                        score: summary.categoryScore,
                        weight: ScoreCalculator.categoryWeight,
                        color: Color(hex: "#2F80ED")
                    )
                    DashboardScoreFactorRow(
                        title: "時間軸",
                        score: summary.timelineScore,
                        weight: ScoreCalculator.timelineWeight,
                        color: Color(hex: "#6C5CE7")
                    )

                    HStack(spacing: 10) {
                        DashboardSmallValue(title: "予定", value: formatDashboardDuration(summary.plannedDuration))
                        DashboardSmallValue(title: "実績", value: formatDashboardDuration(summary.recordedDuration))
                        DashboardSmallValue(title: "一致", value: formatDashboardDuration(summary.matchedDuration))
                    }

                    Text(summary.scoreFormulaText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .dashboardCard()
    }
}

struct DashboardScoreFactorRow: View {
    let title: String
    let score: Double
    let weight: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                DashboardContributionLegend(title: title, color: color)
                Text("配点 \(Int((weight * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(score.rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(max(score / 100, 0), 1))
                    }
            }
            .frame(height: 9)
        }
    }
}

struct DashboardContributionLegend: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardProgressRow: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(Int(value.rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                    }
            }
            .frame(height: 8)
        }
    }
}

struct DashboardSmallValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case today, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "日間"
        case .week: "週間"
        case .month: "月間"
        case .year: "年間"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max.fill"
        case .week: "calendar.badge.clock"
        case .month: "calendar"
        case .year: "calendar.circle.fill"
        }
    }

    func dateInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            let start = DayBoundary.dayStart(for: date, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
            return DateInterval(start: start, end: end)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? {
                let start = DayBoundary.dayStart(for: date, calendar: calendar)
                let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
                return DateInterval(start: start, end: end)
            }()
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
            return DateInterval(start: start, end: end)
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? date
            return DateInterval(start: start, end: end)
        }
    }

    func displayRange(at date: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .today:
            return date.japaneseMonthDayWeekday
        case .week:
            let interval = dateInterval(containing: date, calendar: calendar)
            let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let year = calendar.component(.year, from: interval.start)
            let startMonth = calendar.component(.month, from: interval.start)
            let startDay = calendar.component(.day, from: interval.start)
            let endMonth = calendar.component(.month, from: inclusiveEnd)
            let endDay = calendar.component(.day, from: inclusiveEnd)
            return "\(year) \(startMonth)/\(startDay)-\(endMonth)/\(endDay)"
        case .month:
            return date.japaneseYearMonth
        case .year:
            return date.japaneseYear
        }
    }
}

struct CategoryShareCard: View {
    let chapters: [Chapter]

    private var rows: [DashboardCategoryStat] {
        DashboardCategoryStat.stats(from: chapters)
    }

    private var total: TimeInterval {
        max(rows.reduce(0) { $0 + $1.duration }, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "カテゴリ構成", systemImage: "square.grid.2x2.fill", tint: Color(hex: "#6C5CE7"))

            if rows.isEmpty {
                EmptyStatText(text: "記録を始めるとカテゴリの比率が見えます")
            } else {
                DashboardStackedCategoryBar(rows: Array(rows.prefix(5)), total: total)

                VStack(spacing: 10) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                        DashboardCategoryRow(rank: index + 1, stat: row, total: total)
                    }
                }
            }
        }
        .dashboardCard()
    }
}

struct DashboardStackedCategoryBar: View {
    let rows: [DashboardCategoryStat]
    let total: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(rows) { row in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(row.color)
                        .frame(width: max(4, proxy.size.width * row.duration / total))
                }
                if rows.isEmpty {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct DashboardCategoryRow: View {
    let rank: Int
    let stat: DashboardCategoryStat
    let total: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(stat.color)
                .frame(width: 22, height: 22)
                .background(stat.color.opacity(0.12), in: Circle())

            Label {
                Text(stat.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: stat.icon)
                    .foregroundStyle(stat.color)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(formatDashboardDuration(stat.duration))
                    .font(.caption.weight(.bold).monospacedDigit())
                Text("\(Int((stat.duration / total * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HourRhythmCard: View {
    let chapters: [Chapter]

    private var hourlyStats: [HourStat] {
        (0..<24).map { hour in
            let matches = chapters.filter { Calendar.current.component(.hour, from: $0.startTime) == hour }
            let duration = matches.reduce(0) { $0 + max(0, $1.durationLive) }
            let category = Dictionary(grouping: matches.compactMap(\.category), by: \.id)
                .max { $0.value.count < $1.value.count }?
                .value.first
            return HourStat(hour: hour, duration: duration, category: category)
        }
    }

    private var maxDuration: TimeInterval {
        max(hourlyStats.map(\.duration).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "24時間リズム", systemImage: "waveform.path.ecg", tint: Color(hex: "#00A8A8"))

            if chapters.isEmpty {
                EmptyStatText(text: "時間帯ごとのリズムがここに育ちます")
            } else {
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(hourlyStats) { stat in
                            Capsule()
                                .fill(stat.category?.color ?? Color(.tertiarySystemGroupedBackground))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(7, 48 * stat.duration / maxDuration))
                                .opacity(stat.duration > 0 ? 1 : 0.5)
                        }
                    }
                    .frame(height: 52, alignment: .bottom)

                    HStack {
                        Text("0")
                        Spacer()
                        Text("6")
                        Spacer()
                        Text("12")
                        Spacer()
                        Text("18")
                        Spacer()
                        Text("24")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .dashboardCard()
    }
}

struct ScoreTrendCard: View {
    let period: DashboardPeriod
    let summaries: [ScoreSummary]

    private var displaySummaries: [ScoreSummary] {
        switch period {
        case .year:
            let sampleStep = max(Int(ceil(Double(summaries.count) / 24.0)), 1)
            var sampledSummaries: [ScoreSummary] = []
            var index = 0
            while index < summaries.count {
                sampledSummaries.append(summaries[index])
                index += sampleStep
            }
            return sampledSummaries
        default:
            return summaries
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "スコアの流れ", systemImage: "chart.bar.xaxis", tint: Color(hex: "#F2994A"))

            if summaries.allSatisfy({ $0.plannedDuration <= 0 }) {
                EmptyStatText(text: "予定がある日のスコア推移が表示されます")
            } else {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(displaySummaries, id: \.date) { summary in
                        let hasScore = summary.plannedDuration > 0
                        Capsule()
                            .fill(DashboardScorePalette.color(for: summary.totalScore, hasScore: hasScore))
                            .frame(maxWidth: .infinity)
                            .frame(height: hasScore ? max(8, CGFloat(summary.totalScore / 100) * 86) : 8)
                            .opacity(hasScore ? 0.92 : 0.42)
                    }
                }
                .frame(height: 90, alignment: .bottom)

                HStack {
                    Text(displaySummaries.first?.date.japaneseMonthDay ?? "")
                    Spacer()
                    Text(displaySummaries.last?.date.japaneseMonthDay ?? "")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }
}

struct RecentTrendCard: View {
    let chapters: [Chapter]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "最近の記録", systemImage: "clock.arrow.circlepath", tint: Color(hex: "#EB5757"))

            if chapters.isEmpty {
                EmptyStatText(text: "記録を始めると最近の流れが見えます")
            } else {
                VStack(spacing: 12) {
                    ForEach(chapters.prefix(6)) { chapter in
                        HStack(spacing: 10) {
                            Image(systemName: chapter.category?.icon ?? "circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(chapter.category?.color ?? Color.secondary)
                                .frame(width: 28, height: 28)
                                .background((chapter.category?.color ?? Color.secondary).opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.category?.name ?? "未分類")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(chapter.startTime.japaneseShortDateTime)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(formatDashboardDuration(chapter.durationLive))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .dashboardCard()
    }
}

struct DashboardSectionHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())

            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

struct EmptyStatText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

extension View {
    func dashboardCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

struct DashboardScoreAggregate {
    let totalScore: Double
    let categoryScore: Double
    let timelineScore: Double
    let plannedDuration: TimeInterval
    let recordedDuration: TimeInterval
    let matchedDuration: TimeInterval
    let scoredDayCount: Int

    init(summaries: [ScoreSummary]) {
        let scored = summaries.filter { $0.plannedDuration > 0 }
        scoredDayCount = scored.count
        if scored.isEmpty {
            totalScore = 0
            categoryScore = 0
            timelineScore = 0
        } else {
            totalScore = scored.map(\.totalScore).reduce(0, +) / Double(scored.count)
            categoryScore = scored.map(\.categoryScore).reduce(0, +) / Double(scored.count)
            timelineScore = scored.map(\.timelineScore).reduce(0, +) / Double(scored.count)
        }
        plannedDuration = summaries.reduce(0) { $0 + $1.plannedDuration }
        recordedDuration = summaries.reduce(0) { $0 + $1.recordedDuration }
        matchedDuration = summaries.reduce(0) { $0 + $1.matchedDuration }
    }

    var hasScore: Bool {
        scoredDayCount > 0
    }

    var gradeText: String {
        guard hasScore else { return "これから育つ" }
        switch totalScore {
        case 90...:
            return "かなり予定通り"
        case 75..<90:
            return "いい感じ"
        case 60..<75:
            return "合格ライン"
        default:
            return "伸びしろあり"
        }
    }

    var scoreFormulaText: String {
        let categoryWeight = Int((ScoreCalculator.categoryWeight * 100).rounded())
        let timelineWeight = Int((ScoreCalculator.timelineWeight * 100).rounded())
        return "計算式: カテゴリ\(Int(categoryScore.rounded()))%×\(categoryWeight)% + 時間軸\(Int(timelineScore.rounded()))%×\(timelineWeight)% = \(Int(totalScore.rounded()))pt"
    }
}

struct DashboardCategoryStat: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let color: Color
    let duration: TimeInterval

    static func stats(from chapters: [Chapter]) -> [DashboardCategoryStat] {
        let grouped = Dictionary(grouping: chapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            return (category, max(0, chapter.durationLive))
        }, by: { $0.0.id })

        return grouped.compactMap { id, values in
            guard let category = values.first?.0 else { return nil }
            return DashboardCategoryStat(
                id: id,
                name: category.name,
                icon: category.icon ?? "circle.fill",
                color: category.color,
                duration: values.reduce(0) { $0 + $1.1 }
            )
        }
        .sorted { $0.duration > $1.duration }
    }
}

struct HourStat: Identifiable {
    let hour: Int
    let duration: TimeInterval
    let category: Category?

    var id: Int { hour }
}

enum DashboardScorePalette {
    static func color(for score: Double, hasScore: Bool) -> Color {
        guard hasScore else { return Color.secondary }
        switch score {
        case 90...: return Color(hex: "#27AE60")
        case 75..<90: return Color(hex: "#2F80ED")
        case 60..<75: return Color(hex: "#F2994A")
        default: return Color(hex: "#EB5757")
        }
    }
}

private func formatDashboardDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes < 60 {
        return "\(minutes)分"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
}

#Preview("Dashboard") {
    DashboardView()
        .liminalogPreviewEnvironment()
}

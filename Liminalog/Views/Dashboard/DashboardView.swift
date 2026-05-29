import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @State private var period: DashboardPeriod = .today
    @State private var clock = TickClock(interval: 60)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("期間", selection: $period) {
                    ForEach(DashboardPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        DashboardPeriodHeader(period: period)
                        if period == .today {
                            TodayScoreDashboardCard(summary: scoreSummary(on: clock.now))
                        }
                        SummaryStrip(chapters: chapters)
                        CategoryShareCard(chapters: chapters)
                        HourHeatmapCard(chapters: chapters)
                        RecentTrendCard(chapters: recentChapters(limit: 30))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                clock.start()
            }
            .onDisappear {
                clock.stop()
            }
        }
    }

    private var chapters: [Chapter] {
        let interval = period.dateInterval(containing: clock.now)
        return queriedChapters
            .filter { $0.startTime < interval.end && ($0.endTime ?? clock.now) > interval.start }
            .sorted { $0.startTime < $1.startTime }
    }

    private func plans(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        return queriedPlans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date)
        return queriedChapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clock.now) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: plans(on: date),
            chapters: chapters(on: date),
            now: clock.now
        )
    }

    private func recentChapters(limit: Int) -> [Chapter] {
        Array(queriedChapters.sorted { $0.startTime > $1.startTime }.prefix(limit))
    }
}

struct TodayScoreDashboardCard: View {
    let summary: ScoreSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("予定達成スコア")
                        .font(.headline)
                    Text("カテゴリ合計 80% + 時間軸一致 20%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(summary.totalScore.rounded()))")
                    .font(.system(size: 36, weight: .black, design: .rounded).monospacedDigit())
                Text("pt")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                SummaryTile(title: "カテゴリ", value: "\(Int(summary.categoryScore.rounded()))%")
                SummaryTile(title: "時間軸", value: "\(Int(summary.timelineScore.rounded()))%")
                SummaryTile(title: "一致時間", value: formatDuration(summary.matchedDuration))
            }
        }
        .statCard()
    }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case today, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "今日"
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

    var displayRange: String {
        displayRange(at: Date())
    }

    func dateInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            let start = DayBoundary.dayStart(for: date, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
            return DateInterval(start: start, end: end)
        case .week:
            let todayStart = DayBoundary.dayStart(for: date, calendar: calendar)
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? date
            return DateInterval(start: start, end: end)
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
            return "\(interval.start.japaneseMonthDay) 〜 \(date.japaneseMonthDay)"
        case .month:
            return date.japaneseYearMonth
        case .year:
            return date.japaneseYear
        }
    }
}

struct DashboardPeriodHeader: View {
    let period: DashboardPeriod

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.title)
                    .font(.headline)
                Text(period.displayRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: period.symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct SummaryStrip: View {
    let chapters: [Chapter]

    private var total: TimeInterval {
        chapters.reduce(0) { $0 + $1.durationLive }
    }

    var body: some View {
        HStack(spacing: 10) {
            SummaryTile(title: "記録", value: "\(chapters.count)")
            SummaryTile(title: "合計", value: formatDuration(total))
            SummaryTile(title: "公開", value: "\(chapters.filter(\.isPublic).count)")
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct CategoryShareCard: View {
    let chapters: [Chapter]

    private var rows: [(Category, TimeInterval)] {
        let grouped = Dictionary(grouping: chapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            return (category, chapter.durationLive)
        }, by: { $0.0.id })

        return grouped.compactMap { _, values in
            guard let category = values.first?.0 else { return nil }
            return (category, values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.1 > $1.1 }
    }

    private var total: TimeInterval {
        max(rows.reduce(0) { $0 + $1.1 }, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別")
                .font(.headline)

            if rows.isEmpty {
                EmptyStatText()
            } else {
                ForEach(rows, id: \.0.id) { category, duration in
                    VStack(spacing: 6) {
                        HStack {
                            Label(category.name, systemImage: category.icon ?? "circle.fill")
                                .foregroundStyle(category.color)
                            Spacer()
                            Text(formatDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(category.color)
                                        .frame(width: proxy.size.width * duration / total)
                                }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .statCard()
    }
}

struct HourHeatmapCard: View {
    let chapters: [Chapter]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24時間ヒートマップ")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<24, id: \.self) { hour in
                    let category = dominantCategory(at: hour)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(category?.color ?? Color(.tertiarySystemGroupedBackground))
                            .frame(height: 28)
                        Text("\(hour)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .statCard()
    }

    private func dominantCategory(at hour: Int) -> Category? {
        let matches = chapters.filter { Calendar.current.component(.hour, from: $0.startTime) == hour }
        return Dictionary(grouping: matches.compactMap(\.category), by: \.id)
            .max { $0.value.count < $1.value.count }?
            .value.first
    }
}

struct RecentTrendCard: View {
    let chapters: [Chapter]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近の記録")
                .font(.headline)

            if chapters.isEmpty {
                EmptyStatText()
            } else {
                ForEach(chapters.prefix(6)) { chapter in
                    HStack {
                        Circle()
                            .fill(chapter.category?.color ?? Color(.systemGray3))
                            .frame(width: 10, height: 10)
                        Text(chapter.category?.name ?? "未分類")
                        Spacer()
                        Text(chapter.startTime.japaneseShortDateTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .statCard()
    }
}

struct EmptyStatText: View {
    var body: some View {
        Text("記録を始めるとここに反映されます")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func statCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

#Preview("Dashboard") {
    DashboardView()
        .liminalogPreviewEnvironment()
}

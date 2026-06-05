import SwiftUI

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
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Text(summary.gradeText)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(LiminalTheme.secondaryText)
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
                    .frame(height: 56)
            }

            HStack(spacing: 10) {
                DashboardHeroPill(
                    title: "記録時間",
                    value: formatDashboardDuration(totalDuration),
                    countUpValue: totalDuration,
                    countUpFormatter: formatDashboardDuration,
                    tint: LiminalTheme.accent
                )
                DashboardHeroPill(
                    title: "記録日",
                    value: "\(recordedDayCount)日",
                    countUpValue: Double(recordedDayCount),
                    countUpFormatter: { "\(Int($0.rounded()))日" },
                    tint: Color(hex: "#27AE60")
                )
                DashboardHeroPill(title: "主役", value: topCategory?.name ?? "-", tint: topCategory?.color ?? LiminalTheme.secondaryText)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: scoreColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor)
                        .frame(width: 24, height: 24)
                        .liminalGlassFill(in: Circle())
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
                .stroke(LiminalTheme.elevated, lineWidth: 12)

            Circle()
                .trim(from: 0, to: hasScore ? min(max(score / 100, 0), 1) : 0)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(hasScore ? "\(Int(score.rounded()))" : "-")
                    .dashboardCountUp(value: score, isEnabled: hasScore, placeholder: "-") {
                        "\(Int($0.rounded()))"
                    }
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                Text("pt")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
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

    private var scoredSummaries: [ScoreSummary] {
        summaries.filter { $0.plannedDuration > 0 }
    }

    var body: some View {
        ScoreTrendBarChart(summaries: scoredSummaries, colorOverride: color)
        .accessibilityHidden(true)
    }
}

struct DashboardHeroPill: View {
    let title: String
    let value: String
    var countUpValue: Double? = nil
    var countUpFormatter: ((Double) -> String)? = nil
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(LiminalTheme.secondaryText)
            Text(value)
                .dashboardCountUpIfNeeded(value: countUpValue, formatter: countUpFormatter)
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

struct DashboardMetricRow: View {
    let totalDuration: TimeInterval
    let chapterCount: Int
    let recordedDayCount: Int

    var body: some View {
        HStack(spacing: 10) {
            DashboardMetricTile(
                title: "実績",
                value: formatDashboardDuration(totalDuration),
                countUpValue: totalDuration,
                countUpFormatter: formatDashboardDuration,
                systemImage: "clock.fill",
                tint: LiminalTheme.accent
            )
            DashboardMetricTile(
                title: "件数",
                value: "\(chapterCount)",
                countUpValue: Double(chapterCount),
                countUpFormatter: { "\(Int($0.rounded()))" },
                systemImage: "list.bullet.clipboard.fill",
                tint: Color(hex: "#6C5CE7")
            )
            DashboardMetricTile(
                title: "日数",
                value: "\(recordedDayCount)",
                countUpValue: Double(recordedDayCount),
                countUpFormatter: { "\(Int($0.rounded()))" },
                systemImage: "calendar.badge.checkmark",
                tint: Color(hex: "#F2994A")
            )
        }
    }
}

struct DashboardMetricTile: View {
    let title: String
    let value: String
    var countUpValue: Double? = nil
    var countUpFormatter: ((Double) -> String)? = nil
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
                    .dashboardCountUpIfNeeded(value: countUpValue, formatter: countUpFormatter)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
        )
    }
}

struct ScoreBreakdownCard: View {
    let summary: DashboardScoreAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "スコア内訳", systemImage: "target", tint: LiminalTheme.accent)

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
                        DashboardSmallValue(
                            title: "予定",
                            value: formatDashboardDuration(summary.plannedDuration),
                            countUpValue: summary.plannedDuration,
                            countUpFormatter: formatDashboardDuration
                        )
                        DashboardSmallValue(
                            title: "実績",
                            value: formatDashboardDuration(summary.recordedDuration),
                            countUpValue: summary.recordedDuration,
                            countUpFormatter: formatDashboardDuration
                        )
                        DashboardSmallValue(
                            title: "一致",
                            value: formatDashboardDuration(summary.matchedDuration),
                            countUpValue: summary.matchedDuration,
                            countUpFormatter: formatDashboardDuration
                        )
                    }

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

    private var achievedPt: Int { Int((score * weight).rounded()) }
    private var maxPt: Int { Int((weight * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                DashboardContributionLegend(title: title, color: color)
                Spacer()
                Text("\(achievedPt) / \(maxPt) pt")
                    .dashboardCountUp(value: Double(achievedPt)) {
                        "\(Int($0.rounded())) / \(maxPt) pt"
                    }
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(LiminalTheme.elevated)
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
                .foregroundStyle(LiminalTheme.secondaryText)
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
                    .dashboardCountUp(value: value) {
                        "\(Int($0.rounded()))%"
                    }
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(LiminalTheme.elevated)
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
    var countUpValue: Double? = nil
    var countUpFormatter: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)
            Text(value)
                .dashboardCountUpIfNeeded(value: countUpValue, formatter: countUpFormatter)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case today, week, month, year
    static let allCases: [DashboardPeriod] = [.week, .month, .year]

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

    func previousDateInterval(before interval: DateInterval, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            let start = calendar.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
            return DateInterval(start: start, end: interval.start)
        case .week:
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start) ?? interval.start
            return DateInterval(start: start, end: interval.start)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
            return DateInterval(start: start, end: interval.start)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: interval.start) ?? interval.start
            return DateInterval(start: start, end: interval.start)
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
            DashboardSectionHeader(title: "カテゴリ別トータル", systemImage: "square.grid.2x2.fill", tint: Color(hex: "#6C5CE7"))

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
                        .fill(LiminalTheme.elevated)
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

    private var share: Double {
        total > 0 ? stat.duration / total : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                        .dashboardCountUp(value: stat.duration, formatter: formatDashboardDuration)
                        .font(.caption.weight(.bold).monospacedDigit())
                    Text("\(Int((share * 100).rounded()))%")
                        .dashboardCountUp(value: share * 100) {
                            "\(Int($0.rounded()))%"
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(LiminalTheme.elevated)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(stat.color)
                            .frame(width: proxy.size.width * min(max(share, 0), 1))
                    }
            }
            .frame(height: 8)
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
            DashboardSectionHeader(title: "24時間リズム", systemImage: "chart.bar.fill", tint: Color(hex: "#00A8A8"))

            if chapters.isEmpty {
                EmptyStatText(text: "時間帯ごとのリズムがここに育ちます")
            } else {
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(hourlyStats) { stat in
                            Capsule()
                                .fill(stat.category?.displayColor ?? LiminalTheme.elevated)
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
                    .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
        .dashboardCard()
    }
}

struct ScoreTrendCard: View {
    let period: DashboardPeriod
    let summaries: [ScoreSummary]

    private var scoredDisplaySummaries: [ScoreSummary] {
        let scored = summaries.filter { $0.plannedDuration > 0 }
        switch period {
        case .year:
            let sampleStep = max(Int(ceil(Double(scored.count) / 24.0)), 1)
            var sampledSummaries: [ScoreSummary] = []
            var index = 0
            while index < scored.count {
                sampledSummaries.append(scored[index])
                index += sampleStep
            }
            return sampledSummaries
        default:
            return scored
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "スコアの流れ", systemImage: "chart.bar.xaxis", tint: Color(hex: "#F2994A"))

            if scoredDisplaySummaries.isEmpty {
                EmptyStatText(text: "予定がある日のスコア推移が表示されます")
            } else {
                ScoreTrendBarChart(summaries: scoredDisplaySummaries)
                    .frame(height: 96)

                HStack {
                    Text(scoredDisplaySummaries.first?.date.japaneseMonthDay ?? "")
                    Spacer()
                    Text(scoredDisplaySummaries.last?.date.japaneseMonthDay ?? "")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .dashboardCard()
    }
}

private struct ScoreTrendBarChart: View {
    let summaries: [ScoreSummary]
    var colorOverride: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            let guideScores = guideScores
            let bars = barFrames(in: proxy.size)
            ZStack {
                ForEach(Array(guideScores.enumerated()), id: \.offset) { index, score in
                    let y = yPosition(for: score, in: proxy.size)
                    Rectangle()
                        .fill(index == 1 ? LiminalTheme.divider.opacity(0.34) : LiminalTheme.divider.opacity(0.48))
                        .frame(height: index == 1 ? 0.8 : 1)
                        .position(x: proxy.size.width / 2, y: y)
                }

                ForEach(Array(bars.enumerated()), id: \.offset) { index, frame in
                    let summary = summaries[index]
                    Capsule()
                        .fill(colorOverride ?? DashboardScorePalette.color(for: summary.totalScore, hasScore: true))
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("スコアの流れ")
    }

    private var guideScores: [Double] {
        let scores = summaries.map(\.totalScore)
        guard let minScore = scores.min(), let maxScore = scores.max() else { return [] }
        let midScore = (minScore + maxScore) / 2
        return [maxScore, midScore, minScore]
    }

    private var barWidth: CGFloat {
        8
    }

    private var barDensity: CGFloat {
        0.56
    }

    private func barFrames(in size: CGSize) -> [CGRect] {
        guard !summaries.isEmpty else { return [] }
        let width = min(barWidth, max(size.width / CGFloat(max(summaries.count, 1)) * barDensity, 3))
        let horizontalInset: CGFloat = summaries.count == 1 ? size.width / 2 : max(width / 2, 6)
        let topInset: CGFloat = 8
        let bottomInset: CGFloat = 10
        let usableWidth = max(size.width - horizontalInset * 2, 1)
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let denominator = max(CGFloat(summaries.count - 1), 1)

        return summaries.enumerated().map { index, summary in
            let normalizedScore = min(max(summary.totalScore / 100, 0), 1)
            let x = horizontalInset + usableWidth * CGFloat(index) / denominator
            let height = max(6, usableHeight * CGFloat(normalizedScore))
            let y = topInset + usableHeight - height / 2
            return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
        }
    }

    private func yPosition(for score: Double, in size: CGSize) -> CGFloat {
        let topInset: CGFloat = 8
        let bottomInset: CGFloat = 10
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let normalizedScore = min(max(score / 100, 0), 1)
        return topInset + usableHeight * CGFloat(1 - normalizedScore)
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
                                .foregroundStyle(chapter.category?.displayColor ?? LiminalTheme.secondaryText)
                                .frame(width: 28, height: 28)
                                .background((chapter.category?.displayColor ?? LiminalTheme.secondaryText).opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.category?.name ?? "未分類")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(chapter.startTime.japaneseShortDateTime)
                                    .font(.caption2)
                                    .foregroundStyle(LiminalTheme.secondaryText)
                            }

                            Spacer()

                            Text(formatDashboardDuration(chapter.durationLive))
                                .dashboardCountUp(value: chapter.durationLive, formatter: formatDashboardDuration)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(LiminalTheme.secondaryText)
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
            .foregroundStyle(LiminalTheme.secondaryText)
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
                    .fill(LiminalTheme.surface)
            )
    }
}

import Foundation

enum DashboardCardKey: String, CaseIterable, Identifiable {
    case hero
    case metrics
    case scoreBreakdown
    case timeOfDayTrend
    case periodDelta
    case categoryShare
    case hourRhythm
    case scoreTrend
    case recentTrend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hero:
            return "サマリー"
        case .metrics:
            return "メトリック"
        case .scoreBreakdown:
            return "スコア内訳"
        case .timeOfDayTrend:
            return "時間帯別傾向"
        case .periodDelta:
            return "前期間比"
        case .categoryShare:
            return "カテゴリ別トータル"
        case .hourRhythm:
            return "24時間リズム"
        case .scoreTrend:
            return "スコアの流れ"
        case .recentTrend:
            return "最近の記録"
        }
    }

    var symbolName: String {
        switch self {
        case .hero:
            return "chart.line.uptrend.xyaxis"
        case .metrics:
            return "number"
        case .scoreBreakdown:
            return "target"
        case .timeOfDayTrend:
            return "clock.fill"
        case .periodDelta:
            return "arrow.left.arrow.right"
        case .categoryShare:
            return "square.grid.2x2.fill"
        case .hourRhythm:
            return "chart.bar.fill"
        case .scoreTrend:
            return "chart.bar.xaxis"
        case .recentTrend:
            return "clock.arrow.circlepath"
        }
    }

    static func defaultOrder(for period: DashboardPeriod) -> [DashboardCardKey] {
        switch period {
        case .today:
            return [
                .hero,
                .metrics,
                .scoreBreakdown,
                .categoryShare,
                .hourRhythm,
                .recentTrend
            ]
        case .week:
            return [
                .hero,
                .metrics,
                .scoreBreakdown,
                .timeOfDayTrend,
                .periodDelta,
                .categoryShare,
                .hourRhythm,
                .scoreTrend,
                .recentTrend
            ]
        case .month, .year:
            return [
                .hero,
                .metrics,
                .scoreBreakdown,
                .categoryShare,
                .hourRhythm,
                .scoreTrend,
                .recentTrend
            ]
        }
    }

    static func displayOrder(from storedOrder: [String], for period: DashboardPeriod) -> [DashboardCardKey] {
        let available = defaultOrder(for: period)
        guard !storedOrder.isEmpty else { return available }

        var seen = Set<DashboardCardKey>()
        let stored = storedOrder.compactMap(DashboardCardKey.init(rawValue:)).filter { key in
            guard available.contains(key), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        return stored + available.filter { !seen.contains($0) }
    }

    static func visibleDisplayOrder(
        from storedOrder: [String],
        hiddenKeys: [String],
        for period: DashboardPeriod
    ) -> [DashboardCardKey] {
        let ordered = displayOrder(from: storedOrder, for: period)
        let hidden = Set(hiddenKeys.compactMap(DashboardCardKey.init(rawValue:)))
        return ordered.filter { $0 == .hero || !hidden.contains($0) }
    }
}

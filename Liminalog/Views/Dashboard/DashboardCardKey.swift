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
}

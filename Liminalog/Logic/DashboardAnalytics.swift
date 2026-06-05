import Foundation

struct DashboardDeltaMetric {
    let current: Double
    let previous: Double

    var delta: Double {
        current - previous
    }

    var percentChange: Double? {
        guard previous > 0 else { return nil }
        return delta / previous
    }

    var isIncrease: Bool {
        delta > 0
    }

    var isDecrease: Bool {
        delta < 0
    }
}

struct DashboardPeriodDeltaSummary {
    let score: DashboardDeltaMetric
    let recordedDuration: DashboardDeltaMetric
    let plannedDuration: DashboardDeltaMetric
    let matchedDuration: DashboardDeltaMetric
    let scoredDayCount: DashboardDeltaMetric

    static func make(
        currentSummaries: [ScoreSummary],
        previousSummaries: [ScoreSummary]
    ) -> DashboardPeriodDeltaSummary {
        DashboardPeriodDeltaSummary(
            score: DashboardDeltaMetric(
                current: averageScore(currentSummaries),
                previous: averageScore(previousSummaries)
            ),
            recordedDuration: DashboardDeltaMetric(
                current: currentSummaries.reduce(0) { $0 + $1.recordedDuration },
                previous: previousSummaries.reduce(0) { $0 + $1.recordedDuration }
            ),
            plannedDuration: DashboardDeltaMetric(
                current: currentSummaries.reduce(0) { $0 + $1.plannedDuration },
                previous: previousSummaries.reduce(0) { $0 + $1.plannedDuration }
            ),
            matchedDuration: DashboardDeltaMetric(
                current: currentSummaries.reduce(0) { $0 + $1.matchedDuration },
                previous: previousSummaries.reduce(0) { $0 + $1.matchedDuration }
            ),
            scoredDayCount: DashboardDeltaMetric(
                current: Double(currentSummaries.filter { $0.plannedDuration > 0 }.count),
                previous: Double(previousSummaries.filter { $0.plannedDuration > 0 }.count)
            )
        )
    }

    private static func averageScore(_ summaries: [ScoreSummary]) -> Double {
        let scored = summaries.filter { $0.plannedDuration > 0 }
        guard !scored.isEmpty else { return 0 }
        return scored.reduce(0) { $0 + $1.totalScore } / Double(scored.count)
    }
}

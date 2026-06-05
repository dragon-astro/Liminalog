import Foundation

enum StatsEngine {
    static func dailyCardPattern(
        chapters: [Chapter],
        historyChapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        recordedDuration: TimeInterval,
        dayBoundary: DayBoundary,
        avoidedSpotlightKinds: Set<String> = []
    ) -> DailyCardPatternDetector {
        DailyCardPatternDetector(
            chapters: chapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: dayBoundary,
            avoidedSpotlightKinds: avoidedSpotlightKinds
        )
    }

    static func dailyScoreSummaries(
        in interval: DateInterval,
        chapters: [Chapter],
        plans: [PlanBlock],
        now: Date,
        calendar: Calendar
    ) -> [ScoreSummary] {
        var dates: [Date] = []
        var cursor = DayBoundary.dayStart(for: interval.start, calendar: calendar)
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return dates.map { date in
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            return ScoreCalculator.summary(
                date: date,
                plans: dayPlans,
                chapters: dayChapters,
                calendar: calendar,
                now: now
            )
        }
    }

    static func periodDeltaSummary(
        currentSummaries: [ScoreSummary],
        previousSummaries: [ScoreSummary]
    ) -> DashboardPeriodDeltaSummary {
        DashboardPeriodDeltaSummary.make(
            currentSummaries: currentSummaries,
            previousSummaries: previousSummaries
        )
    }
}

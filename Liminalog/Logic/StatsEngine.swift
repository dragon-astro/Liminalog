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

        let validDayStarts = Set(dates)
        // Preserve the old whole-day clipping even if a caller supplies a partial day.
        let bucketInterval = DateInterval(
            start: dates.first ?? interval.start,
            end: dates.last.map { DayBoundary(date: $0, calendar: calendar).dayEnd } ?? interval.end
        )
        let plansByDay = DayIntervalBuckets.make(
            plans, interval: bucketInterval, calendar: calendar,
            validDayStarts: validDayStarts, start: \.startTime, end: \.endTime
        )
        let chaptersByDay = DayIntervalBuckets.make(
            chapters, interval: bucketInterval, calendar: calendar,
            validDayStarts: validDayStarts, start: \.startTime, end: { $0.endTime ?? now }
        )
        return dates.map { date in
            let dayPlans = plansByDay[date] ?? []
            let dayChapters = chaptersByDay[date] ?? []
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

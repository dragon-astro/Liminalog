import Foundation

enum DashboardTimeOfDay: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning:
            return "朝"
        case .afternoon:
            return "昼"
        case .night:
            return "夜"
        }
    }
}

struct DashboardTimeOfDayRow: Identifiable {
    let segment: DashboardTimeOfDay
    let duration: TimeInterval
    let ratio: Double

    var id: DashboardTimeOfDay { segment }
}

struct DashboardTimeOfDaySummary {
    let rows: [DashboardTimeOfDayRow]
    let totalDuration: TimeInterval

    var dominantSegment: DashboardTimeOfDay? {
        rows.max { $0.duration < $1.duration }?.segment
    }

    static func make(
        chapters: [Chapter],
        interval: DateInterval,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DashboardTimeOfDaySummary {
        var durations = Dictionary(
            uniqueKeysWithValues: DashboardTimeOfDay.allCases.map { ($0, TimeInterval(0)) }
        )

        for chapter in chapters {
            let rawEnd = chapter.endTime ?? now
            let clippedStart = max(chapter.startTime, interval.start)
            let clippedEnd = min(rawEnd, interval.end)
            guard clippedEnd > clippedStart else { continue }

            for bucket in buckets(overlapping: DateInterval(start: clippedStart, end: clippedEnd), calendar: calendar) {
                let overlapStart = max(clippedStart, bucket.interval.start)
                let overlapEnd = min(clippedEnd, bucket.interval.end)
                let duration = max(overlapEnd.timeIntervalSince(overlapStart), 0)
                durations[bucket.segment, default: 0] += duration
            }
        }

        let total = durations.values.reduce(0, +)
        let rows = DashboardTimeOfDay.allCases.map { segment in
            let duration = durations[segment, default: 0]
            return DashboardTimeOfDayRow(
                segment: segment,
                duration: duration,
                ratio: total > 0 ? duration / total : 0
            )
        }

        return DashboardTimeOfDaySummary(rows: rows, totalDuration: total)
    }

    private static func buckets(
        overlapping interval: DateInterval,
        calendar: Calendar
    ) -> [(segment: DashboardTimeOfDay, interval: DateInterval)] {
        var results: [(segment: DashboardTimeOfDay, interval: DateInterval)] = []
        var dayStart = DayBoundary.dayStart(for: interval.start, calendar: calendar)
        while dayStart < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let earlyNightEnd = calendar.date(byAdding: .hour, value: 5, to: dayStart) ?? dayStart
            let morningEnd = calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
            let afternoonEnd = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? dayStart

            results.append((.night, DateInterval(start: dayStart, end: earlyNightEnd)))
            results.append((.morning, DateInterval(start: earlyNightEnd, end: morningEnd)))
            results.append((.afternoon, DateInterval(start: morningEnd, end: afternoonEnd)))
            results.append((.night, DateInterval(start: afternoonEnd, end: nextDay)))

            dayStart = nextDay
        }
        return results.filter { $0.interval.end > interval.start && $0.interval.start < interval.end }
    }
}

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

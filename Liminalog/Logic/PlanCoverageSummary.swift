import Foundation

struct PlanCoverageSummary {
    let dayStart: Date
    let dayEnd: Date
    let plannedDuration: TimeInterval
    let gapDuration: TimeInterval
    let gapCount: Int
    let firstGapStart: Date?
    let firstGapEnd: Date?

    var coverageRatio: Double {
        let total = dayEnd.timeIntervalSince(dayStart)
        guard total > 0 else { return 0 }
        return min(max(plannedDuration / total, 0), 1)
    }

    var hasActionableGap: Bool {
        gapCount > 0
    }

    static func make(
        date: Date,
        plans: [PlanBlock],
        calendar: Calendar = .japanese,
        minimumGapDuration: TimeInterval = 30 * 60
    ) -> PlanCoverageSummary {
        let boundary = DayBoundary(date: date, calendar: calendar)
        let clippedIntervals = plans
            .filter { !$0.isAllDay }
            .compactMap { plan -> DateInterval? in
                let start = max(plan.startTime, boundary.dayStart)
                let end = min(plan.endTime, boundary.dayEnd)
                guard end > start else { return nil }
                return DateInterval(start: start, end: end)
            }
            .sorted { $0.start < $1.start }

        let mergedIntervals = merge(clippedIntervals)
        let plannedDuration = min(
            mergedIntervals.reduce(0) { $0 + $1.duration },
            boundary.dayEnd.timeIntervalSince(boundary.dayStart)
        )

        var cursor = boundary.dayStart
        var gapDuration: TimeInterval = 0
        var gapCount = 0
        var firstGapStart: Date?
        var firstGapEnd: Date?

        for interval in mergedIntervals {
            let gap = interval.start.timeIntervalSince(cursor)
            if gap >= minimumGapDuration {
                gapDuration += gap
                gapCount += 1
                if firstGapStart == nil {
                    firstGapStart = cursor
                    firstGapEnd = interval.start
                }
            }
            cursor = max(cursor, interval.end)
        }

        let tailGap = boundary.dayEnd.timeIntervalSince(cursor)
        if tailGap >= minimumGapDuration {
            gapDuration += tailGap
            gapCount += 1
            if firstGapStart == nil {
                firstGapStart = cursor
                firstGapEnd = boundary.dayEnd
            }
        }

        return PlanCoverageSummary(
            dayStart: boundary.dayStart,
            dayEnd: boundary.dayEnd,
            plannedDuration: plannedDuration,
            gapDuration: gapDuration,
            gapCount: gapCount,
            firstGapStart: firstGapStart,
            firstGapEnd: firstGapEnd
        )
    }

    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        intervals.reduce(into: []) { merged, interval in
            guard let last = merged.last else {
                merged.append(interval)
                return
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
    }
}

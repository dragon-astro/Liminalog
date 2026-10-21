import Foundation

/// Groups each interval into every overlapping day, preserving input order.
enum DayIntervalBuckets {
    static func make<Value>(
        _ values: [Value],
        interval: DateInterval,
        calendar: Calendar,
        validDayStarts: Set<Date>,
        start: (Value) -> Date,
        end: (Value) -> Date
    ) -> [Date: [Value]] {
        var result: [Date: [Value]] = [:]
        for value in values {
            let clippedStart = max(start(value), interval.start)
            let clippedEnd = min(end(value), interval.end)
            guard clippedStart < clippedEnd else { continue }

            var dayStart = DayBoundary.dayStart(for: clippedStart, calendar: calendar)
            while dayStart < clippedEnd {
                if validDayStarts.contains(dayStart) {
                    result[dayStart, default: []].append(value)
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                    break
                }
                dayStart = nextDay
            }
        }
        return result
    }
}

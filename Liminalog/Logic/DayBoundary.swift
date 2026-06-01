import Foundation

struct DayBoundary: Equatable {
    let dayStart: Date
    let dayEnd: Date

    init(date: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        self.dayStart = start
        self.dayEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    init(dayStart: Date) {
        self.dayStart = dayStart
        self.dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)
    }

    static func dayStart(for date: Date, calendar: Calendar = .current) -> Date {
        DayBoundary(date: date, calendar: calendar).dayStart
    }

    static func dayEnd(for date: Date, calendar: Calendar = .current) -> Date {
        DayBoundary(date: date, calendar: calendar).dayEnd
    }

    func overlaps(start: Date, end: Date) -> Bool {
        start < dayEnd && end > dayStart
    }

    func clipped(start: Date, end: Date) -> DateInterval? {
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, dayEnd)
        guard clippedEnd > clippedStart else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }
}

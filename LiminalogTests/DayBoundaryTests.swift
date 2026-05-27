import Foundation
import Testing
@testable import Liminalog

@Suite("DayBoundary")
struct DayBoundaryTests {
    @Test("0:00から翌0:00までを1日として扱う")
    func fixedMidnightBoundary() throws {
        let calendar = Calendar.liminalogTest
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 15)))
        let boundary = DayBoundary(date: date, calendar: calendar)

        #expect(boundary.dayStart == calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 0)))
        #expect(boundary.dayEnd == calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 0)))
    }

    @Test("日付またぎの時間範囲を対象日にクリップする")
    func clipsCrossDayInterval() throws {
        let calendar = Calendar.liminalogTest
        let boundary = DayBoundary(
            date: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))),
            calendar: calendar
        )
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))
        let clipped = try #require(boundary.clipped(start: start, end: end))

        #expect(clipped.start == boundary.dayStart)
        #expect(clipped.end == calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))
    }
}


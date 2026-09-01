import Foundation
import Testing
@testable import Liminalog

struct CalendarJapaneseCacheTests {
    @Test
    func cachedCalendarKeepsConfigurationAndTracksRequestedTimeZone() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let firstUTC = Calendar.japanese(timeZone: utc)
        let secondUTC = Calendar.japanese(timeZone: utc)
        let tokyoCalendar = Calendar.japanese(timeZone: tokyo)

        #expect(firstUTC == secondUTC)
        #expect(firstUTC.identifier == .gregorian)
        #expect(firstUTC.locale?.identifier == "ja_JP")
        #expect(firstUTC.firstWeekday == 1)
        #expect(firstUTC.timeZone == utc)
        #expect(tokyoCalendar.timeZone == tokyo)
    }
}

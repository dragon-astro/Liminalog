import Foundation
import Testing
@testable import Liminalog

@Suite("Calendar plan creation preset")
struct CalendarPlanCreationPresetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    @Test("未来日は対象日の9時から時間指定予定を作る")
    func futureDayUsesNineAMTimedPreset() throws {
        let now = try date(year: 2026, month: 7, day: 18, hour: 14)
        let target = try date(year: 2026, month: 7, day: 21, hour: 17)

        let preset = try #require(CalendarPlanCreationPreset.make(
            for: target,
            canCreateTimedPlan: true,
            now: now,
            calendar: calendar
        ))

        #expect(!preset.startsAsAllDay)
        #expect(calendar.component(.year, from: preset.initialDate) == 2026)
        #expect(calendar.component(.month, from: preset.initialDate) == 7)
        #expect(calendar.component(.day, from: preset.initialDate) == 21)
        #expect(calendar.component(.hour, from: preset.initialDate) == 9)
        #expect(calendar.component(.minute, from: preset.initialDate) == 0)
    }

    @Test("時間指定を作れない今日は対象日の0時から終日予定を作る")
    func todayUsesAllDayPreset() throws {
        let now = try date(year: 2026, month: 7, day: 18, hour: 14)
        let target = try date(year: 2026, month: 7, day: 18, hour: 17)

        let preset = try #require(CalendarPlanCreationPreset.make(
            for: target,
            canCreateTimedPlan: false,
            now: now,
            calendar: calendar
        ))

        #expect(preset.startsAsAllDay)
        #expect(preset.initialDate == calendar.startOfDay(for: target))
    }

    @Test("昨日以前は時間指定可否にかかわらず予定作成を拒否する", arguments: [true, false])
    func pastDayDoesNotCreateFallbackPreset(canCreateTimedPlan: Bool) throws {
        let now = try date(year: 2026, month: 7, day: 18, hour: 0, minute: 5)
        let target = try date(year: 2026, month: 7, day: 17, hour: 23, minute: 59)

        #expect(!CalendarPlanCreationPreset.allowsCreation(
            for: target,
            now: now,
            calendar: calendar
        ))
        #expect(CalendarPlanCreationPreset.make(
            for: target,
            canCreateTimedPlan: canCreateTimedPlan,
            now: now,
            calendar: calendar
        ) == nil)
    }

    @Test("月跨ぎでも選んだ日を維持する")
    func monthBoundaryKeepsTargetDay() throws {
        let now = try date(year: 2026, month: 12, day: 31, hour: 20)
        let target = try date(year: 2027, month: 1, day: 1, hour: 1)

        let preset = try #require(CalendarPlanCreationPreset.make(
            for: target,
            canCreateTimedPlan: true,
            now: now,
            calendar: calendar
        ))

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: preset.initialDate)
        #expect(components.year == 2027)
        #expect(components.month == 1)
        #expect(components.day == 1)
        #expect(components.hour == 9)
        #expect(!preset.startsAsAllDay)
    }

    @Test("同日を時間指定可能として渡した場合は現在時刻を使う")
    func sameDayTimedPresetUsesNow() throws {
        let now = try date(year: 2026, month: 7, day: 18, hour: 14, minute: 35)
        let target = try date(year: 2026, month: 7, day: 18, hour: 9)

        let preset = try #require(CalendarPlanCreationPreset.make(
            for: target,
            canCreateTimedPlan: true,
            now: now,
            calendar: calendar
        ))

        #expect(preset.initialDate == now)
        #expect(!preset.startsAsAllDay)
    }

    @Test("日付境界は端末タイムゾーンの暦日で判定する")
    func timezoneBoundaryUsesLocalCalendarDay() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(losAngeles.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 0, minute: 5
        )))
        let yesterday = try #require(losAngeles.date(from: DateComponents(
            year: 2026, month: 10, day: 31, hour: 23, minute: 59
        )))
        let today = try #require(losAngeles.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 23
        )))

        #expect(!CalendarPlanCreationPreset.allowsCreation(
            for: yesterday,
            now: now,
            calendar: losAngeles
        ))
        #expect(CalendarPlanCreationPreset.allowsCreation(
            for: today,
            now: now,
            calendar: losAngeles
        ))
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}

import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("Monthly ordinal weekday recurrence")
struct PlanMonthlyRecurrenceTests {
    let calendar = Calendar.liminalogTest

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func rule(
        startingAt start: Date,
        ordinals: [PlanRecurrenceRule.MonthlyOrdinal],
        weekday: Int,
        interval: Int = 1,
        limit: Int? = nil
    ) -> PlanRecurrenceRule {
        PlanRecurrenceRule(frequency: .monthly, interval: interval, startDate: start,
            occurrenceLimit: limit, monthlyMode: .ordinalWeekday,
            monthlyOrdinals: ordinals, monthlyWeekday: weekday)
    }

    @Test func oldJSONKeepsDayOfMonthAndSkipsMissingDates() throws {
        let old = "{\"frequency\":\"monthly\",\"interval\":1,\"weekdays\":[],\"startDate\":\(date(2026, 1, 31).timeIntervalSinceReferenceDate),\"occurrenceLimit\":3}"
        let decoded = try #require(PlanRecurrenceRule.decode(Data(old.utf8)))
        #expect(decoded.monthlyMode == .dayOfMonth)
        #expect(decoded.contains(date(2026, 1, 31), calendar: calendar))
        #expect(!decoded.contains(date(2026, 2, 28), calendar: calendar))
        #expect(decoded.contains(date(2026, 3, 31), calendar: calendar))
        #expect(decoded.contains(date(2026, 5, 31), calendar: calendar))
        #expect(!decoded.contains(date(2026, 7, 31), calendar: calendar))
        #expect(decoded.summary(calendar: calendar) == "毎月31日")
    }

    @Test func multipleOrdinalWeekdaysRoundTripAndSummarizeInCalendarOrder() throws {
        let original = rule(startingAt: date(2026, 9, 1), ordinals: [.fourth, .second, .second], weekday: 4)
        let decoded = try #require(PlanRecurrenceRule.decode(original.data))
        #expect(decoded == original)
        #expect(decoded.summary(calendar: calendar) == "毎月 第2・第4水曜")
        #expect([9, 23].allSatisfy { decoded.contains(date(2026, 9, $0), calendar: calendar) })
        #expect([2, 8, 16, 24, 30].allSatisfy { !decoded.contains(date(2026, 9, $0), calendar: calendar) })
        let everyOtherMonth = rule(startingAt: date(2026, 9, 1), ordinals: [.last], weekday: 6, interval: 2)
        #expect(everyOtherMonth.summary(calendar: calendar) == "2か月ごと 最終金曜")
    }

    @Test func lastStaysInsideMonthAndIncludesLeapDay() {
        let leapThursday = rule(startingAt: date(2024, 1, 1), ordinals: [.last], weekday: 5)
        #expect(leapThursday.contains(date(2024, 2, 29), calendar: calendar))
        #expect(!leapThursday.contains(date(2024, 2, 22), calendar: calendar))
        #expect(!leapThursday.contains(date(2024, 3, 7), calendar: calendar))
        #expect(leapThursday.contains(date(2024, 3, 28), calendar: calendar))
        #expect(leapThursday.contains(date(2025, 2, 27), calendar: calendar))
        let lastSunday = rule(startingAt: date(2026, 2, 1), ordinals: [.last], weekday: 1)
        #expect(lastSunday.contains(date(2026, 2, 22), calendar: calendar))
        #expect(!lastSunday.contains(date(2026, 3, 1), calendar: calendar))
        #expect(lastSunday.contains(date(2026, 3, 29), calendar: calendar))
    }

    @Test func fourthAndLastCountOnceWhenTheyShareADate() {
        let fourthAndLast = rule(startingAt: date(2026, 2, 1), ordinals: [.fourth, .last, .fourth], weekday: 1, limit: 3)
        #expect(fourthAndLast.contains(date(2026, 2, 22), calendar: calendar))
        #expect(fourthAndLast.contains(date(2026, 3, 22), calendar: calendar))
        #expect(fourthAndLast.contains(date(2026, 3, 29), calendar: calendar))
        #expect(!fourthAndLast.contains(date(2026, 4, 26), calendar: calendar))
    }

    @Test func countStartsAtFirstMatchingDateAfterStartAndRespectsMonthInterval() {
        let everyMonth = rule(startingAt: date(2026, 9, 10), ordinals: [.second, .fourth], weekday: 4, limit: 3)
        #expect(!everyMonth.contains(date(2026, 9, 9), calendar: calendar))
        #expect(everyMonth.contains(date(2026, 9, 23), calendar: calendar))
        #expect(everyMonth.contains(date(2026, 10, 14), calendar: calendar))
        #expect(everyMonth.contains(date(2026, 10, 28), calendar: calendar))
        #expect(!everyMonth.contains(date(2026, 11, 11), calendar: calendar))
        let everyOtherMonth = rule(startingAt: date(2026, 9, 10), ordinals: [.second, .fourth], weekday: 4, interval: 2, limit: 3)
        #expect(everyOtherMonth.contains(date(2026, 9, 23), calendar: calendar))
        #expect(!everyOtherMonth.contains(date(2026, 10, 14), calendar: calendar))
        #expect(everyOtherMonth.contains(date(2026, 11, 11), calendar: calendar))
        #expect(everyOtherMonth.contains(date(2026, 11, 25), calendar: calendar))
        #expect(!everyOtherMonth.contains(date(2027, 1, 13), calendar: calendar))
    }

    @Test func partialFirstMonthCanHaveNoRemainingOccurrences() {
        let monthly = rule(startingAt: date(2026, 9, 30), ordinals: [.first], weekday: 4, limit: 1)
        #expect(!monthly.contains(date(2026, 9, 2), calendar: calendar))
        #expect(monthly.contains(date(2026, 10, 7), calendar: calendar))
        #expect(!monthly.contains(date(2026, 11, 4), calendar: calendar))
    }

    @Test func exactEndTimeAndInclusiveLegacyEndDayBothApply() {
        var monthly = rule(startingAt: date(2026, 9, 1), ordinals: [.second, .fourth], weekday: 4)
        monthly.endDate = date(2026, 10, 28, hour: 10)
        monthly.endDateIncludesTime = true
        #expect(monthly.allows(startingAt: date(2026, 10, 28, hour: 10), on: date(2026, 10, 28), calendar: calendar))
        #expect(!monthly.allows(startingAt: date(2026, 10, 28, hour: 11), on: date(2026, 10, 28), calendar: calendar))
        #expect(!monthly.contains(date(2026, 11, 11), calendar: calendar))
        monthly.endDateIncludesTime = nil
        #expect(monthly.allows(startingAt: date(2026, 10, 28, hour: 23), on: date(2026, 10, 28), calendar: calendar))
    }

    @Test func weekdayUsesCalendarNotWeekStartAndSurvivesDST() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        losAngeles.firstWeekday = 2
        let start = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        var monthly = rule(startingAt: start, ordinals: [.second, .last], weekday: 1)
        monthly.monthlyWeekday = nil
        #expect(monthly.selectedMonthlyWeekday(calendar: losAngeles) == 1)
        let expected = [8, 29].map { losAngeles.date(from: DateComponents(year: 2026, month: 3, day: $0))! }
        #expect(expected.allSatisfy { monthly.contains($0, calendar: losAngeles) })
        #expect(monthly.summary(calendar: losAngeles) == "毎月 第2・最終日曜")
    }

    @Test func invalidWeekdayEmptySelectionAndUnsupportedFifthAreRejected() throws {
        var monthly = rule(startingAt: date(2026, 9, 1), ordinals: [.first], weekday: 8)
        #expect(!monthly.isValid)
        #expect(PlanRecurrenceRule.decode(monthly.data) == nil)
        monthly.monthlyWeekday = 4
        monthly.monthlyOrdinals = []
        #expect(!monthly.isValid)
        #expect(!monthly.contains(date(2026, 9, 2), calendar: calendar))
        monthly.monthlyOrdinals = [.first]
        let data = try #require(monthly.data)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["monthlyOrdinals"] = [5]
        #expect(PlanRecurrenceRule.decode(try JSONSerialization.data(withJSONObject: json)) == nil)
    }

    @Test func planAndDayPresetsShareDatesAndCountEndingsAcrossMaterializationWindows() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let clock = MutableTestClock(now: date(2026, 9, 1))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let monthly = rule(startingAt: date(2026, 9, 1), ordinals: [.second, .fourth], weekday: 4, limit: 3)
        func item(_ title: String, hour: Int) -> PlanTemplateSnapshot {
            PlanTemplateSnapshot(title: title, categoryID: nil, startMinute: hour * 60, endMinute: (hour + 1) * 60,
                isAllDay: false, isImportant: false, isPublic: false, templateItemID: UUID())
        }
        let planPreset = try #require(presets.createPlanPreset(name: "予定", snapshot: item("予定", hour: 9), recurrence: .some(monthly)))
        let dayPreset = try #require(presets.createDayPreset(name: "一日", items: [item("朝", hour: 10), item("昼", hour: 12)], recurrence: .some(monthly)))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: date(2026, 10, 1)).count == 6)
        #expect(try store.materialize(from: date(2026, 10, 1), to: date(2026, 11, 1)).count == 3)
        #expect(try store.materialize(to: date(2026, 11, 1)).isEmpty)
        let plans = try context.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.startTime)]))
        let expected = [date(2026, 9, 9), date(2026, 9, 23), date(2026, 10, 14)]
        for seriesID in [planPreset.id, dayPreset.id] {
            let seriesPlans = plans.filter { $0.recurrenceSeriesID == seriesID }
            #expect(Set(seriesPlans.map { calendar.startOfDay(for: $0.startTime) }) == Set(expected))
            #expect(seriesPlans.count == (seriesID == planPreset.id ? 3 : 6))
        }
        #expect(!context.hasChanges)
    }
}

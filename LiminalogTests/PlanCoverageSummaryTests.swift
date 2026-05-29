import Foundation
import Testing
@testable import Liminalog

@Suite("PlanCoverageSummary")
struct PlanCoverageSummaryTests {
    @Test("時間つき予定が24時間を埋めると空きなしになる")
    func fullDayTimedPlansHaveNoActionableGap() throws {
        let calendar = Calendar.liminalogTest
        let category = Category(name: "予定", colorHex: "#3B82F6")
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30)))
        let plans = [
            plan(category: category, calendar: calendar, day: day, startHour: 0, endHour: 8),
            plan(category: category, calendar: calendar, day: day, startHour: 8, endHour: 18),
            plan(category: category, calendar: calendar, day: day, startHour: 18, endHour: 24)
        ]

        let summary = PlanCoverageSummary.make(date: day, plans: plans, calendar: calendar)

        #expect(summary.hasActionableGap == false)
        #expect(summary.gapCount == 0)
        #expect(summary.plannedDuration == 24 * 60 * 60)
        #expect(summary.coverageRatio == 1)
    }

    @Test("30分未満の隙間は通知対象にせず大きな隙間だけ数える")
    func ignoresTinyGapsAndReportsFirstActionableGap() throws {
        let calendar = Calendar.liminalogTest
        let category = Category(name: "予定", colorHex: "#3B82F6")
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30)))
        let plans = [
            plan(category: category, calendar: calendar, day: day, startHour: 0, endHour: 8),
            plan(category: category, calendar: calendar, day: day, startHour: 8, startMinute: 10, endHour: 12),
            plan(category: category, calendar: calendar, day: day, startHour: 13, endHour: 24)
        ]

        let summary = PlanCoverageSummary.make(date: day, plans: plans, calendar: calendar)

        #expect(summary.hasActionableGap)
        #expect(summary.gapCount == 1)
        #expect(summary.gapDuration == 60 * 60)
        #expect(summary.firstGapStart == calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 12)))
        #expect(summary.firstGapEnd == calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 13)))
    }

    @Test("終日予定は24時間の入力率には含めない")
    func allDayPlansDoNotCoverTimedSchedule() throws {
        let calendar = Calendar.liminalogTest
        let category = Category(name: "重要", colorHex: "#F97316")
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30)))
        let allDay = PlanBlock(
            category: category,
            title: "遠征",
            startTime: day,
            endTime: try #require(calendar.date(byAdding: .day, value: 1, to: day)),
            isAllDay: true,
            isImportant: true
        )

        let summary = PlanCoverageSummary.make(date: day, plans: [allDay], calendar: calendar)

        #expect(summary.hasActionableGap)
        #expect(summary.gapCount == 1)
        #expect(summary.gapDuration == 24 * 60 * 60)
        #expect(summary.coverageRatio == 0)
    }

    private func plan(
        category: Liminalog.Category,
        calendar: Calendar,
        day: Date,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0
    ) -> PlanBlock {
        let start = calendar.date(
            byAdding: DateComponents(hour: startHour, minute: startMinute),
            to: day
        ) ?? day
        let end = calendar.date(
            byAdding: DateComponents(hour: endHour, minute: endMinute),
            to: day
        ) ?? day
        return PlanBlock(category: category, title: category.name, startTime: start, endTime: end)
    }
}

import Foundation
import Testing
@testable import Liminalog

@Suite("DayPresetApplyPlanner")
struct DayPresetApplyPlannerTests {
    private let calendar = Calendar.liminalogTest

    @Test("一日プリセットは全件追加可能なときだけ丸ごと適用できる")
    func wholeDayApplicationRequiresEveryItem() {
        #expect(!DayPresetApplyPlanner.canApplyWholePreset([]))
        #expect(DayPresetApplyPlanner.canApplyWholePreset([.insertable, .insertable]))
        #expect(!DayPresetApplyPlanner.canApplyWholePreset([.insertable, .lockedDay]))
        #expect(!DayPresetApplyPlanner.canApplyWholePreset([.insertable, .invalidTime]))
        #expect(!DayPresetApplyPlanner.canApplyWholePreset([
            .insertable, .conflictsWithExisting([UUID()])
        ]))
        #expect(!DayPresetApplyPlanner.canApplyWholePreset([
            .insertable, .conflictsWithinPreset([0])
        ]))
    }

    @Test("未来日の空き時間は追加可能")
    func insertableOnFutureDay() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [snapshot(start: 9 * 60, end: 10 * 60)],
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.insertable])
    }

    @Test("今日以前の時間指定だけlockedDayになる")
    func lockedTimedItemButNotAllDay() throws {
        let now = try date(2026, 9, 2, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [
                snapshot(start: 15 * 60, end: 16 * 60),
                snapshot(start: -1, end: -1, isAllDay: true)
            ],
            targetDate: now,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.lockedDay, .insertable])
    }

    @Test(arguments: [
        (-1, 60),
        (60, 60),
        (60, 60 + 24 * 60 + 1),
        (24 * 60, 24 * 60 + 60)
    ] as [(Int, Int)])
    func invalidTimedRanges(start: Int, end: Int) throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [snapshot(start: start, end: end)],
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.invalidTime])
    }

    @Test("隣接する予定は重複しない")
    func adjacentItemsAreInsertable() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [
                snapshot(start: 9 * 60, end: 10 * 60),
                snapshot(start: 10 * 60, end: 11 * 60)
            ],
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.insertable, .insertable])
    }

    @Test("プリセット内重複は相手のindexを返す")
    func conflictsWithinPreset() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [
                snapshot(start: 9 * 60, end: 10 * 60),
                snapshot(start: 9 * 60 + 30, end: 11 * 60),
                snapshot(start: 12 * 60, end: 13 * 60)
            ],
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [
            .conflictsWithinPreset([1]),
            .conflictsWithinPreset([0]),
            .insertable
        ])
    }

    @Test("日跨ぎの翌朝部分もプリセット内重複として扱う")
    func overnightWrapConflictsWithMorning() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [
                snapshot(start: 23 * 60, end: 31 * 60),
                snapshot(start: 6 * 60, end: 8 * 60)
            ],
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [
            .conflictsWithinPreset([1]),
            .conflictsWithinPreset([0])
        ])
    }

    @Test("選択から重複相手を外して再判定すると追加可能になる")
    func replanningSelectedItemsClearsInternalConflict() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        let selected = [snapshot(start: 9 * 60, end: 10 * 60)]

        let verdicts = DayPresetApplyPlanner.plan(
            items: selected,
            targetDate: target,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.insertable])
    }

    @Test("日跨ぎ予定は翌日の既存予定とも重複する")
    func overnightConflictsWithNextDayExistingPlan() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        let existingID = UUID()
        let existing = DayPresetApplyPlanner.ExistingInterval(
            id: existingID,
            start: try date(2026, 9, 4, 6, 30),
            end: try date(2026, 9, 4, 8, 0),
            isAllDay: false
        )

        let verdicts = DayPresetApplyPlanner.plan(
            items: [snapshot(start: 23 * 60, end: 31 * 60)],
            targetDate: target,
            existing: [existing],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.conflictsWithExisting([existingID])])
    }

    @Test("終日予定は既存の時間指定予定と競合しない")
    func allDayDoesNotConflict() throws {
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        let existing = DayPresetApplyPlanner.ExistingInterval(
            id: UUID(),
            start: try date(2026, 9, 3, 9, 0),
            end: try date(2026, 9, 3, 10, 0),
            isAllDay: false
        )

        let verdicts = DayPresetApplyPlanner.plan(
            items: [snapshot(start: 0, end: 0, isAllDay: true)],
            targetDate: target,
            existing: [existing],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.insertable])
    }

    @Test("判定優先順位はinvalidTimeがlockedDayより先")
    func invalidPrecedesLocked() throws {
        let now = try date(2026, 9, 2, 12, 0)

        let verdicts = DayPresetApplyPlanner.plan(
            items: [snapshot(start: 10 * 60, end: 10 * 60)],
            targetDate: now,
            existing: [],
            now: now,
            calendar: calendar
        )

        #expect(verdicts == [.invalidTime])
    }

    private func snapshot(
        start: Int,
        end: Int,
        isAllDay: Bool = false
    ) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: "予定",
            categoryID: nil,
            startMinute: start,
            endMinute: end,
            isAllDay: isAllDay,
            isImportant: false,
            note: nil,
            isPublic: true
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
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

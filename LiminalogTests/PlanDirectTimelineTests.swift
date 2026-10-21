import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct PlanDirectTimelineTests {
    let calendar = Calendar.liminalogTest
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func date(_ day: Int, _ hour: Int = 0) -> Date { date(2026, 9, day, hour) }

    @Test func verticalDragsKeepTheirLayerAndHorizontalDragsUseHysteresis() {
        #expect(!PlanTimelineKindPolicy.memo(atFraction: 0.9, horizontalMovement: 2, current: false))
        #expect(PlanTimelineKindPolicy.memo(atFraction: 0.9, horizontalMovement: 40, current: false))
        #expect(PlanTimelineKindPolicy.memo(atFraction: 0.5, horizontalMovement: -40, current: true))
        #expect(!PlanTimelineKindPolicy.memo(atFraction: 0.2, horizontalMovement: -40, current: true))
        #expect(PlanTimelineKindPolicy.memo(atFraction: 0.8, horizontalMovement: 13, current: false, threshold: 12))
    }

    @Test func layerChangePreviewNeverPushesOtherPlans() throws {
        let first = PlanTimelineInterval(id: UUID(), startMinute: 540, endMinute: 660)
        let second = PlanTimelineInterval(id: UUID(), startMinute: 660, endMinute: 720)
        let memo = PlanTimelineInterval(id: UUID(), startMinute: 570, endMinute: 630, isMemo: true)
        for (editing, target, start, end) in [(first.id, true, 600, 720), (memo.id, false, 570, 630)] {
            let result = try #require(PlanTimelineKindPolicy.resolve(items: [first, second, memo], editingID: editing,
                start: start, end: end, direction: .later, adjustment: .move, minimumDuration: end - start, targetIsMemo: target))
            #expect(result.first { $0.id == editing }?.isMemo == target)
            for original in [first, second, memo] where original.id != editing {
                #expect(result.first { $0.id == original.id } == original)
            }
        }
    }

    @Test func promotionPreviewOverlaysMainAtLeftWithoutMovingUnderlyingColumns() throws {
        let first = PlanTimelineInterval(id: UUID(), startMinute: 540, endMinute: 600)
        let second = PlanTimelineInterval(id: UUID(), startMinute: 600, endMinute: 660)
        let target = PlanTimelineInterval(id: UUID(), startMinute: 570, endMinute: 630)
        let otherMemo = PlanTimelineInterval(id: UUID(), startMinute: 585, endMinute: 615, isMemo: true)
        let slots = PlanTimelineLayoutSlot.makeSlots(for: [first, second, target, otherMemo], overlayMainID: target.id)
        for id in [first.id, second.id, target.id] {
            let slot = try #require(slots[id])
            #expect(slot.column == 0 && slot.columnCount == 1 && !slot.isMemo)
        }
        #expect(slots[otherMemo.id]?.isMemo == true)
    }

    @Test func memoCreationUsesTheSameAnchoredRangeAsMainInBothDirections() {
        var draft = TimelineMemoCreationDraft(sourceID: UUID(), anchorMinute: 600, minimumDuration: 5)
        for minute in [600, 675, 580, 599, 601, 1500, -30, 620] {
            draft.extend(to: minute)
            #expect(draft.range == PlanTimelineCreationPolicy.range(anchorMinute: 600, currentMinute: minute,
                minimumDuration: 5, intervals: [], enforcesMinimumDuration: false))
            #expect(draft.startMinute == 600 || draft.endMinute == 600)
        }
    }

    @Test func memoCreationAtDayEdgesRetainsAnchorAndMinimumDuration() {
        var late = TimelineMemoCreationDraft(sourceID: UUID(), anchorMinute: 1440, minimumDuration: 5)
        #expect(late.startMinute == 1440 && late.endMinute == 1440)
        #expect(late.committedRange == .init(start: 1435, end: 1440))
        late.extend(to: 1400)
        #expect(late.startMinute == 1400 && late.endMinute == 1440)
        var early = TimelineMemoCreationDraft(sourceID: UUID(), anchorMinute: 0, minimumDuration: 5)
        early.extend(to: 1)
        #expect(early.startMinute == 0 && early.endMinute == 1)
        #expect(early.committedRange == .init(start: 0, end: 5))
        early.extend(to: -10)
        #expect(early.startMinute == 0 && early.endMinute == 0)
        #expect(early.committedRange == .init(start: 0, end: 5))
    }

    @Test func creationMinimumIsAppliedOnlyOnReleaseInEitherDirection() {
        var draft = TimelineMemoCreationDraft(sourceID: UUID(), anchorMinute: 600, minimumDuration: 15)
        #expect(draft.range == .init(start: 600, end: 600))
        for minute in [601, 605, 599, 595, 600] {
            draft.extend(to: minute)
            #expect(draft.endMinute - draft.startMinute == abs(600 - minute))
            #expect(draft.committedRange.end - draft.committedRange.start == 15)
            #expect(draft.committedRange.start == 600 || draft.committedRange.end == 600)
        }
    }

    @Test func presetPlacementChangesLayerWithoutChangingMasterOrFixedTime() throws {
        let source = PlanTemplateSnapshot(title: "読書", categoryID: nil, startMinute: 540, endMinute: 600,
            isAllDay: false, isImportant: true, isPublic: false)
        for mode in [PlanPresetPlacementMode.duration, .fixedTime] {
            let memo = try #require(TimelinePlanPresetPlacementGeometry.snapshot(source, placementMode: mode,
                startMinute: 660, horizontalFraction: 0.9, currentIsMemo: false))
            #expect(memo.isMemo && memo.isImportant)
            #expect(memo.startMinute == (mode == .fixedTime ? 540 : 660))
            #expect(memo.durationMinutes == 60)
            let center = try #require(TimelinePlanPresetPlacementGeometry.snapshot(memo, placementMode: mode,
                startMinute: 660, horizontalFraction: 0.5, currentIsMemo: true))
            #expect(center.isMemo)
            let main = try #require(TimelinePlanPresetPlacementGeometry.snapshot(memo, placementMode: mode,
                startMinute: 660, horizontalFraction: 0.1, currentIsMemo: true))
            #expect(!main.isMemo && !source.isMemo && source.startMinute == 540)
        }
    }

    @Test func recurrenceCountsCalendarDatesIncludingPartialFirstWeeks() {
        var rule = PlanRecurrenceRule(frequency: .weekly, weekdays: [2, 4], startDate: date(1), occurrenceLimit: 3)
        #expect(rule.contains(date(2), calendar: calendar))
        #expect(rule.contains(date(7), calendar: calendar))
        #expect(rule.contains(date(9), calendar: calendar))
        #expect(!rule.contains(date(14), calendar: calendar))
        rule.interval = 2
        #expect(rule.contains(date(14), calendar: calendar))
        #expect(rule.contains(date(16), calendar: calendar))
        #expect(!rule.contains(date(28), calendar: calendar))
        rule = PlanRecurrenceRule(frequency: .daily, interval: 2, startDate: date(1), occurrenceLimit: 3)
        #expect(rule.contains(date(5), calendar: calendar))
        #expect(!rule.contains(date(7), calendar: calendar))
    }

    @Test func monthlyAndYearlyCountsSkipMissingDates() {
        var rule = PlanRecurrenceRule(frequency: .monthly, startDate: date(2026, 1, 31), occurrenceLimit: 3)
        #expect(!rule.contains(date(2026, 2, 28), calendar: calendar))
        #expect(rule.contains(date(2026, 5, 31), calendar: calendar))
        #expect(!rule.contains(date(2026, 7, 31), calendar: calendar))
        rule = PlanRecurrenceRule(frequency: .yearly, startDate: date(2024, 2, 29), occurrenceLimit: 3)
        #expect(!rule.contains(date(2025, 2, 28), calendar: calendar))
        #expect(rule.contains(date(2032, 2, 29), calendar: calendar))
        #expect(!rule.contains(date(2036, 2, 29), calendar: calendar))
        rule = PlanRecurrenceRule(frequency: .yearly, interval: 2, startDate: date(2026, 9, 17))
        #expect(rule.contains(date(2028, 9, 17), calendar: calendar))
        #expect(!rule.contains(date(2027, 9, 17), calendar: calendar))
    }

    @Test func oldRecurrenceJSONStillIncludesEntireEndDay() throws {
        let old = "{\"frequency\":\"daily\",\"interval\":1,\"weekdays\":[],\"startDate\":\(date(1).timeIntervalSinceReferenceDate),\"endDate\":\(date(2).timeIntervalSinceReferenceDate)}"
        var rule = try #require(PlanRecurrenceRule.decode(Data(old.utf8)))
        #expect(rule.allows(startingAt: date(2, 23), on: date(2), calendar: calendar))
        rule.endDate = date(2, 10); rule.endDateIncludesTime = true
        #expect(rule.allows(startingAt: date(2, 10), on: date(2), calendar: calendar))
        #expect(!rule.allows(startingAt: date(2, 11), on: date(2), calendar: calendar))
        #expect(rule.cadence == "毎日")
    }

    @Test func shorterCountRemovesOnlyUntouchedDefaultsAndDoesNotRestartInLaterWindows() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let clock = MutableTestClock(now: date(1))
        let snapshot = PlanTemplateSnapshot(title: "読書", categoryID: nil, startMinute: 540, endMinute: 600,
            isAllDay: false, isImportant: false, isPublic: false)
        var rule = PlanRecurrenceRule(frequency: .daily, startDate: date(2), occurrenceLimit: 4)
        let preset = try #require(PlanPresetStore(modelContext: context, clock: clock).createPlanPreset(name: "読書", snapshot: snapshot, recurrence: .some(rule)))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: date(10)).count == 4)
        let plans = try context.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.startTime)]))
        plans[3].title = "この日だけ変更"; try context.save()
        rule.occurrenceLimit = 2; preset.recurrenceData = rule.data; try context.save()
        #expect(try store.materialize(to: date(10)).count == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 3)
        #expect(try store.materialize(from: date(20), to: date(30)).isEmpty)
    }

    @Test func exactEndTimeRetiresLaterItemsInDayPreset() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let clock = MutableTestClock(now: date(1))
        let items = [9, 12].map { hour in PlanTemplateSnapshot(title: "予定", categoryID: nil,
            startMinute: hour * 60, endMinute: hour * 60 + 60, isAllDay: false, isImportant: false, isPublic: false, templateItemID: UUID()) }
        var rule = PlanRecurrenceRule(frequency: .daily, startDate: date(2), endDate: date(2, 15), endDateIncludesTime: true)
        let master = try #require(PlanPresetStore(modelContext: context, clock: clock).createDayPreset(name: "一日", items: items, recurrence: .some(rule)))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: date(4)).count == 2)
        rule.endDate = date(2, 10); master.recurrenceData = rule.data; try context.save()
        #expect(try store.materialize(to: date(4)).count == 1)
        #expect(try context.fetch(FetchDescriptor<PlanBlock>()).map(\.startTime) == [date(2, 9)])
    }

    @Test func fixedReminderDoesNotFollowMovesAndTemplatesRetainItsRelativeTiming() throws {
        let plan = PlanBlock(category: nil, title: "予定", startTime: date(20, 9), endTime: date(20, 10))
        plan.reminderDate = date(2, 14)
        #expect(PlanReminderRequest.make(for: plan, now: date(1), calendar: calendar)?.fireDate == date(2, 14))
        plan.startTime = date(21, 9); plan.endTime = date(21, 10)
        #expect(PlanReminderRequest.make(for: plan, now: date(1), calendar: calendar)?.fireDate == date(2, 14))
        let snapshot = try #require(PlanPresetStore.snapshot(from: plan, calendar: calendar))
        #expect(snapshot.reminderMinutesBefore == Int(date(21, 9).timeIntervalSince(date(2, 14)) / 60))
        let baseline = PlanRecurrenceBaseline(plan).data
        plan.reminderDate = date(3, 14)
        #expect(!PlanRecurrenceBaseline(plan).matches(baseline))
        plan.reminderDate = nil; plan.reminderMinutesBefore = 20_160
        #expect(PlanReminderRequest.make(for: plan, now: date(1), calendar: calendar)?.fireDate == date(7, 9))
        plan.reminderMinutesBefore = -60
        #expect(PlanReminderRequest.make(for: plan, now: date(1), calendar: calendar)?.fireDate == date(21, 10))
    }
}

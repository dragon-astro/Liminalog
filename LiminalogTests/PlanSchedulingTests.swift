import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("Recurring plan defaults and reminders")
struct PlanSchedulingTests {
    let calendar = Calendar.liminalogTest
    func day(_ value: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: value, hour: hour))!
    }
    func item(_ title: String = "読書", start: Int = 540, end: Int = 600, id: UUID? = nil) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(title: title, categoryID: nil, startMinute: start, endMinute: end,
            isAllDay: false, isImportant: false, note: nil, isPublic: false,
            reminderMinutesBefore: 10, templateItemID: id)
    }
    func plans(_ context: ModelContext) throws -> [PlanBlock] {
        try context.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.startTime)]))
    }

    @Test func rulesRespectCalendarBoundaries() {
        var rule = PlanRecurrenceRule(frequency: .daily, interval: 2, startDate: day(1), endDate: day(7))
        #expect([1, 3, 5, 7].allSatisfy { rule.contains(day($0), calendar: calendar) })
        #expect(!rule.contains(day(2), calendar: calendar))
        #expect(!rule.contains(day(9), calendar: calendar))
        rule = PlanRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 5], startDate: day(1))
        #expect(rule.contains(day(3), calendar: calendar))
        #expect(!rule.contains(day(8), calendar: calendar))
        #expect(rule.contains(day(15), calendar: calendar))
        rule = PlanRecurrenceRule(frequency: .monthly, startDate: calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!)
        #expect(!rule.contains(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!, calendar: calendar))
        #expect(rule.contains(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!, calendar: calendar))
        rule.interval = 0
        #expect(!rule.contains(day(1), calendar: calendar))
    }

    @Test func generatedPlansAreIdempotentAndPersonalEditsAndDeletionSurviveReload() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let clock = MutableTestClock(now: day(1, hour: 12))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let master = try #require(presets.createPlanPreset(name: "読書", snapshot: item(), recurrence: .some(PlanRecurrenceRule(frequency: .daily, startDate: day(2)))))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: day(5)).count == 3)
        #expect(try store.materialize(to: day(5)).isEmpty)
        #expect(!context.hasChanges)
        let generated = try plans(context)
        let movedID = generated[0].id
        generated[0].startTime = day(2, hour: 15)
        generated[0].endTime = day(2, hour: 16)
        let deletedID = generated[1].id
        context.delete(generated[1])
        try context.save()
        master.startMinute = 600; master.endMinute = 660; master.title = "新しい読書"
        try context.save()
        let reopened = ModelContext(container)
        let resumed = PlanRecurrenceStore(modelContext: reopened, clock: clock, calendar: calendar)
        #expect(try resumed.materialize(to: day(5)).count == 1)
        let result = try plans(reopened)
        #expect(result.count == 2)
        #expect(result.first { $0.id == movedID }?.startTime == day(2, hour: 15))
        #expect(!result.contains { $0.id == deletedID })
        #expect(result.last?.title == "新しい読書")
        #expect(result.last?.reminderMinutesBefore == 10)
    }

    @Test func shiftingWholeDayDefaultsDoesNotConflictWithOldPositions() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let first = UUID(), second = UUID()
        let master = try #require(presets.createDayPreset(name: "朝", items: [item("A", id: first), item("B", start: 600, end: 660, id: second)], recurrence: .some(PlanRecurrenceRule(frequency: .daily, startDate: day(2), endDate: day(2)))))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: day(3)).count == 2)
        let ids = Set(try plans(context).map(\.id))
        // Reorder the template and shift both by an hour, retaining their identities.
        master.itemsData = try DayPresetItemsCodec.encode([item("B", start: 660, end: 720, id: second), item("A", start: 600, end: 660, id: first)])
        try context.save()
        #expect(try store.materialize(to: day(3)).count == 2)
        #expect(Set(try plans(context).map(\.id)) == ids)
        #expect(try plans(context).map(\.startTime) == [day(2, hour: 10), day(2, hour: 11)])
    }

    @Test func conflictingManualPlanIsNeverReplacedAndDefaultsRetryWhenFree() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let manual = PlanBlock(category: nil, title: "手動", startTime: day(2, hour: 9), endTime: day(2, hour: 10))
        context.insert(manual); try context.save()
        _ = PlanPresetStore(modelContext: context, clock: clock).createPlanPreset(name: "読書", snapshot: item(), recurrence: .some(PlanRecurrenceRule(frequency: .daily, startDate: day(2))))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try store.materialize(to: day(3)).isEmpty)
        #expect(try plans(context).map(\.title) == ["手動"])
        context.delete(manual); try context.save()
        #expect(try store.materialize(to: day(3)).count == 1)
    }

    @Test func disablingAndReenablingPreservesOnlyPersonalDeletions() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let rule = PlanRecurrenceRule(frequency: .daily, startDate: day(2))
        let master = try #require(PlanPresetStore(modelContext: context, clock: clock).createPlanPreset(name: "読書", snapshot: item(), recurrence: .some(rule)))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        _ = try store.materialize(to: day(4))
        let generated = try plans(context)
        context.delete(generated[0]); try context.save()
        master.recurrenceData = nil; try context.save()
        #expect(try store.materialize(to: day(4)).count == 1)
        #expect(try plans(context).isEmpty)
        master.recurrenceData = rule.data; try context.save()
        #expect(try store.materialize(to: day(4)).count == 1)
        #expect(try plans(context).first?.startTime == day(3, hour: 9))
    }

    @Test func registrationJoinsPlanTransactionAndCreatesFixedMaster() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let recurrence = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        let store = PlanStore(modelContext: context, clock: clock)
        let plan = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(2, hour: 9), endTime: day(2, hour: 10), beforeSave: {
            $0.reminderMinutesBefore = 30
            return recurrence.register($0, rule: PlanRecurrenceRule(frequency: .daily, startDate: day(2)))
        }))
        let master = try #require(context.fetch(FetchDescriptor<PlanPreset>()).first)
        #expect(master.id == plan.recurrenceSeriesID)
        #expect(master.placementMode == .fixedTime)
        #expect(master.reminderMinutesBefore == 30)
        _ = try recurrence.materialize(to: day(4))
        #expect(try plans(context).count == 2)
    }

    @Test func reminderFollowsTimeAndAllDayUsesNineAM() {
        let plan = PlanBlock(category: nil, title: "読書", startTime: day(2, hour: 9), endTime: day(2, hour: 10))
        plan.reminderMinutesBefore = 10
        let first = PlanReminderRequest.make(for: plan, now: day(1), calendar: calendar)
        #expect(first?.fireDate == day(2, hour: 9).addingTimeInterval(-600))
        plan.startTime = day(2, hour: 11)
        let moved = PlanReminderRequest.make(for: plan, now: day(1), calendar: calendar)
        #expect(moved?.id == first?.id)
        #expect(moved?.fireDate == day(2, hour: 11).addingTimeInterval(-600))
        plan.isAllDay = true; plan.startTime = day(2); plan.reminderMinutesBefore = 1440
        #expect(PlanReminderRequest.make(for: plan, now: day(1), calendar: calendar)?.fireDate == day(1, hour: 9))
        plan.reminderMinutesBefore = nil
        #expect(PlanReminderRequest.make(for: plan, now: day(1), calendar: calendar) == nil)
        plan.reminderMinutesBefore = 0
        #expect(PlanReminderRequest.make(for: plan, now: day(3), calendar: calendar) == nil)
    }

    @Test func reminderScheduleCancelsDeletedPlansAndKeepsOtherNotifications() {
        let plan = PlanBlock(category: nil, title: "予定", startTime: day(2, hour: 9), endTime: day(2, hour: 10))
        plan.reminderMinutesBefore = 10
        let wanted = PlanReminderSchedule.desired(plans: [plan], now: day(1), otherNotificationCount: 1, calendar: calendar)
        let id = "plan-reminder-\(plan.id)"
        #expect(wanted.map(\.id) == [id])
        #expect(PlanReminderSchedule.obsolete(pendingIDs: [id, "streak-warning"], desired: wanted).isEmpty)
        #expect(PlanReminderSchedule.obsolete(pendingIDs: [id, "streak-warning"], desired: []) == [id])
        #expect(PlanReminderSchedule.desired(plans: [plan], now: day(1), otherNotificationCount: 60, calendar: calendar).isEmpty)
    }

    @Test func fillingAFullDayForTwoMonthsRemainsIdempotent() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let items = (0..<24).map { item("予定\($0)", start: $0 * 60, end: $0 * 60 + 30, id: UUID()) }
        _ = PlanPresetStore(modelContext: context, clock: clock).createDayPreset(name: "一日", items: items,
            recurrence: .some(PlanRecurrenceRule(frequency: .daily, startDate: day(2))))
        let store = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        let start = Date()
        #expect(try store.materialize().count == 59 * 24)
        let initial = Date().timeIntervalSince(start)
        let repeatStart = Date()
        #expect(try store.materialize().isEmpty)
        #expect(!context.hasChanges)
        print("Recurrence 1416 plans: initial=\(initial), unchanged=\(Date().timeIntervalSince(repeatStart)) seconds")
    }

    @Test func cloudDuplicateMergePrefersPersonalOccurrenceOverNewerDefault() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let seriesID = UUID(), planID = UUID()
        let generated = PlanBlock(category: nil, title: "読書", startTime: day(2, hour: 9), endTime: day(2, hour: 10))
        generated.id = planID; generated.recurrenceSeriesID = seriesID; generated.updatedAt = day(1, hour: 12)
        generated.reminderMinutesBefore = 10
        let record = PlanRecurrenceOccurrence(seriesID: seriesID, itemID: seriesID, day: day(2))
        record.planID = planID; record.baselineData = PlanRecurrenceBaseline(generated).data
        let personal = PlanBlock(category: nil, title: "自分で変更", startTime: day(2, hour: 14), endTime: day(2, hour: 15))
        personal.id = planID; personal.recurrenceSeriesID = seriesID; personal.updatedAt = day(1, hour: 10)
        context.insert(generated); context.insert(record); context.insert(personal); try context.save()
        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()
        let result = try plans(context)
        #expect(result.count == 1)
        #expect(result.first?.title == "自分で変更")
        #expect(result.first?.startTime == day(2, hour: 14))
        #expect(result.first?.reminderMinutesBefore == nil)
    }

    @Test func unrelatedManualAndRecurringPlansAreNotDeduplicatedTogether() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        for recurring in [true, false] {
            let plan = PlanBlock(category: nil, title: "同じ名前", startTime: day(2, hour: 9), endTime: day(2, hour: 10))
            if recurring { plan.recurrenceSeriesID = UUID() }
            context.insert(plan)
        }
        try context.save()
        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()
        #expect(try plans(context).count == 2)
    }

    @Test func cloudMergeWaitsUntilOccurrenceHistoryArrives() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let id = UUID(), series = UUID()
        for hour in [9, 14] {
            let plan = PlanBlock(category: nil, title: "同期中", startTime: day(2, hour: hour), endTime: day(2, hour: hour + 1))
            plan.id = id; plan.recurrenceSeriesID = series
            context.insert(plan)
        }
        try context.save()
        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()
        #expect(try plans(context).count == 2)
    }

    @Test func recurrenceRegistrationFailureRollsBackThePlanSave() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let recurring = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        let store = PlanStore(modelContext: context, clock: clock)
        let result = store.createPlanBlock(category: nil, title: "24時間を超える予定", startTime: day(2, hour: 9), endTime: day(3, hour: 11), beforeSave: {
            recurring.register($0, rule: PlanRecurrenceRule(frequency: .daily, startDate: day(2)))
        })
        #expect(result == nil)
        #expect(try plans(context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<PlanPreset>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test func oldTemplatePayloadStillDecodesWithoutNewFields() throws {
        let json = Data(#"{"version":1,"items":[{"title":"旧予定","startMinute":540,"endMinute":600,"isAllDay":false,"isImportant":false,"isPublic":false}]}"#.utf8)
        let decoded = try DayPresetItemsCodec.decode(json)
        #expect(decoded.count == 1)
        #expect(decoded[0].reminderMinutesBefore == nil)
        #expect(decoded[0].templateItemID == nil)
    }
}

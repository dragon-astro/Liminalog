import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct PlanMemoTests {
    let calendar = Calendar.liminalogTest
    func day(_ day: Int = 2, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    func store(_ context: ModelContext) -> PlanStore {
        PlanStore(modelContext: context, clock: MutableTestClock(now: day(1)), requestRefresh: { _, _, _ in })
    }
    func item(_ title: String, memo: Bool = false) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(title: title, categoryID: nil, startMinute: 540, endMinute: 600,
            isAllDay: false, isImportant: false, note: nil, isPublic: false, isMemo: memo)
    }
    func save(_ plan: PlanBlock, memo: Bool, using store: PlanStore,
              approval: [PlanMemoPromotionChange]? = nil, mode: PlanMemoPromotionMode = .keepRemainders) -> Bool {
        store.savePlanBlock(plan, category: plan.category, title: plan.title,
            startTime: plan.startTime, endTime: plan.endTime, isAllDay: plan.isAllDay,
            isMemo: memo, isImportant: plan.isImportant, note: plan.note, isPublic: plan.isPublic,
            approvedPromotion: approval, promotionMode: mode)
    }

    @Test func overlappingMemosPersistWithoutBlockingMainAndRemainEditableOnPastDays() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let memo = try #require(store.createPlanBlock(category: nil, title: "荷物", startTime: day(), endTime: day(hour: 10), isMemo: true))
        let main = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 10)))
        #expect(store.createPlanBlock(category: nil, title: "電話", startTime: day(), endTime: day(hour: 10), isMemo: true) != nil)
        #expect(store.createPlanBlock(category: nil, title: "別のメイン", startTime: day(), endTime: day(hour: 10)) == nil)
        #expect(store.savePlanScheduleChanges([.init(plan: memo, startTime: day(1), endTime: day(1, hour: 11))]))
        #expect(main.startTime == day() && main.endTime == day(hour: 10))
        #expect(!store.isScheduleLocked(memo))
        #expect(!save(memo, memo: false, using: store))
        #expect(memo.isMemo)
        #expect(store.createPlanBlock(category: nil, title: "不正", startTime: day(), endTime: day(), isMemo: true) == nil)
        let reopened = ModelContext(container)
        let id = memo.id
        #expect(try reopened.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.id == id })).first?.isMemo == true)
    }

    @Test func promotionKeepsNonoverlappingTimeAndRequiresExactApproval() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let main = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 12)))
        let memo = try #require(store.createPlanBlock(category: nil, title: "打ち合わせ", startTime: day(hour: 10), endTime: day(hour: 11), isMemo: true))
        let before = try #require(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id))
        #expect(before.map(\.id) == [main.id])
        #expect(!save(memo, memo: false, using: store))
        #expect(!main.isMemo && memo.isMemo)
        main.title = "変更後"; main.updatedAt = day(hour: 13); try context.save()
        #expect(!save(memo, memo: false, using: store, approval: before))
        #expect(!main.isMemo && memo.isMemo)
        let refreshed = try #require(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id))
        #expect(save(memo, memo: false, using: store, approval: refreshed))
        #expect(!main.isMemo && !memo.isMemo)
        #expect(main.startTime == day() && main.endTime == day(hour: 10))
        #expect(memo.startTime == day(hour: 10) && memo.endTime == day(hour: 11))
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 3)
        #expect(save(memo, memo: true, using: store))
    }

    @Test(arguments: PlanMemoPromotionMode.allCases)
    func promotionChoicesSaveExactlyTheirPreviewAndLeaveOtherMemosAlone(mode: PlanMemoPromotionMode) throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let main = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 12),
            isImportant: true, note: "残す内容", isPublic: false))
        let mainID = main.id
        let untouched = try #require(store.createPlanBlock(category: nil, title: "電話", startTime: day(), endTime: day(hour: 12), isMemo: true))
        let memo = try #require(store.createPlanBlock(category: nil, title: "打ち合わせ", startTime: day(hour: 10), endTime: day(hour: 11), isMemo: true))
        let approval = try #require(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id))
        #expect(!save(memo, memo: false, using: store, mode: mode))
        #expect(save(memo, memo: false, using: store, approval: approval, mode: mode))
        let reloaded = ModelContext(container)
        let all = try reloaded.fetch(FetchDescriptor<PlanBlock>())
        #expect(all.first { $0.id == memo.id }?.isMemo == false)
        #expect(all.first { $0.id == untouched.id }?.isMemo == true)
        let remaining = all.filter { $0.title == "仕事" }.sorted { $0.startTime < $1.startTime }
        let preview = mode.replacement(changes: approval, start: memo.startTime, end: memo.endTime)
        #expect(remaining.map { DateInterval(start: $0.startTime, end: $0.endTime) } == preview.changes[0].remaining)
        #expect(remaining.allSatisfy { !$0.isMemo && $0.isImportant && $0.note == "残す内容" && !$0.isPublic })
        if mode == .keepRemainders { #expect(remaining.first?.id == mainID) }
        let mains = all.filter { !$0.isMemo }.sorted { $0.startTime < $1.startTime }
        #expect(zip(mains, mains.dropFirst()).allSatisfy { $0.endTime <= $1.startTime })
    }

    @Test(arguments: PlanMemoPromotionMode.allCases)
    func promotionChoicesRejectStaleApprovalAndRollBackFailedSave(mode: PlanMemoPromotionMode) throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let main = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 12)))
        let memo = try #require(store.createPlanBlock(category: nil, title: "会議", startTime: day(hour: 10), endTime: day(hour: 11), isMemo: true))
        let approval = try #require(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id))
        main.title = "更新"; try context.save()
        #expect(!save(memo, memo: false, using: store, approval: approval, mode: mode))
        let fresh = try #require(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id))
        #expect(!store.savePlanBlock(memo, category: nil, title: memo.title, startTime: memo.startTime,
            endTime: memo.endTime, isAllDay: false, isMemo: false, isImportant: false, note: nil, isPublic: false,
            approvedPromotion: fresh, promotionMode: mode, beforeSave: { _ in false }))
        let all = try ModelContext(container).fetch(FetchDescriptor<PlanBlock>())
        #expect(all.count == 2)
        #expect(all.first { $0.title == "更新" }?.isMemo == false)
        #expect(all.first { $0.title == "会議" }?.isMemo == true)
    }

    @Test func protectedMainCannotBeDemotedByPromotion() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let main = PlanBlock(category: nil, title: "外部", startTime: day(), endTime: day(hour: 10))
        main.sourceEventID = "external"; context.insert(main); try context.save()
        let memo = try #require(store.createPlanBlock(category: nil, title: "メモ", startTime: day(), endTime: day(hour: 10), isMemo: true))
        #expect(store.memoPromotionPreview(start: memo.startTime, end: memo.endTime, excluding: memo.id) == nil)
        #expect(!save(memo, memo: false, using: store, approval: []))
        #expect(!main.isMemo && memo.isMemo)
    }

    @Test func memoMoveAndResizeNeverPushWhileMainStillPushesMainOnly() throws {
        let first = PlanTimelineInterval(id: UUID(), startMinute: 540, endMinute: 600)
        let second = PlanTimelineInterval(id: UUID(), startMinute: 600, endMinute: 660)
        let memo = PlanTimelineInterval(id: UUID(), startMinute: 550, endMinute: 630, isMemo: true)
        let items = [first, second, memo]
        let moved = try #require(PlanTimelineRescheduler.resolveClamped(items: items, editingID: memo.id,
            proposedStartMinute: 590, proposedEndMinute: 670, pushDirection: .later, adjustment: .move))
        #expect(moved.first { $0.id == first.id } == first)
        #expect(moved.first { $0.id == second.id } == second)
        let resized = try #require(PlanTimelineRescheduler.resolveClamped(items: items, editingID: memo.id,
            proposedStartMinute: 550, proposedEndMinute: 720, pushDirection: .later, adjustment: .resizeEnd))
        #expect(resized.first { $0.id == second.id } == second)
        let pushed = try #require(PlanTimelineRescheduler.resolveClamped(items: items, editingID: first.id,
            proposedStartMinute: 540, proposedEndMinute: 630, pushDirection: .later, adjustment: .resizeEnd))
        #expect(pushed.first { $0.id == second.id }?.startMinute == 630)
        #expect(pushed.first { $0.id == memo.id } == memo)
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 555, currentMinute: 600, minimumDuration: 15, intervals: [memo]) != nil)
    }

    @Test func memoIsExcludedFromAchievementAndFreeTime() {
        let main = PlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 10))
        let memo = PlanBlock(category: nil, title: "荷物", startTime: day(), endTime: day(hour: 18), isMemo: true)
        let without = ScoreCalculator.summary(date: day(), plans: [main], chapters: [], calendar: calendar)
        let with = ScoreCalculator.summary(date: day(), plans: [main, memo], chapters: [], calendar: calendar)
        #expect(with.plannedDuration == without.plannedDuration)
        #expect(with.totalScore == without.totalScore)
        #expect(ScoreCalculator.summary(date: day(), plans: [memo], chapters: [], calendar: calendar).plannedDuration == 0)
        #expect(PlanCoverageSummary.make(date: day(), plans: [main, memo], calendar: calendar).plannedDuration == 3600)
    }

    @Test func changingOnlyKindInvalidatesCalendarScoreCache() {
        let plan = PlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 10))
        func summary() -> ScoreSummary {
            CalendarDayScoreCache.summary(date: day(), dayStart: calendar.startOfDay(for: day()),
                plans: [plan], chapters: [], calendar: calendar, now: day(1))
        }
        #expect(summary().plannedDuration == 3600)
        plan.isMemo = true
        #expect(summary().plannedDuration == 0)
        plan.isMemo = false
        #expect(summary().plannedDuration == 3600)
    }

    @Test func mixedPresetCanOverlapAndLegacyPayloadDefaultsToMain() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let main = item("仕事"), memo = item("電話", memo: true)
        #expect(!DayPresetApplyPlanner.hasConflictsWithinPreset([main, memo]))
        #expect(DayPresetApplyPlanner.hasConflictsWithinPreset([main, main]))
        let data = try DayPresetItemsCodec.encode([main, memo])
        let decoded = try DayPresetItemsCodec.decode(data)
        #expect(decoded.map(\.isMemo) == [false, true])
        // Main payload still omits the optional memo field, matching pre-feature JSON.
        #expect(!String(decoding: try JSONEncoder().encode(main), as: UTF8.self).contains("memo"))
        let store = store(context)
        #expect(store.applyTemplates(decoded.map { .init(snapshot: $0, resolvedCategory: nil) }, to: day(), calendar: calendar))
        #expect(store.allPlannedBlocks().filter(\.isMemo).count == 1)
        let preset = try #require(PlanPresetStore(modelContext: context).createPlanPreset(name: "電話", snapshot: memo))
        #expect(preset.isMemo && preset.snapshot.isMemo)
        let datedMemo = try #require(store.allPlannedBlocks().first { $0.isMemo })
        #expect(PlanPresetStore.snapshot(from: datedMemo, calendar: calendar)?.isMemo == true)
    }

    @Test func copyAndReplacementLeaveMemoTimeAndKindIntact() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let store = store(context)
        let main = try #require(store.createPlanBlock(category: nil, title: "仕事", startTime: day(), endTime: day(hour: 10)))
        let memo = try #require(store.createPlanBlock(category: nil, title: "電話", startTime: day(), endTime: day(hour: 10), isMemo: true))
        _ = try #require(store.createPlanBlock(category: nil, title: "明日の仕事", startTime: day(3), endTime: day(3, hour: 10)))
        let preview = try store.transferPreview(id: memo.id, to: [day(3)], mode: .copy, calendar: calendar).get()
        #expect(preview.replacement.changes.isEmpty)
        #expect(try store.transferPlan(id: memo.id, to: [day(3)], mode: .copy, calendar: calendar).get() == 1)
        #expect(store.allPlannedBlocks().filter(\.isMemo).count == 2)
        let applications: [PlanStore.TemplateApplication] = [.init(snapshot: item("変更"), resolvedCategory: nil)]
        let replacement = try #require(store.templateReplacementPreview(applications, to: day(), mode: .replaceWholePlans, calendar: calendar))
        #expect(replacement.changes.map(\.id) == [main.id])
        #expect(store.applyTemplates(applications, to: day(), calendar: calendar, approvedReplacement: replacement))
        #expect(store.allPlannedBlocks().contains { $0.id == memo.id && $0.isMemo && $0.startTime == day() })
    }

    @Test func recurringMemosOverlapAndDaySpecificKindChangesSurviveRefresh() throws {
        let container = try TestModelContainer.make(), context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let rule = PlanRecurrenceRule(frequency: .daily, startDate: day(2), endDate: day(3))
        let master = try #require(presets.createDayPreset(name: "型", items: [item("仕事"), item("荷物", memo: true)], recurrence: .some(rule)))
        let recurrence = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        #expect(try recurrence.materialize(to: day(4, hour: 0)).count == 4)
        let memo = try #require(store(context).allPlannedBlocks().first { $0.isMemo })
        let memoID = memo.id
        let main = try #require(store(context).allPlannedBlocks().first { !$0.isMemo && $0.startTime == memo.startTime })
        // A user swaps roles; both edits must be preserved by the next default refresh.
        memo.isMemo = false; main.isMemo = true; try context.save()
        #expect(try recurrence.materialize(to: day(4, hour: 0)).isEmpty)
        #expect(store(context).allPlannedBlocks().first { $0.id == memoID }?.isMemo == false)
        #expect(try DayPresetItemsCodec.decode(master.itemsData).filter(\.isMemo).count == 1)
    }

    @Test func memoColumnsDoNotShrinkMainAndTouchingMemoIntervalsReuseColumn() throws {
        let main = PlanTimelineInterval(id: UUID(), startMinute: 540, endMinute: 720)
        let first = PlanTimelineInterval(id: UUID(), startMinute: 540, endMinute: 600, isMemo: true)
        let second = PlanTimelineInterval(id: UUID(), startMinute: 570, endMinute: 630, isMemo: true)
        let third = PlanTimelineInterval(id: UUID(), startMinute: 600, endMinute: 660, isMemo: true)
        let slots = PlanTimelineLayoutSlot.makeSlots(for: [main, first, second, third])
        #expect(slots[main.id]?.columnCount == 1 && slots[main.id]?.isMemo == false)
        #expect(slots[first.id]?.columnCount == 2 && slots[first.id]?.isMemo == true)
        #expect(slots[first.id]?.column == slots[third.id]?.column)
    }

    @Test func sharedMemoKindSurvivesJSONAndRecordCache() throws {
        let memo = PlanBlock(category: nil, title: "電話", startTime: day(), endTime: day(hour: 10), isMemo: true)
        let snapshot = FriendSharedPlanSnapshot(plan: memo)
        let decoded = try JSONDecoder().decode(FriendSharedPlanSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.isMemo)
        #expect(FriendSharedPlanRecord(friendID: UUID(), snapshot: decoded).snapshot.isMemo)
        memo.isMemo = false
        let oldData = try JSONEncoder().encode(FriendSharedPlanSnapshot(plan: memo))
        #expect(!String(decoding: oldData, as: UTF8.self).contains("memo"))
        #expect(try !JSONDecoder().decode(FriendSharedPlanSnapshot.self, from: oldData).isMemo)
    }
}

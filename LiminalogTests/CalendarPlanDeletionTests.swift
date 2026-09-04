import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("CalendarPlanDeletion")
struct CalendarPlanDeletionTests {
    private func date(_ day: Int, hour: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test("一覧削除の保存経路で対象だけ消え、共有更新へIDを通知する")
    func deleteFuturePlan() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = PlanBlock(category: nil, title: "削除対象", startTime: date(10), endTime: date(10, hour: 10))
        let other = PlanBlock(category: nil, title: "保持", startTime: date(11), endTime: date(11, hour: 10))
        let targetID = target.id
        context.insert(target)
        context.insert(other)
        try context.save()
        var refreshedIDs: Set<UUID> = []
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: date(4)), requestRefresh: { _, ids, _ in
            refreshedIDs.formUnion(ids)
        })
        #expect(store.deletePlanBlock(target))
        let persisted = try ModelContext(container).fetch(FetchDescriptor<PlanBlock>())
        #expect(persisted.map(\.id) == [other.id])
        #expect(refreshedIDs == [targetID])
    }

    @Test("確認中に日付が変わってロックされた予定も削除しない")
    func rechecksLockAtCommit() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = PlanBlock(category: nil, title: "保持", startTime: date(5), endTime: date(5, hour: 10))
        context.insert(target)
        try context.save()
        let clock = MutableTestClock(now: date(4))
        let store = PlanStore(modelContext: context, clock: clock, requestRefresh: { _, _, _ in })
        #expect(!store.isScheduleLocked(target))
        clock.now = date(5, hour: 0)
        #expect(!store.deletePlanBlock(target))
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test("複数日の終日予定は一つの予定全体として削除する")
    func allDaySpan() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = PlanBlock(category: nil, title: "終日", startTime: date(2, hour: 0), endTime: date(6, hour: 0), isAllDay: true)
        context.insert(target)
        try context.save()
        var refreshedDays: Set<Date> = []
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: date(4)), requestRefresh: { _, _, days in
            refreshedDays.formUnion(days)
        })
        #expect(store.deletePlanBlock(target))
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
        #expect(refreshedDays == Set((2...5).map { date($0, hour: 0) }))
    }
}

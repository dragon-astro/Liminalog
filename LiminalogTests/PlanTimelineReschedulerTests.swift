import Foundation
import SwiftData
import Testing
@testable import Liminalog

@Suite("PlanTimelineRescheduler")
struct PlanTimelineReschedulerTests {
    @Test("開始ハンドルを終了時刻より後ろへ越えても最小幅のまま後ろへ動く")
    func startHandlePastEndMovesMinimumBlockLater() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .start,
            delta: 90
        )

        #expect(result.startMinute == 11 * 60 + 30)
        #expect(result.endMinute == 11 * 60 + 45)
        #expect(result.pushDirection == .later)
        #expect(result.feedbackMinute == 11 * 60 + 30)
    }

    @Test("終了ハンドルを開始時刻より前へ越えても最小幅のまま前へ動く")
    func endHandlePastStartMovesMinimumBlockEarlier() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -90
        )

        #expect(result.startMinute == 9 * 60 + 15)
        #expect(result.endMinute == 9 * 60 + 30)
        #expect(result.pushDirection == .earlier)
        #expect(result.feedbackMinute == 9 * 60 + 30)
    }

    @Test("開始ハンドルは日付終端を越えず最小幅を保つ")
    func startHandleNearDayEndKeepsMinimumBlockInsideDay() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 23 * 60 + 20,
            originalEndMinute: 23 * 60 + 50,
            edge: .start,
            delta: 60
        )

        #expect(result.startMinute == 23 * 60 + 45)
        #expect(result.endMinute == 24 * 60)
        #expect(result.pushDirection == .later)
        #expect(result.feedbackMinute == 23 * 60 + 45)
    }

    @Test("終了ハンドルは日付始端を越えず最小幅を保つ")
    func endHandleNearDayStartKeepsMinimumBlockInsideDay() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10,
            originalEndMinute: 40,
            edge: .end,
            delta: -60
        )

        #expect(result.startMinute == 0)
        #expect(result.endMinute == 15)
        #expect(result.pushDirection == .earlier)
        #expect(result.feedbackMinute == 15)
    }

    @Test("終了ハンドルで次の予定にぶつかると後続予定を押す")
    func pushesLaterPlansWhenEndHandleExpands() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 30,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 9 * 60)
        #expect(items[firstID]?.endMinute == 10 * 60 + 30)
        #expect(items[secondID]?.startMinute == 10 * 60 + 30)
        #expect(items[secondID]?.endMinute == 11 * 60 + 30)
    }

    @Test("後方への玉突きは密集した複数予定へ連鎖する")
    func pushingLaterCascadesThroughMultiplePlans() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 10 * 60 + 30),
                PlanTimelineInterval(id: thirdID, startMinute: 10 * 60 + 30, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 15,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 9 * 60)
        #expect(items[firstID]?.endMinute == 10 * 60 + 15)
        #expect(items[secondID]?.startMinute == 10 * 60 + 15)
        #expect(items[secondID]?.endMinute == 10 * 60 + 45)
        #expect(items[thirdID]?.startMinute == 10 * 60 + 45)
        #expect(items[thirdID]?.endMinute == 11 * 60 + 15)
    }

    @Test("開始ハンドルで前の予定にぶつかると前方予定を押し上げる")
    func pushesEarlierPlansWhenStartHandleExpands() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 9 * 60 + 30,
            proposedEndMinute: 11 * 60,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 8 * 60 + 30)
        #expect(items[firstID]?.endMinute == 9 * 60 + 30)
        #expect(items[secondID]?.startMinute == 9 * 60 + 30)
        #expect(items[secondID]?.endMinute == 11 * 60)
    }

    @Test("前方への玉突きは密集した複数予定へ連鎖する")
    func pushingEarlierCascadesThroughMultiplePlans() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 9 * 60 + 30),
                PlanTimelineInterval(id: secondID, startMinute: 9 * 60 + 30, endMinute: 10 * 60),
                PlanTimelineInterval(id: thirdID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: thirdID,
            proposedStartMinute: 9 * 60 + 45,
            proposedEndMinute: 11 * 60,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 8 * 60 + 45)
        #expect(items[firstID]?.endMinute == 9 * 60 + 15)
        #expect(items[secondID]?.startMinute == 9 * 60 + 15)
        #expect(items[secondID]?.endMinute == 9 * 60 + 45)
        #expect(items[thirdID]?.startMinute == 9 * 60 + 45)
        #expect(items[thirdID]?.endMinute == 11 * 60)
    }

    @Test("予定を後ろへ移動して次の予定をまたいでも玉突きで押す")
    func movingPlanLaterAcrossNextPlanPushesCollision() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 10 * 60 + 30,
            proposedEndMinute: 11 * 60 + 30,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 10 * 60 + 30)
        #expect(items[firstID]?.endMinute == 11 * 60 + 30)
        #expect(items[secondID]?.startMinute == 11 * 60 + 30)
        #expect(items[secondID]?.endMinute == 12 * 60 + 30)
    }

    @Test("予定を前へ移動して前の予定をまたいでも玉突きで押し上げる")
    func movingPlanEarlierAcrossPreviousPlanPushesCollision() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 8 * 60 + 30,
            proposedEndMinute: 9 * 60 + 30,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 7 * 60 + 30)
        #expect(items[firstID]?.endMinute == 8 * 60 + 30)
        #expect(items[secondID]?.startMinute == 8 * 60 + 30)
        #expect(items[secondID]?.endMinute == 9 * 60 + 30)
    }

    @Test("後方への玉突きが日付終端を超える配置は拒否する")
    func pushingLaterPastDayEndFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 22 * 60 + 30, endMinute: 23 * 60 + 30),
                PlanTimelineInterval(id: secondID, startMinute: 23 * 60 + 30, endMinute: 24 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 22 * 60 + 30,
            proposedEndMinute: 23 * 60 + 45,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }

    @Test("前方への玉突きが日付始端を超える配置は拒否する")
    func pushingEarlierPastDayStartFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 0, endMinute: 30),
                PlanTimelineInterval(id: secondID, startMinute: 30, endMinute: 90)
            ],
            editingID: secondID,
            proposedStartMinute: 15,
            proposedEndMinute: 75,
            pushDirection: .earlier
        )

        #expect(resolved == nil)
    }

    @Test("移動先でロック済み予定を押す必要がある配置は拒否する")
    func movingAcrossLockedPlanFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60, isLocked: true)
            ],
            editingID: firstID,
            proposedStartMinute: 10 * 60 + 30,
            proposedEndMinute: 11 * 60 + 30,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }

    @Test("ロック済み予定を押す必要がある配置は拒否する")
    func lockedCollisionFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60, isLocked: true)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 15,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }
}

@MainActor
@Suite("PlanStore timeline scheduling")
struct PlanStoreTimelineSchedulingTests {
    @Test("未来日の複数予定を一括で重ならない配置へ保存できる")
    func batchScheduleChangesCanMoveMultipleFuturePlans() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))
        let firstStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 9)))
        let firstEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let secondStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let secondEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11)))

        #expect(store.addPlanBlock(category: nil, title: "前半", startTime: firstStart, endTime: firstEnd))
        #expect(store.addPlanBlock(category: nil, title: "後半", startTime: secondStart, endTime: secondEnd))
        let plans = store.allPlannedBlocks().sorted { $0.startTime < $1.startTime }
        let first = try #require(plans.first)
        let second = try #require(plans.dropFirst().first)
        let movedFirstEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10, minute: 30)))
        let movedSecondStart = movedFirstEnd
        let movedSecondEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11, minute: 30)))

        #expect(store.savePlanScheduleChanges([
            .init(plan: first, startTime: firstStart, endTime: movedFirstEnd),
            .init(plan: second, startTime: movedSecondStart, endTime: movedSecondEnd)
        ]))

        #expect(first.endTime == movedFirstEnd)
        #expect(second.startTime == movedSecondStart)
        #expect(second.endTime == movedSecondEnd)
    }

    @Test("当日の時刻指定予定は一括移動できない")
    func batchScheduleChangesRejectsLockedPlans() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 10)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 11)))
        let plan = PlanBlock(category: nil, title: "今日", startTime: start, endTime: end)
        context.insert(plan)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))
        let movedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 11)))
        let movedEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 12)))

        #expect(!store.savePlanScheduleChanges([
            .init(plan: plan, startTime: movedStart, endTime: movedEnd)
        ]))
        #expect(plan.startTime == start)
        #expect(plan.endTime == end)
    }
}

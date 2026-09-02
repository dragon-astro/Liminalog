import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("PlanStore applyTemplates")
struct PlanStoreApplyTemplatesTests {
    private let calendar = Calendar.liminalogTest

    @Test("複数テンプレートを一括保存しrefreshを一度だけ通知する")
    func appliesAllTemplatesInOneBatch() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        var refreshes: [(String, Set<UUID>, Set<Date>)] = []
        let store = PlanStore(
            modelContext: context,
            clock: MutableTestClock(now: now),
            requestRefresh: { reason, ids, days in
                refreshes.append((reason, ids, days))
            }
        )

        let didApply = store.applyTemplates([
            .init(
                snapshot: snapshot(title: "", start: 9 * 60, end: 10 * 60),
                resolvedCategory: nil
            ),
            .init(
                snapshot: snapshot(
                    title: "睡眠",
                    start: 23 * 60,
                    end: 31 * 60,
                    isPublic: false
                ),
                resolvedCategory: nil
            )
        ], to: target, calendar: calendar)

        let plans = store.allPlannedBlocks().sorted { $0.startTime < $1.startTime }
        #expect(didApply)
        #expect(plans.count == 2)
        #expect(plans.map(\.title) == ["予定", "睡眠"])
        #expect(plans[1].isPublic == false)
        #expect(refreshes.count == 1)
        #expect(refreshes[0].0 == "plan template batch add")
        #expect(refreshes[0].1 == Set(plans.map(\.id)))
        #expect(refreshes[0].2.count == 2)
    }

    @Test("1件でも既存予定と重なる場合は全件追加しない")
    func conflictRejectsWholeBatch() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        let existing = PlanBlock(
            category: nil,
            title: "既存",
            startTime: try date(2026, 9, 3, 9, 30),
            endTime: try date(2026, 9, 3, 10, 30)
        )
        context.insert(existing)
        try context.save()
        var refreshCount = 0
        let store = PlanStore(
            modelContext: context,
            clock: MutableTestClock(now: now),
            requestRefresh: { _, _, _ in refreshCount += 1 }
        )

        let didApply = store.applyTemplates([
            .init(
                snapshot: snapshot(title: "衝突", start: 9 * 60, end: 10 * 60),
                resolvedCategory: nil
            ),
            .init(
                snapshot: snapshot(title: "空き", start: 12 * 60, end: 13 * 60),
                resolvedCategory: nil
            )
        ], to: target, calendar: calendar)

        #expect(!didApply)
        #expect(store.allPlannedBlocks().map(\.title) == ["既存"])
        #expect(refreshCount == 0)
    }

    @Test("今日の時間指定が混ざる場合は終日予定も含め全件追加しない")
    func lockedItemRejectsWholeBatch() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try date(2026, 9, 2, 12, 0)
        let store = PlanStore(
            modelContext: context,
            clock: MutableTestClock(now: now),
            requestRefresh: { _, _, _ in }
        )

        let didApply = store.applyTemplates([
            .init(
                snapshot: snapshot(title: "終日", start: 0, end: 0, isAllDay: true),
                resolvedCategory: nil
            ),
            .init(
                snapshot: snapshot(title: "時間指定", start: 15 * 60, end: 16 * 60),
                resolvedCategory: nil
            )
        ], to: now, calendar: calendar)

        #expect(!didApply)
        #expect(store.allPlannedBlocks().isEmpty)
    }

    @Test("カテゴリ既定の公開相手を適用時点で解決する")
    func resolvesAudienceAtApplicationTime() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try date(2026, 9, 2, 12, 0)
        let target = try date(2026, 9, 3, 12, 0)
        let friend = Friend(displayName: "友達", handle: "@friend", status: .accepted)
        let category = Category(name: "仕事", colorHex: "#112233")
        category.defaultAudienceIncludedFriendIDs = [friend.id]
        context.insert(friend)
        context.insert(category)
        try context.save()
        let store = PlanStore(
            modelContext: context,
            clock: MutableTestClock(now: now),
            requestRefresh: { _, _, _ in }
        )

        #expect(store.applyTemplates([
            .init(
                snapshot: snapshot(title: "会議", start: 9 * 60, end: 10 * 60),
                resolvedCategory: category
            )
        ], to: target, calendar: calendar))

        let plan = try #require(store.allPlannedBlocks().first)
        #expect(plan.category?.id == category.id)
        #expect(plan.audienceFriendIDs == [friend.id])
        #expect(plan.audienceSource == .categoryDefaultSnapshot)
        #expect(plan.hasAudienceSnapshot)
    }

    private func snapshot(
        title: String,
        start: Int,
        end: Int,
        isAllDay: Bool = false,
        isPublic: Bool = true
    ) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title,
            categoryID: nil,
            startMinute: start,
            endMinute: end,
            isAllDay: isAllDay,
            isImportant: false,
            note: nil,
            isPublic: isPublic
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

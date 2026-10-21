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

    @Test("部分置換は前後を残しメモと公開相手を引き継ぐ")
    func partialReplacementPreservesMetadata() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = try date(2026, 9, 3, 12, 0)
        let existing = PlanBlock(category: nil, title: "元の予定", startTime: try date(2026, 9, 3, 9, 0),
                                 endTime: try date(2026, 9, 3, 12, 0), isImportant: true, note: "残すメモ", isPublic: false)
        existing.audienceFriendIDs = [UUID()]
        existing.hasAudienceSnapshot = true
        let audience = existing.audienceFriendIDs
        context.insert(existing)
        try context.save()
        var refreshes = 0
        var changedIDs: Set<UUID> = []
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: try date(2026, 9, 2, 12, 0)),
                              requestRefresh: { _, ids, _ in refreshes += 1; changedIDs = ids })
        let apps: [PlanStore.TemplateApplication] = [.init(snapshot: snapshot(title: "新規", start: 600, end: 660), resolvedCategory: nil)]
        let preview = try #require(store.templateReplacementPreview(apps, to: target, mode: .keepRemainders, calendar: calendar))
        #expect(store.allPlannedBlocks().count == 1) // preview does not mutate
        #expect(store.applyTemplates(apps, to: target, calendar: calendar, approvedReplacement: preview))
        let plans = store.allPlannedBlocks().sorted { $0.startTime < $1.startTime }
        #expect(plans.count == 3)
        #expect(plans[0].id == existing.id)
        #expect(plans[0].endTime == (try date(2026, 9, 3, 10, 0)))
        #expect(plans[2].startTime == (try date(2026, 9, 3, 11, 0)))
        for plan in [plans[0], plans[2]] {
            #expect(plan.title == "元の予定" && plan.note == "残すメモ")
            #expect(plan.isImportant && !plan.isPublic && plan.hasAudienceSnapshot)
            #expect(plan.audienceFriendIDs == audience)
        }
        #expect(refreshes == 1 && changedIDs == Set(plans.map(\.id)))
    }

    @Test("確認後に既存予定が変われば何も置換せず再確認を要求")
    func rejectsStaleApproval() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = try date(2026, 9, 3, 12, 0)
        let existing = PlanBlock(category: nil, title: "既存", startTime: try date(2026, 9, 3, 9, 0), endTime: try date(2026, 9, 3, 12, 0))
        context.insert(existing)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: try date(2026, 9, 2, 12, 0)), requestRefresh: { _, _, _ in })
        let apps: [PlanStore.TemplateApplication] = [.init(snapshot: snapshot(title: "新規", start: 600, end: 660), resolvedCategory: nil)]
        let preview = try #require(store.templateReplacementPreview(apps, to: target, mode: .replaceWholePlans, calendar: calendar))
        existing.endTime = try date(2026, 9, 3, 13, 0)
        try context.save()
        #expect(!store.applyTemplates(apps, to: target, calendar: calendar, approvedReplacement: preview))
        #expect(store.allPlannedBlocks().count == 1)
        let fresh = try #require(store.templateReplacementPreview(apps, to: target, mode: .replaceWholePlans, calendar: calendar))
        #expect(store.applyTemplates(apps, to: target, calendar: calendar, approvedReplacement: fresh))
        #expect(store.allPlannedBlocks().map(\.title) == ["新規"])
    }

    @Test("今日から続く予定と外部予定は置換不可、終日は保持")
    func protectsLockedExternalAndAllDay() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = try date(2026, 9, 3, 12, 0)
        let existing = PlanBlock(category: nil, title: "今日から", startTime: try date(2026, 9, 2, 23, 0), endTime: try date(2026, 9, 3, 12, 0))
        context.insert(existing)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: try date(2026, 9, 2, 12, 0)), requestRefresh: { _, _, _ in })
        let apps: [PlanStore.TemplateApplication] = [.init(snapshot: snapshot(title: "新規", start: 600, end: 660), resolvedCategory: nil)]
        #expect(store.templateReplacementPreview(apps, to: target, mode: .keepRemainders, calendar: calendar) == nil)
        existing.startTime = try date(2026, 9, 3, 9, 0)
        existing.sourceEventID = "external"
        try context.save()
        #expect(store.templateReplacementPreview(apps, to: target, mode: .replaceWholePlans, calendar: calendar) == nil)
        existing.isAllDay = true
        try context.save()
        #expect(store.applyTemplates(apps, to: target, calendar: calendar))
        #expect(store.allPlannedBlocks().count == 2)
    }

    @Test("置換プレビューは予定のカテゴリ表示を保持し、確認後の色変更も再確認する")
    func replacementApprovalIncludesAppearance() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "仕事", colorHex: "#7E57C2", icon: "laptopcomputer")
        context.insert(category)
        let target = try date(2026, 9, 3, 0, 0)
        let existing = PlanBlock(category: category, title: "作業", startTime: try date(2026, 9, 3, 9, 0),
                                 endTime: try date(2026, 9, 3, 12, 0))
        context.insert(existing)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: try date(2026, 9, 2, 12, 0)), requestRefresh: { _, _, _ in })
        let apps: [PlanStore.TemplateApplication] = [.init(snapshot: snapshot(title: "休憩", start: 600, end: 660), resolvedCategory: nil)]
        let partial = try #require(store.templateReplacementPreview(apps, to: target, mode: .keepRemainders, calendar: calendar))
        let change = try #require(partial.changes.first)
        #expect(change.categoryName == "仕事" && change.colorHex == "#7E57C2" && change.icon == "laptopcomputer")
        let whole = PlanTemplateReplacement(mode: .replaceWholePlans, changes: partial.changes.map(\.removingEntirePlan))
        #expect(whole == store.templateReplacementPreview(apps, to: target, mode: .replaceWholePlans, calendar: calendar))
        category.colorHex = "#FF8800"
        try context.save()
        #expect(!store.applyTemplates(apps, to: target, calendar: calendar, approvedReplacement: whole))
        #expect(store.allPlannedBlocks().count == 1)
    }

    @Test("一日プリセットは二つの予定を置換し、重ならない予定と終日予定を保持する")
    func dayPresetReplacesMultiplePlans() throws {
        for mode in PlanTemplateReplacementMode.allCases {
            let container = try TestModelContainer.make()
            let context = container.mainContext
            let target = try date(2026, 9, 3, 0, 0)
            for (title, start, end) in [("作業", 9, 12), ("会議", 13, 16), ("夕食", 18, 19)] {
                context.insert(PlanBlock(category: nil, title: title, startTime: try date(2026, 9, 3, start, 0),
                                         endTime: try date(2026, 9, 3, end, 0)))
            }
            try context.save()
            let store = PlanStore(modelContext: context, clock: MutableTestClock(now: try date(2026, 9, 2, 12, 0)), requestRefresh: { _, _, _ in })
            let apps = [snapshot(title: "勉強", start: 600, end: 660), snapshot(title: "運動", start: 840, end: 900),
                        snapshot(title: "学習日", start: 0, end: 1440, isAllDay: true)].map {
                PlanStore.TemplateApplication(snapshot: $0, resolvedCategory: nil)
            }
            let preview = try #require(store.templateReplacementPreview(apps, to: target, mode: mode, calendar: calendar))
            #expect(preview.changes.map(\.title) == ["作業", "会議"])
            #expect(store.applyTemplates(apps, to: target, calendar: calendar, approvedReplacement: preview))
            let plans = store.allPlannedBlocks()
            #expect(plans.count == (mode == .keepRemainders ? 8 : 4))
            #expect(plans.filter { $0.title == "学習日" && $0.isAllDay }.count == 1)
            #expect(plans.filter { $0.title == "夕食" }.count == 1)
        }
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

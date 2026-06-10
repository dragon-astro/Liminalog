import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("FriendSharedRecordReconcilePolicy")
struct FriendSharedRecordReconcilePolicyTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("新規・更新・削除を sourceID で振り分ける")
    func plansInsertUpdateDelete() {
        let kept = UUID()
        let updated = UUID()
        let removed = UUID()
        let added = UUID()

        let plan = FriendSharedRecordReconcilePolicy.plan(
            existing: [
                .init(sourceID: kept, updatedAt: base),
                .init(sourceID: updated, updatedAt: base),
                .init(sourceID: removed, updatedAt: base)
            ],
            incoming: [
                .init(sourceID: kept, updatedAt: base),
                .init(sourceID: updated, updatedAt: base.addingTimeInterval(60)),
                .init(sourceID: added, updatedAt: base)
            ]
        )

        #expect(plan.insertSourceIDs == [added])
        #expect(plan.updateSourceIDs == [updated])
        #expect(plan.deleteSourceIDs == [removed])
    }

    @Test("受信側の updatedAt が古い場合は上書きしない")
    func staleIncomingDoesNotUpdate() {
        let id = UUID()
        let plan = FriendSharedRecordReconcilePolicy.plan(
            existing: [.init(sourceID: id, updatedAt: base)],
            incoming: [.init(sourceID: id, updatedAt: base.addingTimeInterval(-60))]
        )

        #expect(plan.insertSourceIDs.isEmpty)
        #expect(plan.updateSourceIDs.isEmpty)
        #expect(plan.deleteSourceIDs.isEmpty)
    }

    @Test("重複した sourceID は最初の1件だけ反映する")
    func duplicateIncomingIsIgnored() {
        let id = UUID()
        let plan = FriendSharedRecordReconcilePolicy.plan(
            existing: [],
            incoming: [
                .init(sourceID: id, updatedAt: base),
                .init(sourceID: id, updatedAt: base.addingTimeInterval(60))
            ]
        )

        #expect(plan.insertSourceIDs == [id])
        #expect(plan.updateSourceIDs.isEmpty)
    }
}

@MainActor
@Suite("FriendSharedRecordStore")
struct FriendSharedRecordStoreTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func makePlanSnapshot(
        id: UUID = UUID(),
        title: String = "予定",
        start: TimeInterval,
        end: TimeInterval,
        updatedAt: TimeInterval = 0
    ) -> FriendSharedPlanSnapshot {
        FriendSharedPlanSnapshot(
            id: id,
            title: title,
            startTime: base.addingTimeInterval(start),
            endTime: base.addingTimeInterval(end),
            updatedAt: base.addingTimeInterval(updatedAt)
        )
    }

    private func makeActivitySnapshot(
        id: UUID = UUID(),
        title: String = "実績",
        start: TimeInterval,
        end: TimeInterval
    ) -> FriendSharedActivitySnapshot {
        FriendSharedActivitySnapshot(
            id: id,
            title: title,
            startTime: base.addingTimeInterval(start),
            endTime: base.addingTimeInterval(end),
            updatedAt: base
        )
    }

    @Test("reconcile で行が作られ、再受信で更新・削除される")
    func reconcileRoundTrip() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendID = UUID()
        let keptID = UUID()
        let removedID = UUID()

        store.reconcile(
            friendID: friendID,
            plans: [
                makePlanSnapshot(id: keptID, title: "朝活", start: 0, end: 3600),
                makePlanSnapshot(id: removedID, title: "消える予定", start: 7200, end: 10800)
            ],
            activities: [makeActivitySnapshot(start: 0, end: 1800)]
        )
        try container.mainContext.save()

        let allRange = base.addingTimeInterval(-86_400)..<base.addingTimeInterval(86_400)
        #expect(store.plans(friendID: friendID, overlapping: allRange).count == 2)
        #expect(store.chapters(friendID: friendID, overlapping: allRange).count == 1)

        // 再受信: 1件はタイトル更新、1件は消えている
        store.reconcile(
            friendID: friendID,
            plans: [makePlanSnapshot(id: keptID, title: "朝活(更新)", start: 0, end: 3600, updatedAt: 60)],
            activities: []
        )
        try container.mainContext.save()

        let plans = store.plans(friendID: friendID, overlapping: allRange)
        #expect(plans.count == 1)
        #expect(plans.first?.title == "朝活(更新)")
        #expect(store.chapters(friendID: friendID, overlapping: allRange).isEmpty)
    }

    @Test("範囲クエリは重なる行だけを返す")
    func rangeQueryReturnsOverlappingOnly() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendID = UUID()
        let otherFriendID = UUID()

        store.reconcile(
            friendID: friendID,
            plans: [
                makePlanSnapshot(title: "範囲内", start: 3600, end: 7200),
                makePlanSnapshot(title: "範囲をまたぐ", start: -3600, end: 3600),
                makePlanSnapshot(title: "範囲外(過去)", start: -7200, end: -3600),
                makePlanSnapshot(title: "範囲外(未来)", start: 86_400, end: 90_000)
            ],
            activities: []
        )
        store.reconcile(
            friendID: otherFriendID,
            plans: [makePlanSnapshot(title: "他人の予定", start: 3600, end: 7200)],
            activities: []
        )
        try container.mainContext.save()

        let range = base..<base.addingTimeInterval(10_800)
        let titles = store.plans(friendID: friendID, overlapping: range).map(\.title)
        #expect(titles == ["範囲をまたぐ", "範囲内"])
    }

    @Test("deleteAll と purge で行が消える")
    func deleteAllAndPurge() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendA = UUID()
        let friendB = UUID()
        let allRange = base.addingTimeInterval(-86_400)..<base.addingTimeInterval(86_400)

        store.reconcile(
            friendID: friendA,
            plans: [makePlanSnapshot(start: 0, end: 3600)],
            activities: [makeActivitySnapshot(start: 0, end: 1800)]
        )
        store.reconcile(
            friendID: friendB,
            plans: [makePlanSnapshot(start: 0, end: 3600)],
            activities: []
        )
        try container.mainContext.save()

        store.deleteAll(friendID: friendA)
        try container.mainContext.save()
        #expect(store.plans(friendID: friendA, overlapping: allRange).isEmpty)
        #expect(store.chapters(friendID: friendA, overlapping: allRange).isEmpty)
        #expect(store.plans(friendID: friendB, overlapping: allRange).count == 1)

        store.purgeRecords(notBelongingTo: [])
        try container.mainContext.save()
        #expect(store.plans(friendID: friendB, overlapping: allRange).isEmpty)
    }

    @Test("タイトル部分一致検索と空状態判定")
    func searchPlansAndEmptyState() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendID = UUID()
        #expect(!store.hasAnyPlans(friendID: friendID))

        store.reconcile(
            friendID: friendID,
            plans: [
                makePlanSnapshot(title: "ゼミ準備", start: 0, end: 3600),
                makePlanSnapshot(title: "レポート仕上げ", start: 7200, end: 10_800),
                makePlanSnapshot(title: "買い物", start: 14_400, end: 18_000)
            ],
            activities: []
        )
        try container.mainContext.save()

        #expect(store.hasAnyPlans(friendID: friendID))
        #expect(store.searchPlans(friendID: friendID, titleContains: "ゼミ").map(\.title) == ["ゼミ準備"])
        #expect(store.searchPlans(friendID: friendID, titleContains: "存在しない").isEmpty)
        #expect(store.searchPlans(friendID: friendID, titleContains: "").isEmpty)
    }

    @Test("ゾーン差分の applyChanges で upsert と削除が反映される")
    func applyZoneChangesUpsertAndDelete() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendID = UUID()
        let keptID = UUID()
        let removedID = UUID()
        let allRange = base.addingTimeInterval(-86_400)..<base.addingTimeInterval(86_400)

        store.reconcile(
            friendID: friendID,
            plans: [
                makePlanSnapshot(id: keptID, title: "元の予定", start: 0, end: 3600),
                makePlanSnapshot(id: removedID, title: "消える予定", start: 7200, end: 10_800)
            ],
            activities: []
        )
        try container.mainContext.save()

        // 差分: keptID はタイトル更新、removedID は削除、新規1件追加
        let addedID = UUID()
        store.applyChanges(
            friendID: friendID,
            upsertPlans: [
                makePlanSnapshot(id: keptID, title: "更新された予定", start: 0, end: 3600, updatedAt: 60),
                makePlanSnapshot(id: addedID, title: "追加された予定", start: 14_400, end: 18_000)
            ],
            upsertChapters: [makeActivitySnapshot(title: "追加された実績", start: 0, end: 1800)],
            deletePlanSourceIDs: [removedID],
            deleteChapterSourceIDs: []
        )
        try container.mainContext.save()

        let titles = store.plans(friendID: friendID, overlapping: allRange).map(\.title)
        #expect(titles == ["更新された予定", "追加された予定"])
        #expect(store.chapters(friendID: friendID, overlapping: allRange).map(\.title) == ["追加された実績"])
    }

    @Test("clearCachedShare で行キャッシュも消える")
    func clearCachedShareDeletesRows() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friend = Friend(displayName: "Mika")
        context.insert(friend)
        try context.save()

        let store = FriendSharedRecordStore(modelContext: context)
        store.reconcile(
            friendID: friend.id,
            plans: [makePlanSnapshot(title: "共有予定", start: 0, end: 3600)],
            activities: [makeActivitySnapshot(title: "共有実績", start: 0, end: 1800)]
        )
        try context.save()

        let allRange = base.addingTimeInterval(-86_400)..<base.addingTimeInterval(86_400)
        #expect(store.plans(friendID: friend.id, overlapping: allRange).count == 1)

        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
        try context.save()
        #expect(store.plans(friendID: friend.id, overlapping: allRange).isEmpty)
        #expect(store.chapters(friendID: friend.id, overlapping: allRange).isEmpty)
    }
}

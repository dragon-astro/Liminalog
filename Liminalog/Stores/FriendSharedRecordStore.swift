import Foundation
import SwiftData

/// 友達共有の個別行キャッシュ（`FriendSharedPlanRecord` / `FriendSharedChapterRecord`）の読み書き（docs/20 §2.2-2.3）。
/// - 書き込み: 受信スナップショットを `FriendSharedRecordReconcilePolicy` で突合して反映する。
/// - 読み出し: カレンダー等が「表示範囲だけ」を fetch するための範囲クエリ。
/// 呼び出し側で `modelContext.save()` すること（既存の塊JSON反映と同一トランザクションに乗せる）。
@MainActor
struct FriendSharedRecordStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 書き込み（受信反映）

    /// 受信した全量スナップショットを正として、友達1人分の行キャッシュを一致させる。
    func reconcile(
        friendID: UUID,
        plans: [FriendSharedPlanSnapshot],
        activities: [FriendSharedActivitySnapshot]
    ) {
        reconcilePlans(friendID: friendID, snapshots: plans)
        reconcileChapters(friendID: friendID, snapshots: activities)
    }

    func reconcilePlans(friendID: UUID, snapshots: [FriendSharedPlanSnapshot]) {
        let existing = (try? modelContext.fetch(
            FetchDescriptor<FriendSharedPlanRecord>(
                predicate: #Predicate { $0.friendID == friendID }
            )
        )) ?? []
        let plan = FriendSharedRecordReconcilePolicy.plan(
            existing: existing.map { .init(sourceID: $0.sourceID, updatedAt: $0.updatedAt) },
            incoming: snapshots.map { .init(sourceID: $0.id, updatedAt: $0.updatedAt) }
        )
        let existingBySourceID = Dictionary(
            existing.map { ($0.sourceID, $0) },
            uniquingKeysWith: { record, _ in record }
        )
        let snapshotsBySourceID = Dictionary(
            snapshots.map { ($0.id, $0) },
            uniquingKeysWith: { snapshot, _ in snapshot }
        )

        for sourceID in plan.insertSourceIDs {
            guard let snapshot = snapshotsBySourceID[sourceID] else { continue }
            modelContext.insert(FriendSharedPlanRecord(friendID: friendID, snapshot: snapshot))
        }
        for sourceID in plan.updateSourceIDs {
            guard let record = existingBySourceID[sourceID],
                  let snapshot = snapshotsBySourceID[sourceID]
            else { continue }
            record.apply(snapshot)
        }
        for sourceID in plan.deleteSourceIDs {
            guard let record = existingBySourceID[sourceID] else { continue }
            modelContext.delete(record)
        }
    }

    func reconcileChapters(friendID: UUID, snapshots: [FriendSharedActivitySnapshot]) {
        let existing = (try? modelContext.fetch(
            FetchDescriptor<FriendSharedChapterRecord>(
                predicate: #Predicate { $0.friendID == friendID }
            )
        )) ?? []
        let plan = FriendSharedRecordReconcilePolicy.plan(
            existing: existing.map { .init(sourceID: $0.sourceID, updatedAt: $0.updatedAt) },
            incoming: snapshots.map { .init(sourceID: $0.id, updatedAt: $0.updatedAt) }
        )
        let existingBySourceID = Dictionary(
            existing.map { ($0.sourceID, $0) },
            uniquingKeysWith: { record, _ in record }
        )
        let snapshotsBySourceID = Dictionary(
            snapshots.map { ($0.id, $0) },
            uniquingKeysWith: { snapshot, _ in snapshot }
        )

        for sourceID in plan.insertSourceIDs {
            guard let snapshot = snapshotsBySourceID[sourceID] else { continue }
            modelContext.insert(FriendSharedChapterRecord(friendID: friendID, snapshot: snapshot))
        }
        for sourceID in plan.updateSourceIDs {
            guard let record = existingBySourceID[sourceID],
                  let snapshot = snapshotsBySourceID[sourceID]
            else { continue }
            record.apply(snapshot)
        }
        for sourceID in plan.deleteSourceIDs {
            guard let record = existingBySourceID[sourceID] else { continue }
            modelContext.delete(record)
        }
    }

    /// 友達1人分の行キャッシュを全削除する（友達削除・共有解除時）。
    func deleteAll(friendID: UUID) {
        try? modelContext.delete(
            model: FriendSharedPlanRecord.self,
            where: #Predicate { $0.friendID == friendID }
        )
        try? modelContext.delete(
            model: FriendSharedChapterRecord.self,
            where: #Predicate { $0.friendID == friendID }
        )
    }

    /// 有効な友達ID集合に属さない行を一括削除する（友達削除の取りこぼし回収）。
    /// - Returns: 削除した行数。
    @discardableResult
    func purgeRecords(notBelongingTo validFriendIDs: Set<UUID>) -> Int {
        var deleted = 0
        let orphanPlans = (try? modelContext.fetch(FetchDescriptor<FriendSharedPlanRecord>())) ?? []
        for record in orphanPlans where !validFriendIDs.contains(record.friendID) {
            modelContext.delete(record)
            deleted += 1
        }
        let orphanChapters = (try? modelContext.fetch(FetchDescriptor<FriendSharedChapterRecord>())) ?? []
        for record in orphanChapters where !validFriendIDs.contains(record.friendID) {
            modelContext.delete(record)
            deleted += 1
        }
        return deleted
    }

    // MARK: - 読み出し（範囲クエリ）

    /// 指定範囲に重なる友達の予定。カレンダーのグリッド範囲・デイビューの当日範囲で使う。
    func plans(friendID: UUID, overlapping range: Range<Date>) -> [FriendSharedPlanSnapshot] {
        let start = range.lowerBound
        let end = range.upperBound
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate {
                $0.friendID == friendID && $0.startTime < end && $0.endTime > start
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        descriptor.includePendingChanges = true
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.snapshot)
    }

    /// 指定範囲に重なる友達の実績。
    func chapters(friendID: UUID, overlapping range: Range<Date>) -> [FriendSharedActivitySnapshot] {
        let start = range.lowerBound
        let end = range.upperBound
        var descriptor = FetchDescriptor<FriendSharedChapterRecord>(
            predicate: #Predicate {
                $0.friendID == friendID && $0.startTime < end && $0.endTime > start
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        descriptor.includePendingChanges = true
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.snapshot)
    }
}

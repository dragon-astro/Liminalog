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
    @discardableResult
    func reconcile(
        friendID: UUID,
        plans: [FriendSharedPlanSnapshot],
        activities: [FriendSharedActivitySnapshot]
    ) -> FriendSharedRecordChangeImpact {
        reconcilePlans(friendID: friendID, snapshots: plans)
        reconcileChapters(friendID: friendID, snapshots: activities)
        return .fullReload
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

    /// ゾーン差分（docs/20 §2.2）の適用。変更分のみ upsert / 削除分のみ delete する。
    @discardableResult
    func applyChanges(
        friendID: UUID,
        upsertPlans: [FriendSharedPlanSnapshot],
        upsertChapters: [FriendSharedActivitySnapshot],
        deletePlanSourceIDs: Set<UUID>,
        deleteChapterSourceIDs: Set<UUID>
    ) -> FriendSharedRecordChangeImpact {
        var impact = FriendSharedRecordChangeImpact()
        upsertPlans.forEach { impact.add(start: $0.startTime, end: $0.endTime) }
        upsertChapters.forEach { impact.add(start: $0.startTime, end: $0.endTime) }
        for snapshot in upsertPlans {
            upsertPlan(friendID: friendID, snapshot: snapshot)
        }
        for snapshot in upsertChapters {
            upsertChapter(friendID: friendID, snapshot: snapshot)
        }
        for sourceID in deletePlanSourceIDs {
            if let interval = planInterval(friendID: friendID, sourceID: sourceID) {
                impact.add(interval)
            }
            deletePlan(friendID: friendID, sourceID: sourceID)
        }
        for sourceID in deleteChapterSourceIDs {
            if let interval = chapterInterval(friendID: friendID, sourceID: sourceID) {
                impact.add(interval)
            }
            deleteChapter(friendID: friendID, sourceID: sourceID)
        }
        return impact
    }

    private func upsertPlan(friendID: UUID, snapshot: FriendSharedPlanSnapshot) {
        let sourceID = snapshot.id
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(FriendSharedPlanRecord(friendID: friendID, snapshot: snapshot))
        }
    }

    private func upsertChapter(friendID: UUID, snapshot: FriendSharedActivitySnapshot) {
        let sourceID = snapshot.id
        var descriptor = FetchDescriptor<FriendSharedChapterRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(FriendSharedChapterRecord(friendID: friendID, snapshot: snapshot))
        }
    }

    private func deletePlan(friendID: UUID, sourceID: UUID) {
        let descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        for record in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(record)
        }
    }

    private func deleteChapter(friendID: UUID, sourceID: UUID) {
        let descriptor = FetchDescriptor<FriendSharedChapterRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        for record in (try? modelContext.fetch(descriptor)) ?? [] {
            modelContext.delete(record)
        }
    }

    private func planInterval(friendID: UUID, sourceID: UUID) -> DateInterval? {
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return nil }
        return FriendSharedRecordChangeImpact.interval(start: record.startTime, end: record.endTime)
    }

    private func chapterInterval(friendID: UUID, sourceID: UUID) -> DateInterval? {
        var descriptor = FetchDescriptor<FriendSharedChapterRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return nil }
        return FriendSharedRecordChangeImpact.interval(start: record.startTime, end: record.endTime)
    }

    /// 友達の重複統合時に、行キャッシュを勝者の friendID へ付け替える（sourceID重複は勝者優先で破棄）。
    func repointRows(from loserFriendID: UUID, to winnerFriendID: UUID) {
        let winnerPlanSourceIDs = Set((
            (try? modelContext.fetch(
                FetchDescriptor<FriendSharedPlanRecord>(
                    predicate: #Predicate { $0.friendID == winnerFriendID }
                )
            )) ?? []
        ).map(\.sourceID))
        let loserPlans = (try? modelContext.fetch(
            FetchDescriptor<FriendSharedPlanRecord>(
                predicate: #Predicate { $0.friendID == loserFriendID }
            )
        )) ?? []
        for record in loserPlans {
            if winnerPlanSourceIDs.contains(record.sourceID) {
                modelContext.delete(record)
            } else {
                record.friendID = winnerFriendID
            }
        }

        let winnerChapterSourceIDs = Set((
            (try? modelContext.fetch(
                FetchDescriptor<FriendSharedChapterRecord>(
                    predicate: #Predicate { $0.friendID == winnerFriendID }
                )
            )) ?? []
        ).map(\.sourceID))
        let loserChapters = (try? modelContext.fetch(
            FetchDescriptor<FriendSharedChapterRecord>(
                predicate: #Predicate { $0.friendID == loserFriendID }
            )
        )) ?? []
        for record in loserChapters {
            if winnerChapterSourceIDs.contains(record.sourceID) {
                modelContext.delete(record)
            } else {
                record.friendID = winnerFriendID
            }
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

    /// 友達の共有予定が1件でもあるか（検索シートの空状態判定用）。
    func hasAnyPlans(friendID: UUID) -> Bool {
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate { $0.friendID == friendID }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// タイトル部分一致の共有予定検索（検索シート用）。
    func searchPlans(friendID: UUID, titleContains query: String) -> [FriendSharedPlanSnapshot] {
        guard !query.isEmpty else { return [] }
        let descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate {
                $0.friendID == friendID && $0.title.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
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

struct FriendSharedRecordChangeImpact: Equatable {
    var requiresFullReload = false
    private(set) var affectedIntervals: [DateInterval] = []

    static let fullReload = FriendSharedRecordChangeImpact(requiresFullReload: true)

    mutating func add(start: Date, end: Date) {
        guard let interval = Self.interval(start: start, end: end) else { return }
        add(interval)
    }

    mutating func add(_ interval: DateInterval) {
        affectedIntervals.append(interval)
    }

    mutating func merge(_ other: FriendSharedRecordChangeImpact) {
        requiresFullReload = requiresFullReload || other.requiresFullReload
        affectedIntervals.append(contentsOf: other.affectedIntervals)
    }

    static func interval(start: Date, end: Date) -> DateInterval? {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite
        else { return nil }
        if end > start {
            return DateInterval(start: start, end: end)
        }
        return DateInterval(start: start, duration: 1)
    }
}

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
        activities: [FriendSharedActivitySnapshot],
        scores: [FriendSharedDailyScoreSnapshot] = []
    ) -> FriendSharedRecordChangeImpact {
        reconcilePlans(friendID: friendID, snapshots: plans)
        reconcileChapters(friendID: friendID, snapshots: activities)
        reconcileScores(friendID: friendID, snapshots: scores)
        return .fullReload
    }

    func reconcilePlans(friendID: UUID, snapshots: [FriendSharedPlanSnapshot]) {
        let snapshots = latestPlanSnapshotsBySourceID(snapshots)
        let existing = compactPlanRecords((try? modelContext.fetch(
            FetchDescriptor<FriendSharedPlanRecord>(
                predicate: #Predicate { $0.friendID == friendID }
            )
        )) ?? [])
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
        let snapshots = latestActivitySnapshotsBySourceID(snapshots)
        let existing = compactChapterRecords((try? modelContext.fetch(
            FetchDescriptor<FriendSharedChapterRecord>(
                predicate: #Predicate { $0.friendID == friendID }
            )
        )) ?? [])
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

    func reconcileScores(friendID: UUID, snapshots: [FriendSharedDailyScoreSnapshot]) {
        let snapshots = latestScoreSnapshotsBySourceID(snapshots)
        let existing = compactScoreRecords((try? modelContext.fetch(
            FetchDescriptor<FriendSharedScoreRecord>(
                predicate: #Predicate { $0.friendID == friendID }
            )
        )) ?? [])
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
            modelContext.insert(FriendSharedScoreRecord(friendID: friendID, snapshot: snapshot))
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
        upsertScores: [FriendSharedDailyScoreSnapshot] = [],
        deletePlanSourceIDs: Set<UUID>,
        deleteChapterSourceIDs: Set<UUID>,
        deleteScoreSourceIDs: Set<UUID> = []
    ) -> FriendSharedRecordChangeImpact {
        let upsertPlans = latestPlanSnapshotsBySourceID(upsertPlans)
        let upsertChapters = latestActivitySnapshotsBySourceID(upsertChapters)
        let upsertScores = latestScoreSnapshotsBySourceID(upsertScores)
        var impact = FriendSharedRecordChangeImpact()
        upsertPlans.forEach { impact.add(start: $0.startTime, end: $0.endTime) }
        upsertChapters.forEach { impact.add(start: $0.startTime, end: $0.endTime) }
        upsertScores.forEach { score in
            let end = Calendar.japanese.date(byAdding: .day, value: 1, to: score.dayStart) ?? score.dayStart
            impact.add(start: score.dayStart, end: end)
        }
        for snapshot in upsertPlans {
            upsertPlan(friendID: friendID, snapshot: snapshot)
        }
        for snapshot in upsertChapters {
            upsertChapter(friendID: friendID, snapshot: snapshot)
        }
        for snapshot in upsertScores {
            upsertScore(friendID: friendID, snapshot: snapshot)
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
        for sourceID in deleteScoreSourceIDs {
            if let interval = scoreInterval(friendID: friendID, sourceID: sourceID) {
                impact.add(interval)
            }
            deleteScore(friendID: friendID, sourceID: sourceID)
        }
        if purgeDuplicateRecords() > 0 {
            impact.requiresFullReload = true
        }
        return impact
    }

    private func upsertPlan(friendID: UUID, snapshot: FriendSharedPlanSnapshot) {
        let sourceID = snapshot.id
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.includePendingChanges = true
        if let existing = compactPlanRecords((try? modelContext.fetch(descriptor)) ?? []).first {
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
        descriptor.includePendingChanges = true
        if let existing = compactChapterRecords((try? modelContext.fetch(descriptor)) ?? []).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(FriendSharedChapterRecord(friendID: friendID, snapshot: snapshot))
        }
    }

    private func upsertScore(friendID: UUID, snapshot: FriendSharedDailyScoreSnapshot) {
        let sourceID = snapshot.id
        var descriptor = FetchDescriptor<FriendSharedScoreRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.includePendingChanges = true
        if let existing = compactScoreRecords((try? modelContext.fetch(descriptor)) ?? []).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(FriendSharedScoreRecord(friendID: friendID, snapshot: snapshot))
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

    private func deleteScore(friendID: UUID, sourceID: UUID) {
        let descriptor = FetchDescriptor<FriendSharedScoreRecord>(
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

    private func scoreInterval(friendID: UUID, sourceID: UUID) -> DateInterval? {
        var descriptor = FetchDescriptor<FriendSharedScoreRecord>(
            predicate: #Predicate { $0.friendID == friendID && $0.sourceID == sourceID }
        )
        descriptor.fetchLimit = 1
        guard let record = (try? modelContext.fetch(descriptor))?.first else { return nil }
        let end = Calendar.japanese.date(byAdding: .day, value: 1, to: record.dayStart) ?? record.dayStart
        return DateInterval(start: record.dayStart, end: end)
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

        let winnerScoreSourceIDs = Set((
            (try? modelContext.fetch(
                FetchDescriptor<FriendSharedScoreRecord>(
                    predicate: #Predicate { $0.friendID == winnerFriendID }
                )
            )) ?? []
        ).map(\.sourceID))
        let loserScores = (try? modelContext.fetch(
            FetchDescriptor<FriendSharedScoreRecord>(
                predicate: #Predicate { $0.friendID == loserFriendID }
            )
        )) ?? []
        for record in loserScores {
            if winnerScoreSourceIDs.contains(record.sourceID) {
                modelContext.delete(record)
            } else {
                record.friendID = winnerFriendID
            }
        }
        purgeDuplicateRecords()
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
        try? modelContext.delete(
            model: FriendSharedScoreRecord.self,
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
        let orphanScores = (try? modelContext.fetch(FetchDescriptor<FriendSharedScoreRecord>())) ?? []
        for record in orphanScores where !validFriendIDs.contains(record.friendID) {
            modelContext.delete(record)
            deleted += 1
        }
        return deleted
    }

    /// 既存ストアに残った同一 friendID/sourceID の重複行を1件へ畳む。
    /// LocalCache の派生データなので、最新 `updatedAt` の行を残し、古い重複を削除する。
    @discardableResult
    func purgeDuplicateRecords() -> Int {
        var deleted = 0
        deleted += compactPlanRecordsWithCount((try? modelContext.fetch(FetchDescriptor<FriendSharedPlanRecord>())) ?? []).deletedCount
        deleted += compactChapterRecordsWithCount((try? modelContext.fetch(FetchDescriptor<FriendSharedChapterRecord>())) ?? []).deletedCount
        deleted += compactScoreRecordsWithCount((try? modelContext.fetch(FetchDescriptor<FriendSharedScoreRecord>())) ?? []).deletedCount
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
        return uniquePlanSnapshots(from: (try? modelContext.fetch(descriptor)) ?? [])
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
        var descriptor = FetchDescriptor<FriendSharedPlanRecord>(
            predicate: #Predicate {
                $0.friendID == friendID && $0.title.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return uniquePlanSnapshots(from: (try? modelContext.fetch(descriptor)) ?? [])
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
        return uniqueChapterSnapshots(from: (try? modelContext.fetch(descriptor)) ?? [])
    }

    /// 指定範囲の日別スコア。友達カレンダーはこの軽量キャッシュを読むだけにする。
    func scores(friendID: UUID, overlapping range: Range<Date>) -> [FriendSharedDailyScoreSnapshot] {
        let start = range.lowerBound
        let end = range.upperBound
        var descriptor = FetchDescriptor<FriendSharedScoreRecord>(
            predicate: #Predicate {
                $0.friendID == friendID && $0.dayStart >= start && $0.dayStart < end
            },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        descriptor.includePendingChanges = true
        return uniqueScoreSnapshots(from: (try? modelContext.fetch(descriptor)) ?? [])
    }

    private func compactPlanRecords(_ records: [FriendSharedPlanRecord]) -> [FriendSharedPlanRecord] {
        compactPlanRecordsWithCount(records).kept
    }

    private func compactPlanRecordsWithCount(_ records: [FriendSharedPlanRecord]) -> (kept: [FriendSharedPlanRecord], deletedCount: Int) {
        var keptByKey: [FriendSharedRecordKey: FriendSharedPlanRecord] = [:]
        var deletedCount = 0
        for record in records {
            let key = FriendSharedRecordKey(friendID: record.friendID, sourceID: record.sourceID)
            if let kept = keptByKey[key] {
                if record.updatedAt > kept.updatedAt {
                    modelContext.delete(kept)
                    keptByKey[key] = record
                } else {
                    modelContext.delete(record)
                }
                deletedCount += 1
            } else {
                keptByKey[key] = record
            }
        }
        return (Array(keptByKey.values), deletedCount)
    }

    private func compactChapterRecords(_ records: [FriendSharedChapterRecord]) -> [FriendSharedChapterRecord] {
        compactChapterRecordsWithCount(records).kept
    }

    private func compactChapterRecordsWithCount(_ records: [FriendSharedChapterRecord]) -> (kept: [FriendSharedChapterRecord], deletedCount: Int) {
        var keptByKey: [FriendSharedRecordKey: FriendSharedChapterRecord] = [:]
        var deletedCount = 0
        for record in records {
            let key = FriendSharedRecordKey(friendID: record.friendID, sourceID: record.sourceID)
            if let kept = keptByKey[key] {
                if record.updatedAt > kept.updatedAt {
                    modelContext.delete(kept)
                    keptByKey[key] = record
                } else {
                    modelContext.delete(record)
                }
                deletedCount += 1
            } else {
                keptByKey[key] = record
            }
        }
        return (Array(keptByKey.values), deletedCount)
    }

    private func compactScoreRecords(_ records: [FriendSharedScoreRecord]) -> [FriendSharedScoreRecord] {
        compactScoreRecordsWithCount(records).kept
    }

    private func compactScoreRecordsWithCount(_ records: [FriendSharedScoreRecord]) -> (kept: [FriendSharedScoreRecord], deletedCount: Int) {
        var keptByKey: [FriendSharedRecordKey: FriendSharedScoreRecord] = [:]
        var deletedCount = 0
        for record in records {
            let key = FriendSharedRecordKey(friendID: record.friendID, sourceID: record.sourceID)
            if let kept = keptByKey[key] {
                if record.updatedAt > kept.updatedAt {
                    modelContext.delete(kept)
                    keptByKey[key] = record
                } else {
                    modelContext.delete(record)
                }
                deletedCount += 1
            } else {
                keptByKey[key] = record
            }
        }
        return (Array(keptByKey.values), deletedCount)
    }

    private func uniquePlanSnapshots(from records: [FriendSharedPlanRecord]) -> [FriendSharedPlanSnapshot] {
        uniquePlanRecords(records).map(\.snapshot)
    }

    private func uniqueChapterSnapshots(from records: [FriendSharedChapterRecord]) -> [FriendSharedActivitySnapshot] {
        uniqueChapterRecords(records).map(\.snapshot)
    }

    private func uniqueScoreSnapshots(from records: [FriendSharedScoreRecord]) -> [FriendSharedDailyScoreSnapshot] {
        uniqueRecords(records).map(\.snapshot)
    }

    private func uniquePlanRecords(_ records: [FriendSharedPlanRecord]) -> [FriendSharedPlanRecord] {
        let sourceUnique = uniqueRecords(records)
        var keptByDisplayKey: [FriendSharedPlanDisplayKey: FriendSharedPlanRecord] = [:]
        for record in sourceUnique {
            let key = FriendSharedPlanDisplayKey(record: record)
            if let kept = keptByDisplayKey[key], kept.updatedAt >= record.updatedAt {
                continue
            }
            keptByDisplayKey[key] = record
        }
        return sortedRecords(Array(keptByDisplayKey.values))
    }

    private func uniqueChapterRecords(_ records: [FriendSharedChapterRecord]) -> [FriendSharedChapterRecord] {
        let sourceUnique = uniqueRecords(records)
        var keptByDisplayKey: [FriendSharedChapterDisplayKey: FriendSharedChapterRecord] = [:]
        for record in sourceUnique {
            let key = FriendSharedChapterDisplayKey(record: record)
            if let kept = keptByDisplayKey[key], kept.updatedAt >= record.updatedAt {
                continue
            }
            keptByDisplayKey[key] = record
        }
        return sortedRecords(Array(keptByDisplayKey.values))
    }

    private func uniqueRecords<Record: PersistentModel & FriendSharedRecordDeduplicatable>(_ records: [Record]) -> [Record] {
        var keptByKey: [FriendSharedRecordKey: Record] = [:]
        for record in records {
            let key = FriendSharedRecordKey(friendID: record.friendID, sourceID: record.sourceID)
            if let kept = keptByKey[key], kept.updatedAt >= record.updatedAt {
                continue
            }
            keptByKey[key] = record
        }
        return sortedRecords(Array(keptByKey.values))
    }

    private func sortedRecords<Record: FriendSharedRecordDeduplicatable>(_ records: [Record]) -> [Record] {
        records.sorted {
            if $0.startTime == $1.startTime {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.startTime < $1.startTime
        }
    }

    private func latestPlanSnapshotsBySourceID(_ snapshots: [FriendSharedPlanSnapshot]) -> [FriendSharedPlanSnapshot] {
        var keptBySourceID: [UUID: FriendSharedPlanSnapshot] = [:]
        for snapshot in snapshots {
            if let kept = keptBySourceID[snapshot.id], kept.updatedAt >= snapshot.updatedAt {
                continue
            }
            keptBySourceID[snapshot.id] = snapshot
        }
        return keptBySourceID.values.sorted { $0.startTime < $1.startTime }
    }

    private func latestActivitySnapshotsBySourceID(_ snapshots: [FriendSharedActivitySnapshot]) -> [FriendSharedActivitySnapshot] {
        var keptBySourceID: [UUID: FriendSharedActivitySnapshot] = [:]
        for snapshot in snapshots {
            if let kept = keptBySourceID[snapshot.id], kept.updatedAt >= snapshot.updatedAt {
                continue
            }
            keptBySourceID[snapshot.id] = snapshot
        }
        return keptBySourceID.values.sorted { $0.startTime < $1.startTime }
    }

    private func latestScoreSnapshotsBySourceID(_ snapshots: [FriendSharedDailyScoreSnapshot]) -> [FriendSharedDailyScoreSnapshot] {
        var keptBySourceID: [UUID: FriendSharedDailyScoreSnapshot] = [:]
        for snapshot in snapshots {
            if let kept = keptBySourceID[snapshot.id], kept.updatedAt >= snapshot.updatedAt {
                continue
            }
            keptBySourceID[snapshot.id] = snapshot
        }
        return keptBySourceID.values.sorted { $0.dayStart < $1.dayStart }
    }
}

private struct FriendSharedRecordKey: Hashable {
    let friendID: UUID
    let sourceID: UUID
}

private struct FriendSharedPlanDisplayKey: Hashable {
    let friendID: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let categoryTitle: String
    let categoryIconName: String
    let categoryColorHex: String

    init(record: FriendSharedPlanRecord) {
        friendID = record.friendID
        title = record.title
        startTime = record.startTime
        endTime = record.endTime
        isAllDay = record.isAllDay
        categoryTitle = record.categoryTitle
        categoryIconName = record.categoryIconName
        categoryColorHex = record.categoryColorHex
    }
}

private struct FriendSharedChapterDisplayKey: Hashable {
    let friendID: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let categoryTitle: String
    let categoryIconName: String
    let categoryColorHex: String

    init(record: FriendSharedChapterRecord) {
        friendID = record.friendID
        title = record.title
        startTime = record.startTime
        endTime = record.endTime
        categoryTitle = record.categoryTitle
        categoryIconName = record.categoryIconName
        categoryColorHex = record.categoryColorHex
    }
}

private protocol FriendSharedRecordDeduplicatable {
    var friendID: UUID { get }
    var sourceID: UUID { get }
    var startTime: Date { get }
    var updatedAt: Date { get }
}

extension FriendSharedPlanRecord: FriendSharedRecordDeduplicatable {}
extension FriendSharedChapterRecord: FriendSharedRecordDeduplicatable {}
extension FriendSharedScoreRecord: FriendSharedRecordDeduplicatable {
    var startTime: Date { dayStart }
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

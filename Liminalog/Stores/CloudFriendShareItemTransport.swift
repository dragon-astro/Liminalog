import CloudKit
import Foundation

/// 友達共有アイテムの差分送信指示（docs/20 §2.1）。
struct FriendShareItemModifyRequest {
    var upsertPlans: [FriendSharedPlanSnapshot] = []
    var upsertChapters: [FriendSharedActivitySnapshot] = []
    var deletePlanSourceIDs: Set<UUID> = []
    var deleteChapterSourceIDs: Set<UUID> = []

    var isEmpty: Bool {
        upsertPlans.isEmpty && upsertChapters.isEmpty
            && deletePlanSourceIDs.isEmpty && deleteChapterSourceIDs.isEmpty
    }
}

/// 差分送信の結果。チャンク単位のベストエフォートなので、成功した分だけ台帳へ反映する。
struct FriendShareItemModifyOutcome {
    var appliedPlanUpserts: Set<UUID> = []
    var appliedChapterUpserts: Set<UUID> = []
    var appliedPlanDeletes: Set<UUID> = []
    var appliedChapterDeletes: Set<UUID> = []
    /// 一部チャンクが失敗した場合の最初のエラー（成功分は applied* に入っている）。
    var failure: Error?
}

/// 共有ゾーンの差分取得結果（docs/20 §2.2）。
struct FriendShareZoneChanges {
    var changedRecords: [CKRecord] = []
    var deletedRecordNames: [String] = []
    var changeToken: CKServerChangeToken?
    /// トークンなし/失効からの全件取得だった場合 true（受信側は差分適用ではなく全量突合する）。
    var didFetchFullZone = false
}

extension CloudFriendShareStore {
    private static let modifyChunkSize = 300

    // MARK: - 送信（オーナー側）

    /// 個別アイテムレコードを共有ルートの子としてupsert/deleteする。
    /// チャンク分割・非アトミック。成功した分を outcome に返すので、呼び出し側は台帳へ反映する。
    func modifySharedItems(
        targetUserRecordName: String,
        rootRecordID: CKRecord.ID,
        request: FriendShareItemModifyRequest
    ) async -> FriendShareItemModifyOutcome {
        var outcome = FriendShareItemModifyOutcome()
        guard !request.isEmpty else { return outcome }
        let zoneID = rootRecordID.zoneID

        // upsert
        var saveRecords: [(record: CKRecord, planSourceID: UUID?, chapterSourceID: UUID?)] = []
        for snapshot in request.upsertPlans {
            let recordID = CKRecord.ID(
                recordName: FriendSharedItemRecordPolicy.planRecordName(
                    targetUserRecordName: targetUserRecordName,
                    sourceID: snapshot.id
                ),
                zoneID: zoneID
            )
            let record = CKRecord(recordType: FriendSharedItemRecordPolicy.planRecordType, recordID: recordID)
            FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: rootRecordID)
            saveRecords.append((record, snapshot.id, nil))
        }
        for snapshot in request.upsertChapters {
            let recordID = CKRecord.ID(
                recordName: FriendSharedItemRecordPolicy.chapterRecordName(
                    targetUserRecordName: targetUserRecordName,
                    sourceID: snapshot.id
                ),
                zoneID: zoneID
            )
            let record = CKRecord(recordType: FriendSharedItemRecordPolicy.chapterRecordType, recordID: recordID)
            FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: rootRecordID)
            saveRecords.append((record, nil, snapshot.id))
        }

        for chunk in saveRecords.chunked(into: Self.modifyChunkSize) {
            do {
                let savedIDs = try await saveSharedItemChunk(records: chunk.map(\.record))
                for entry in chunk where savedIDs.contains(entry.record.recordID.recordName) {
                    if let planID = entry.planSourceID { outcome.appliedPlanUpserts.insert(planID) }
                    if let chapterID = entry.chapterSourceID { outcome.appliedChapterUpserts.insert(chapterID) }
                }
            } catch {
                outcome.failure = outcome.failure ?? error
            }
        }

        // delete
        var deleteEntries: [(recordID: CKRecord.ID, planSourceID: UUID?, chapterSourceID: UUID?)] = []
        for sourceID in request.deletePlanSourceIDs {
            let recordID = CKRecord.ID(
                recordName: FriendSharedItemRecordPolicy.planRecordName(
                    targetUserRecordName: targetUserRecordName,
                    sourceID: sourceID
                ),
                zoneID: zoneID
            )
            deleteEntries.append((recordID, sourceID, nil))
        }
        for sourceID in request.deleteChapterSourceIDs {
            let recordID = CKRecord.ID(
                recordName: FriendSharedItemRecordPolicy.chapterRecordName(
                    targetUserRecordName: targetUserRecordName,
                    sourceID: sourceID
                ),
                zoneID: zoneID
            )
            deleteEntries.append((recordID, nil, sourceID))
        }

        for chunk in deleteEntries.chunked(into: Self.modifyChunkSize) {
            do {
                let deletedNames = try await deleteSharedItemChunk(recordIDs: chunk.map(\.recordID))
                for entry in chunk where deletedNames.contains(entry.recordID.recordName) {
                    if let planID = entry.planSourceID { outcome.appliedPlanDeletes.insert(planID) }
                    if let chapterID = entry.chapterSourceID { outcome.appliedChapterDeletes.insert(chapterID) }
                }
            } catch {
                outcome.failure = outcome.failure ?? error
            }
        }

        return outcome
    }

    /// 非アトミック保存。成功したレコード名を返し、レコード単位の失敗は最初の1件を投げずに集計したいので
    /// チャンク全体が失敗した場合のみ throw する。
    private func saveSharedItemChunk(records: [CKRecord]) async throws -> Set<String> {
        guard !records.isEmpty else { return [] }
        let result = try await withTransientRetry("friend share item save") {
            try await privateDatabase.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        }
        var savedNames = Set<String>()
        var firstError: Error?
        for (recordID, recordResult) in result.saveResults {
            switch recordResult {
            case .success:
                savedNames.insert(recordID.recordName)
            case let .failure(error):
                NSLog("Liminalog: shared item save failed for \(recordID.recordName): \(String(describing: error))")
                firstError = firstError ?? error
            }
        }
        if savedNames.isEmpty, let firstError {
            throw firstError
        }
        return savedNames
    }

    private func deleteSharedItemChunk(recordIDs: [CKRecord.ID]) async throws -> Set<String> {
        guard !recordIDs.isEmpty else { return [] }
        let result = try await withTransientRetry("friend share item delete") {
            try await privateDatabase.modifyRecords(
                saving: [],
                deleting: recordIDs,
                savePolicy: .changedKeys,
                atomically: false
            )
        }
        var deletedNames = Set<String>()
        var firstError: Error?
        for (recordID, deleteResult) in result.deleteResults {
            switch deleteResult {
            case .success:
                deletedNames.insert(recordID.recordName)
            case let .failure(error):
                if CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(error) {
                    // 既に存在しない＝削除完了扱い。
                    deletedNames.insert(recordID.recordName)
                } else {
                    NSLog("Liminalog: shared item delete failed for \(recordID.recordName): \(String(describing: error))")
                    firstError = firstError ?? error
                }
            }
        }
        if deletedNames.isEmpty, let firstError {
            throw firstError
        }
        return deletedNames
    }

    // MARK: - 受信（差分取得）

    /// 友達の共有ゾーンから変更分だけを取得する。トークン失効時は全件取得へ自動フォールバック。
    func fetchSharedZoneChanges(
        ownerUserRecordName: String,
        previousToken: CKServerChangeToken?
    ) async throws -> FriendShareZoneChanges {
        do {
            var changes = try await withTransientRetry("friend share zone fetch") {
                try await fetchZoneChangesLoop(
                    ownerUserRecordName: ownerUserRecordName,
                    token: previousToken
                )
            }
            changes.didFetchFullZone = previousToken == nil
            return changes
        } catch let error as CKError where error.code == .changeTokenExpired {
            var changes = try await withTransientRetry("friend share zone full fetch") {
                try await fetchZoneChangesLoop(
                    ownerUserRecordName: ownerUserRecordName,
                    token: nil
                )
            }
            changes.didFetchFullZone = true
            return changes
        }
    }

    private func fetchZoneChangesLoop(
        ownerUserRecordName: String,
        token: CKServerChangeToken?
    ) async throws -> FriendShareZoneChanges {
        var accumulated = FriendShareZoneChanges(changeToken: token)
        var moreComing = true
        while moreComing {
            let page = try await fetchZoneChangesPage(
                ownerUserRecordName: ownerUserRecordName,
                token: accumulated.changeToken
            )
            accumulated.changedRecords.append(contentsOf: page.changes.changedRecords)
            accumulated.deletedRecordNames.append(contentsOf: page.changes.deletedRecordNames)
            accumulated.changeToken = page.changes.changeToken
            moreComing = page.moreComing
        }
        return accumulated
    }

    private func fetchZoneChangesPage(
        ownerUserRecordName: String,
        token: CKServerChangeToken?
    ) async throws -> (changes: FriendShareZoneChanges, moreComing: Bool) {
        let zoneID = Self.sharedZoneID(ownerUserRecordName: ownerUserRecordName)
        return try await withCheckedThrowingContinuation { continuation in
            var changes = FriendShareZoneChanges()
            var moreComing = false

            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.fetchAllChanges = false

            operation.recordWasChangedBlock = { _, result in
                if case let .success(record) = result {
                    changes.changedRecords.append(record)
                }
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                changes.deletedRecordNames.append(recordID.recordName)
            }
            var zoneError: Error?
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case let .success((serverChangeToken, _, zoneMoreComing)):
                    changes.changeToken = serverChangeToken
                    moreComing = zoneMoreComing
                case let .failure(error):
                    // トークン失効などはゾーン単位のエラーとして届く。全体結果より優先して伝える。
                    zoneError = error
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let zoneError {
                        continuation.resume(throwing: zoneError)
                    } else {
                        continuation.resume(returning: (changes, moreComing))
                    }
                case let .failure(error):
                    continuation.resume(throwing: zoneError ?? error)
                }
            }
            sharedDatabase.add(operation)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

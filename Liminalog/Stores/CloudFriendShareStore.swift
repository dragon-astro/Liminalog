import CloudKit
import Foundation

/// 共有ルートレコードの内容。docs/20 §2.1 により「現在地・スコア・streak」などの
/// 軽量ステータス専用。予定/実績の本体は SharedPlan/SharedChapter の個別レコードで運ぶ。
struct CloudFriendShareSnapshot: Codable, Equatable {
    var ownerUsername: String
    var ownerDisplayName: String
    var targetUserRecordName: String
    var currentStatusTitle: String
    var currentStatusIcon: String
    var currentStatusColorHex: String
    var currentMoodText: String
    var currentStatusStartedAt: Date?
    var todayScore: Double
    var yesterdayScore: Double
    var weekScore: Double
    var monthScore: Double
    var yearScore: Double
    var streakCount: Int
    var updatedAt: Date

    init(
        ownerUsername: String,
        ownerDisplayName: String,
        targetUserRecordName: String,
        currentStatusTitle: String = "",
        currentStatusIcon: String = "circle.dashed",
        currentStatusColorHex: String = "#8E8E93",
        currentMoodText: String = "",
        currentStatusStartedAt: Date? = nil,
        todayScore: Double = 0,
        yesterdayScore: Double = 0,
        weekScore: Double = 0,
        monthScore: Double = 0,
        yearScore: Double = 0,
        streakCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.ownerUsername = ownerUsername
        self.ownerDisplayName = ownerDisplayName
        self.targetUserRecordName = targetUserRecordName
        self.currentStatusTitle = currentStatusTitle
        self.currentStatusIcon = currentStatusIcon
        self.currentStatusColorHex = currentStatusColorHex
        self.currentMoodText = currentMoodText
        self.currentStatusStartedAt = currentStatusStartedAt
        self.todayScore = todayScore
        self.yesterdayScore = yesterdayScore
        self.weekScore = weekScore
        self.monthScore = monthScore
        self.yearScore = yearScore
        self.streakCount = streakCount
        self.updatedAt = updatedAt
    }
}

struct CloudFriendShareUpsertResult {
    let snapshot: CloudFriendShareSnapshot
    let shareURL: URL?
    let rootRecordID: CKRecord.ID
    let shareRecordName: String?
    /// ルートを新規作成（or 作り直し）した場合 true。公開台帳を破棄して全量再公開する合図。
    let didCreateRoot: Bool

    var rootRecordName: String { rootRecordID.recordName }
}

enum CloudFriendShareError: LocalizedError {
    case accountUnavailable
    case missingShareURL
    case missingRootRecord
    case invalidSnapshotPayload
    case snapshotTargetMismatch
    case saveResultMissing(String)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloudにサインインすると友達共有が使えます。"
        case .missingShareURL:
            return "CloudKitの共有URLを取得できませんでした。"
        case .missingRootRecord:
            return "共有データの本体を取得できませんでした。"
        case .invalidSnapshotPayload:
            return "友達共有データの読み取りに失敗しました。"
        case .snapshotTargetMismatch:
            return "この友達共有データは自分宛てではありません。"
        case let .saveResultMissing(recordName):
            return "CloudKitへの保存結果を確認できませんでした: \(recordName)"
        }
    }
}

final class CloudFriendShareStore {
    static let rootRecordType = "FriendShareSnapshot"

    private enum RecordType {
        static let friendShareSnapshot = CloudFriendShareStore.rootRecordType
    }

    private enum Field {
        static let ownerUsername = "ownerUsername"
        static let ownerDisplayName = "ownerDisplayName"
        static let targetUserRecordName = "targetUserRecordName"
        static let currentStatusTitle = "currentStatusTitle"
        static let currentStatusIcon = "currentStatusIcon"
        static let currentStatusColorHex = "currentStatusColorHex"
        static let currentMoodText = "currentMoodText"
        static let currentStatusStartedAt = "currentStatusStartedAt"
        static let todayScore = "todayScore"
        static let yesterdayScore = "yesterdayScore"
        static let weekScore = "weekScore"
        static let monthScore = "monthScore"
        static let yearScore = "yearScore"
        static let streakCount = "streakCount"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    let privateDatabase: CKDatabase
    let sharedDatabase: CKDatabase

    init(container: CKContainer = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)) {
        self.container = container
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase
    }

    func upsertOutgoingShare(snapshot: CloudFriendShareSnapshot) async throws -> CloudFriendShareUpsertResult {
        try await requireAccount()
        try await ensureShareZone()

        // 楽観ロック衝突（client oplock error / serverRecordChanged）は、相手の承認や
        // 直近の再公開とレースしたときに起きる。最新のレコード（とトークン）を取り直して数回再試行する。
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await performOutgoingUpsert(snapshot: snapshot)
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(150_000_000) * UInt64(attempt + 1))
                continue
            } catch let error where CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: attempt + 1) != nil {
                // Zone Busy / レート制限など。サーバー指定の待ち時間でリトライする。
                let delay = CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: attempt + 1) ?? 2
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
        }
        throw lastError ?? CloudFriendShareError.missingShareURL
    }

    private func performOutgoingUpsert(snapshot: CloudFriendShareSnapshot) async throws -> CloudFriendShareUpsertResult {
        let ownerUserRecordName = try await fetchCurrentUserRecordID().recordName
        let rootID = Self.rootRecordID(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: snapshot.targetUserRecordName
        )

        if let existing = try await fetchRecordIfExists(rootID, from: privateDatabase) {
            Self.apply(snapshot, to: existing)
            do {
                let share = try await fetchShare(for: existing)
                try await ensureShareTargets(
                    share,
                    targetUserRecordName: snapshot.targetUserRecordName
                )
                let saved = try await save([existing, share], to: privateDatabase, savePolicy: .changedKeys)
                let root = try savedRecord(for: existing.recordID, in: saved)
                let savedShare = try savedRecord(for: share.recordID, in: saved) as? CKShare
                return CloudFriendShareUpsertResult(
                    snapshot: try Self.snapshot(from: root),
                    shareURL: savedShare?.url ?? share.url,
                    rootRecordID: root.recordID,
                    shareRecordName: savedShare?.recordID.recordName ?? share.recordID.recordName,
                    didCreateRoot: false
                )
            } catch {
                guard CloudFriendShareUpsertRepairPolicy.shouldRecreateRootAndShare(after: error) else {
                    throw error
                }
                try await delete([existing.recordID], from: privateDatabase)
                let repairedRoot = CKRecord(recordType: RecordType.friendShareSnapshot, recordID: rootID)
                return try await createOutgoingShare(root: repairedRoot, snapshot: snapshot)
            }
        }

        let root = CKRecord(recordType: RecordType.friendShareSnapshot, recordID: rootID)
        return try await createOutgoingShare(root: root, snapshot: snapshot)
    }

    private func createOutgoingShare(
        root: CKRecord,
        snapshot: CloudFriendShareSnapshot
    ) async throws -> CloudFriendShareUpsertResult {
        Self.apply(snapshot, to: root)
        let participant = try await fetchShareParticipant(userRecordName: snapshot.targetUserRecordName)
        participant.permission = .readOnly

        let share = CKShare(rootRecord: root)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "Liminalog" as CKRecordValue
        share.addParticipant(participant)

        let saved = try await save([root, share], to: privateDatabase, savePolicy: .ifServerRecordUnchanged)
        let savedRoot = try savedRecord(for: root.recordID, in: saved)
        let savedShare = try savedRecord(for: share.recordID, in: saved) as? CKShare
        guard let shareURL = savedShare?.url ?? share.url else {
            throw CloudFriendShareError.missingShareURL
        }
        return CloudFriendShareUpsertResult(
            snapshot: try Self.snapshot(from: savedRoot),
            shareURL: shareURL,
            rootRecordID: savedRoot.recordID,
            shareRecordName: savedShare?.recordID.recordName ?? share.recordID.recordName,
            didCreateRoot: true
        )
    }

    func acceptIncomingShare(url: URL) async throws -> CloudFriendShareSnapshot {
        try await requireAccount()
        let currentUserRecordName = try await fetchCurrentUserRecordID().recordName
        let metadata = try await fetchShareMetadata(url: url)
        if metadata.participantStatus == .pending {
            _ = try await accept(metadata: metadata)
        }
        if let rootRecord = metadata.rootRecord {
            return try Self.validatedSnapshot(from: rootRecord, currentUserRecordName: currentUserRecordName)
        }
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudFriendShareError.missingRootRecord
        }
        let record = try await fetchRecord(rootRecordID, from: sharedDatabase)
        return try Self.validatedSnapshot(from: record, currentUserRecordName: currentUserRecordName)
    }

    func fetchAcceptedIncomingShare(rootRecordName: String) async throws -> CloudFriendShareSnapshot {
        try await requireAccount()
        let currentUserRecordName = try await fetchCurrentUserRecordID().recordName
        let recordID = CKRecord.ID(recordName: rootRecordName)
        return try Self.validatedSnapshot(
            from: try await fetchRecord(recordID, from: sharedDatabase),
            currentUserRecordName: currentUserRecordName
        )
    }

    func ensureIncomingShareSubscription() async throws {
        try await requireAccount()
        do {
            _ = try await fetchSubscription(
                subscriptionID: CloudKitFriendEventBridge.friendShareSubscriptionID,
                from: sharedDatabase
            )
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Create the shared database subscription once per account.
        }

        let subscription = CKDatabaseSubscription(subscriptionID: CloudKitFriendEventBridge.friendShareSubscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await save(subscription, to: sharedDatabase)
    }

    func revokeOutgoingShare(targetUserRecordName: String) async throws {
        try await requireAccount()
        let ownerUserRecordName = try await fetchCurrentUserRecordID().recordName
        let rootID = Self.rootRecordID(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: targetUserRecordName
        )
        guard let root = try await fetchRecordIfExists(rootID, from: privateDatabase) else { return }

        var recordIDs = [root.recordID]
        if let shareRecordID = root.share?.recordID {
            recordIDs.append(shareRecordID)
        }
        try await delete(recordIDs, from: privateDatabase)
    }

    private func requireAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudFriendShareError.accountUnavailable
        }
    }

    private func fetchCurrentUserRecordID() async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let recordID else {
                    continuation.resume(throwing: CloudFriendShareError.accountUnavailable)
                    return
                }
                continuation.resume(returning: recordID)
            }
        }
    }

    private func fetchShareParticipant(userRecordName: String) async throws -> CKShare.Participant {
        try await withCheckedThrowingContinuation { continuation in
            let recordID = CKRecord.ID(recordName: userRecordName)
            container.fetchShareParticipant(withUserRecordID: recordID) { participant, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let participant else {
                    continuation.resume(throwing: CloudFriendShareError.accountUnavailable)
                    return
                }
                continuation.resume(returning: participant)
            }
        }
    }

    private func fetchShareMetadata(url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            var fetchedMetadata: CKShare.Metadata?
            var fetchedError: Error?
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = true
            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case let .success(metadata):
                    fetchedMetadata = metadata
                case let .failure(error):
                    fetchedError = error
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let fetchedError {
                        continuation.resume(throwing: fetchedError)
                    } else if let fetchedMetadata {
                        continuation.resume(returning: fetchedMetadata)
                    } else {
                        continuation.resume(throwing: CloudFriendShareError.missingRootRecord)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    private func accept(metadata: CKShare.Metadata) async throws -> CKShare {
        let result = try await container.accept([metadata])
        guard let accepted = result[metadata] else {
            throw CloudFriendShareError.missingRootRecord
        }
        return try accepted.get()
    }

    private func fetchRecord(_ recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord {
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard let result = results[recordID] else {
            throw CloudFriendShareError.missingRootRecord
        }
        return try result.get()
    }

    private func fetchRecordIfExists(_ recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await fetchRecord(recordID, from: database)
        } catch {
            guard CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(error) else {
                throw error
            }
            return nil
        }
    }

    private func fetchShare(for rootRecord: CKRecord) async throws -> CKShare {
        guard let shareRecordID = rootRecord.share?.recordID else {
            throw CloudFriendShareError.missingShareURL
        }
        guard let share = try await fetchRecord(shareRecordID, from: privateDatabase) as? CKShare else {
            throw CloudFriendShareError.missingShareURL
        }
        guard share.url != nil else {
            throw CloudFriendShareError.missingShareURL
        }
        return share
    }

    private func ensureShareTargets(_ share: CKShare, targetUserRecordName: String) async throws {
        share.publicPermission = .none
        let participantStates = share.participants.map {
            CloudFriendShareParticipantPolicy.ParticipantState(
                userRecordName: $0.userIdentity.userRecordID?.recordName,
                isReadOnly: $0.permission == .readOnly,
                isOwner: $0.role == .owner
            )
        }

        for (participant, state) in zip(share.participants, participantStates)
        where CloudFriendShareParticipantPolicy.shouldRemoveParticipant(
            targetUserRecordName: targetUserRecordName,
            participant: state
        ) {
            share.removeParticipant(participant)
        }

        if let existingTarget = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == targetUserRecordName
        }) {
            existingTarget.permission = .readOnly
            return
        }

        let participant = try await fetchShareParticipant(userRecordName: targetUserRecordName)
        participant.permission = .readOnly
        share.addParticipant(participant)
    }

    private func save(
        _ records: [CKRecord],
        to database: CKDatabase,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws -> [CKRecord.ID: CKRecord] {
        let result = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: savePolicy,
            atomically: true
        )
        var saved: [CKRecord.ID: CKRecord] = [:]
        var primaryError: Error?
        var batchError: Error?
        for (recordID, recordResult) in result.saveResults {
            switch recordResult {
            case let .success(record):
                saved[recordID] = record
            case let .failure(error):
                // atomically:true のバッチでは巻き添えのレコードが .batchRequestFailed（=「Atomic failure」）に
                // なり真因が隠れる。実際に失敗したレコードのエラーを優先してログ＆送出する。
                NSLog("Liminalog: friend-share save failed for \(recordID.recordName): \(String(describing: error))")
                if let ckError = error as? CKError, ckError.code == .batchRequestFailed {
                    batchError = batchError ?? error
                } else {
                    primaryError = primaryError ?? error
                }
            }
        }
        if let primaryError { throw primaryError }
        if let batchError { throw batchError }
        return saved
    }

    private func delete(_ recordIDs: [CKRecord.ID], from database: CKDatabase) async throws {
        guard !recordIDs.isEmpty else { return }
        _ = try await database.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .changedKeys,
            atomically: true
        )
    }

    private func save(_ subscription: CKSubscription, to database: CKDatabase) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            database.save(subscription) { savedSubscription, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let savedSubscription else {
                    continuation.resume(throwing: CloudFriendShareError.missingRootRecord)
                    return
                }
                continuation.resume(returning: savedSubscription)
            }
        }
    }

    private func fetchSubscription(subscriptionID: String, from database: CKDatabase) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let subscription else {
                    continuation.resume(throwing: CloudFriendShareError.missingRootRecord)
                    return
                }
                continuation.resume(returning: subscription)
            }
        }
    }

    private func savedRecord(for recordID: CKRecord.ID, in records: [CKRecord.ID: CKRecord]) throws -> CKRecord {
        guard let record = records[recordID] else {
            throw CloudFriendShareError.saveResultMissing(recordID.recordName)
        }
        return record
    }

    // CKShare はデフォルトゾーンのレコードを共有できないため、共有ルートは専用のカスタムゾーンに置く。
    static let shareZoneName = "LiminalogFriendShares"

    private static let shareZoneID = CKRecordZone.ID(
        zoneName: shareZoneName,
        ownerName: CKCurrentUserDefaultName
    )

    /// 受信側から見た友達（=ゾーンオーナー）の共有ゾーンID。
    static func sharedZoneID(ownerUserRecordName: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: ownerUserRecordName)
    }

    /// 共有用カスタムゾーンを用意する（存在すれば冪等）。CKShare はデフォルトゾーン不可のため必須。
    private func ensureShareZone() async throws {
        _ = try await privateDatabase.save(CKRecordZone(zoneID: Self.shareZoneID))
    }

    private static func rootRecordID(ownerUserRecordName: String, targetUserRecordName: String) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "friend-share:\(ownerUserRecordName):\(targetUserRecordName)",
            zoneID: shareZoneID
        )
    }

    private static func apply(_ snapshot: CloudFriendShareSnapshot, to record: CKRecord) {
        record[Field.ownerUsername] = snapshot.ownerUsername as CKRecordValue
        record[Field.ownerDisplayName] = snapshot.ownerDisplayName as CKRecordValue
        record[Field.targetUserRecordName] = snapshot.targetUserRecordName as CKRecordValue
        record[Field.currentStatusTitle] = snapshot.currentStatusTitle as CKRecordValue
        record[Field.currentStatusIcon] = snapshot.currentStatusIcon as CKRecordValue
        record[Field.currentStatusColorHex] = snapshot.currentStatusColorHex as CKRecordValue
        record[Field.currentMoodText] = snapshot.currentMoodText as CKRecordValue
        record[Field.currentStatusStartedAt] = snapshot.currentStatusStartedAt as CKRecordValue?
        record[Field.todayScore] = snapshot.todayScore as CKRecordValue
        record[Field.yesterdayScore] = snapshot.yesterdayScore as CKRecordValue
        record[Field.weekScore] = snapshot.weekScore as CKRecordValue
        record[Field.monthScore] = snapshot.monthScore as CKRecordValue
        record[Field.yearScore] = snapshot.yearScore as CKRecordValue
        record[Field.streakCount] = snapshot.streakCount as CKRecordValue
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
    }

    private static func snapshot(from record: CKRecord) throws -> CloudFriendShareSnapshot {
        guard let ownerUsername = record[Field.ownerUsername] as? String,
              let ownerDisplayName = record[Field.ownerDisplayName] as? String,
              let targetUserRecordName = record[Field.targetUserRecordName] as? String,
              let currentStatusTitle = record[Field.currentStatusTitle] as? String,
              let currentStatusIcon = record[Field.currentStatusIcon] as? String,
              let currentStatusColorHex = record[Field.currentStatusColorHex] as? String,
              let currentMoodText = record[Field.currentMoodText] as? String,
              let todayScore = record[Field.todayScore] as? Double,
              let yesterdayScore = record[Field.yesterdayScore] as? Double,
              let weekScore = record[Field.weekScore] as? Double,
              let monthScore = record[Field.monthScore] as? Double,
              let yearScore = record[Field.yearScore] as? Double,
              let streakCount = record[Field.streakCount] as? Int,
              let updatedAt = record[Field.updatedAt] as? Date
        else {
            throw CloudFriendShareError.invalidSnapshotPayload
        }

        return CloudFriendShareSnapshot(
            ownerUsername: ownerUsername,
            ownerDisplayName: ownerDisplayName,
            targetUserRecordName: targetUserRecordName,
            currentStatusTitle: currentStatusTitle,
            currentStatusIcon: currentStatusIcon,
            currentStatusColorHex: currentStatusColorHex,
            currentMoodText: currentMoodText,
            currentStatusStartedAt: record[Field.currentStatusStartedAt] as? Date,
            todayScore: todayScore,
            yesterdayScore: yesterdayScore,
            weekScore: weekScore,
            monthScore: monthScore,
            yearScore: yearScore,
            streakCount: streakCount,
            updatedAt: updatedAt
        )
    }

    /// ゾーン差分で届いたルートレコードをステータススナップショットへ復号する（受信者検証込み）。
    static func incomingStatusSnapshot(from record: CKRecord, currentUserRecordName: String) throws -> CloudFriendShareSnapshot {
        try validatedSnapshot(from: record, currentUserRecordName: currentUserRecordName)
    }

    private static func validatedSnapshot(from record: CKRecord, currentUserRecordName: String) throws -> CloudFriendShareSnapshot {
        let snapshot = try snapshot(from: record)
        guard CloudFriendShareRecipientPolicy.canApplySnapshot(snapshot, currentUserRecordName: currentUserRecordName) else {
            throw CloudFriendShareError.snapshotTargetMismatch
        }
        return snapshot
    }

}

import CloudKit
import Foundation

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
    var sharedPlans: [FriendSharedPlanSnapshot]
    var sharedActivities: [FriendSharedActivitySnapshot]
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
        sharedPlans: [FriendSharedPlanSnapshot] = [],
        sharedActivities: [FriendSharedActivitySnapshot] = [],
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
        self.sharedPlans = sharedPlans
        self.sharedActivities = sharedActivities
        self.updatedAt = updatedAt
    }
}

struct CloudFriendShareUpsertResult {
    let snapshot: CloudFriendShareSnapshot
    let shareURL: URL?
    let rootRecordName: String
    let shareRecordName: String?
}

enum CloudFriendShareError: LocalizedError {
    case accountUnavailable
    case missingShareURL
    case missingRootRecord
    case invalidSnapshotPayload
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
        case let .saveResultMissing(recordName):
            return "CloudKitへの保存結果を確認できませんでした: \(recordName)"
        }
    }
}

final class CloudFriendShareStore {
    private enum RecordType {
        static let friendShareSnapshot = "FriendShareSnapshot"
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
        static let sharedPlansJSON = "sharedPlansJSON"
        static let sharedActivitiesJSON = "sharedActivitiesJSON"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    init(container: CKContainer = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)) {
        self.container = container
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase
    }

    func upsertOutgoingShare(snapshot: CloudFriendShareSnapshot) async throws -> CloudFriendShareUpsertResult {
        try await requireAccount()
        let ownerUserRecordName = try await fetchCurrentUserRecordID().recordName
        let rootID = Self.rootRecordID(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: snapshot.targetUserRecordName
        )

        if let existing = try? await fetchRecord(rootID, from: privateDatabase) {
            Self.apply(snapshot, to: existing)
            let saved = try await save([existing], to: privateDatabase, savePolicy: .changedKeys)
            let root = try savedRecord(for: existing.recordID, in: saved)
            return CloudFriendShareUpsertResult(
                snapshot: try Self.snapshot(from: root),
                shareURL: nil,
                rootRecordName: root.recordID.recordName,
                shareRecordName: nil
            )
        }

        let root = CKRecord(recordType: RecordType.friendShareSnapshot, recordID: rootID)
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
            rootRecordName: savedRoot.recordID.recordName,
            shareRecordName: savedShare?.recordID.recordName ?? share.recordID.recordName
        )
    }

    func acceptIncomingShare(url: URL) async throws -> CloudFriendShareSnapshot {
        try await requireAccount()
        let metadata = try await fetchShareMetadata(url: url)
        if metadata.participantStatus == .pending {
            _ = try await accept(metadata: metadata)
        }
        if let rootRecord = metadata.rootRecord {
            return try Self.snapshot(from: rootRecord)
        }
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudFriendShareError.missingRootRecord
        }
        let record = try await fetchRecord(rootRecordID, from: sharedDatabase)
        return try Self.snapshot(from: record)
    }

    func fetchAcceptedIncomingShare(rootRecordName: String) async throws -> CloudFriendShareSnapshot {
        try await requireAccount()
        let recordID = CKRecord.ID(recordName: rootRecordName)
        return try Self.snapshot(from: try await fetchRecord(recordID, from: sharedDatabase))
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
        for (recordID, recordResult) in result.saveResults {
            saved[recordID] = try recordResult.get()
        }
        return saved
    }

    private func savedRecord(for recordID: CKRecord.ID, in records: [CKRecord.ID: CKRecord]) throws -> CKRecord {
        guard let record = records[recordID] else {
            throw CloudFriendShareError.saveResultMissing(recordID.recordName)
        }
        return record
    }

    private static func rootRecordID(ownerUserRecordName: String, targetUserRecordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "friend-share:\(ownerUserRecordName):\(targetUserRecordName)")
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
        record[Field.sharedPlansJSON] = encode(snapshot.sharedPlans) as CKRecordValue
        record[Field.sharedActivitiesJSON] = encode(snapshot.sharedActivities) as CKRecordValue
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
              let plansJSON = record[Field.sharedPlansJSON] as? String,
              let activitiesJSON = record[Field.sharedActivitiesJSON] as? String,
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
            sharedPlans: try decode([FriendSharedPlanSnapshot].self, from: plansJSON),
            sharedActivities: try decode([FriendSharedActivitySnapshot].self, from: activitiesJSON),
            updatedAt: updatedAt
        )
    }

    private static func encode<Value: Encodable>(_ value: Value) -> String {
        guard let data = try? shareJSONEncoder.encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        guard let data = json.data(using: .utf8) else {
            throw CloudFriendShareError.invalidSnapshotPayload
        }
        return try shareJSONDecoder.decode(type, from: data)
    }

    private static var shareJSONEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var shareJSONDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

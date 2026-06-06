import CloudKit
import Foundation

struct CloudFriendProfile: Equatable, Identifiable {
    var id: String { ownerUserRecordName }
    let username: String
    let displayName: String
    let ownerUserRecordName: String
    let ownerAppUserID: String
}

struct CloudFriendConsent: Equatable {
    enum Status: String {
        case requested
        case accepted
        case blocked
    }

    let ownerUserRecordName: String
    let targetUserRecordName: String
    let ownerUsername: String
    let targetUsername: String
    let ownerDisplayName: String
    let shareURL: String?
    let status: Status
}

struct CloudFriendRequestResult: Equatable {
    let profile: CloudFriendProfile
    let status: FriendStatus
    let incomingShareURL: String?
}

enum CloudKitSocialError: LocalizedError {
    case accountUnavailable
    case invalidUserID(UserIDValidationError)
    case usernameTaken
    case usernameAlreadyRegistered(String)
    case profileNotFound
    case ownProfileMissing
    case cannotRequestSelf
    case requestBlocked
    case requestNotFound
    case missingRecordField(String)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloudにサインインすると友達機能が使えます。"
        case let .invalidUserID(error):
            return error.localizedDescription
        case .usernameTaken:
            return "このユーザーIDはすでに使われています。"
        case let .usernameAlreadyRegistered(username):
            return "このiCloudアカウントでは @\(username) を確定済みです。ユーザーIDは変更できません。"
        case .profileNotFound:
            return "そのユーザーIDの人は見つかりませんでした。"
        case .ownProfileMissing:
            return "先に自分のユーザーIDを確定してください。"
        case .cannotRequestSelf:
            return "自分自身は追加できません。"
        case .requestBlocked:
            return "ブロック中の相手とは友達申請できません。"
        case .requestNotFound:
            return "友達申請が見つかりませんでした。"
        case let .missingRecordField(field):
            return "CloudKitレコードの\(field)が不足しています。"
        }
    }
}

final class CloudKitSocialStore {
    private enum RecordType {
        static let profile = "PublicProfile"
        static let profileOwnerIndex = "PublicProfileOwnerIndex"
        static let consent = "FriendConsent"
    }

    private enum Field {
        static let username = "username"
        static let displayName = "displayName"
        static let ownerUserRecordName = "ownerUserRecordName"
        static let ownerAppUserID = "ownerAppUserID"
        static let targetUserRecordName = "targetUserRecordName"
        static let targetUsername = "targetUsername"
        static let ownerUsername = "ownerUsername"
        static let ownerDisplayName = "ownerDisplayName"
        static let shareURL = "shareURL"
        static let status = "status"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    private let publicDatabase: CKDatabase

    init(container: CKContainer = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)) {
        self.container = container
        self.publicDatabase = container.publicCloudDatabase
    }

    func currentUserRecordName() async throws -> String {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudKitSocialError.accountUnavailable
        }
        return try await fetchCurrentUserRecordID().recordName
    }

    func registerProfile(username rawUsername: String, displayName: String, appUserID: UUID) async throws -> CloudFriendProfile {
        let username = try normalizedUsername(rawUsername)
        let ownerRecordName = try await currentUserRecordName()
        let now = Date()
        let ownerIndex = try await fetchRecordIfExists(Self.profileOwnerIndexRecordID(ownerUserRecordName: ownerRecordName))
        let existingOwnerUsername = try ownerIndex.map(Self.ownerIndexUsername(from:))
        guard CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: username,
            existingOwnerUsername: existingOwnerUsername
        ) else {
            throw CloudKitSocialError.usernameAlreadyRegistered(existingOwnerUsername ?? username)
        }

        let profile = CKRecord(recordType: RecordType.profile, recordID: Self.profileRecordID(username: username))
        applyProfileFields(
            to: profile,
            username: username,
            displayName: displayName,
            appUserID: appUserID,
            ownerRecordName: ownerRecordName,
            now: now,
            isNewRecord: true
        )
        let index = ownerIndex ?? CKRecord(
            recordType: RecordType.profileOwnerIndex,
            recordID: Self.profileOwnerIndexRecordID(ownerUserRecordName: ownerRecordName)
        )
        applyOwnerIndexFields(
            to: index,
            username: username,
            ownerRecordName: ownerRecordName,
            now: now,
            isNewRecord: ownerIndex == nil
        )

        do {
            let savedRecords = try await save([profile, index], savePolicy: .ifServerRecordUnchanged)
            let saved = try savedRecord(for: profile.recordID, in: savedRecords)
            return try Self.profile(from: saved)
        } catch let error as CKError where Self.isRecordConflict(error) {
            return try await reclaimExistingProfileIfOwned(
                username: username,
                displayName: displayName,
                appUserID: appUserID,
                ownerRecordName: ownerRecordName,
                existingOwnerIndex: ownerIndex
            )
        } catch {
            throw error
        }
    }

    func fetchProfile(username rawUsername: String) async throws -> CloudFriendProfile {
        let username = try normalizedUsername(rawUsername)
        do {
            return try Self.profile(from: try await fetchRecord(Self.profileRecordID(username: username)))
        } catch let error as CKError where error.code == .unknownItem {
            throw CloudKitSocialError.profileNotFound
        }
    }

    func sendFriendRequest(to rawUsername: String, fromOwnUsername ownUsername: String, ownDisplayName: String) async throws -> CloudFriendRequestResult {
        let target = try await fetchProfile(username: rawUsername)
        let ownRecordName = try await currentUserRecordName()
        let normalizedOwnUsername = try normalizedUsername(ownUsername)
        guard target.ownerUserRecordName != ownRecordName else {
            throw CloudKitSocialError.cannotRequestSelf
        }

        let existingOwnConsent = try await fetchConsentIfExists(
            ownerUserRecordName: ownRecordName,
            targetUserRecordName: target.ownerUserRecordName
        )
        let reciprocalConsent = try await fetchConsentIfExists(
            ownerUserRecordName: target.ownerUserRecordName,
            targetUserRecordName: ownRecordName
        )
        let status = try CloudFriendConsentPolicy.statusForOutgoingRequest(
            existingOwnStatus: existingOwnConsent?.status,
            reciprocalStatus: reciprocalConsent?.status
        )
        _ = try await saveConsent(
            ownerUserRecordName: ownRecordName,
            targetUserRecordName: target.ownerUserRecordName,
            ownerUsername: normalizedOwnUsername,
            targetUsername: target.username,
            ownerDisplayName: publicDisplayName(ownDisplayName),
            shareURL: nil,
            status: status
        )

        return CloudFriendRequestResult(
            profile: target,
            status: status == .accepted ? .accepted : .pendingOutgoing,
            incomingShareURL: CloudFriendReciprocalConsentPolicy.incomingShareURL(
                outgoingStatus: status,
                reciprocalShareURL: reciprocalConsent?.shareURL
            )
        )
    }

    func acceptFriendRequest(
        from requesterUserRecordName: String,
        requesterUsername: String,
        ownUsername: String,
        ownDisplayName: String
    ) async throws {
        let ownRecordName = try await currentUserRecordName()
        let existingOwnConsent = try await fetchConsentIfExists(
            ownerUserRecordName: ownRecordName,
            targetUserRecordName: requesterUserRecordName
        )
        let incomingConsent = try await fetchConsentIfExists(
            ownerUserRecordName: requesterUserRecordName,
            targetUserRecordName: ownRecordName
        )
        try CloudFriendConsentPolicy.validateAcceptingRequest(
            existingOwnStatus: existingOwnConsent?.status,
            incomingRequestStatus: incomingConsent?.status
        )
        _ = try await saveConsent(
            ownerUserRecordName: ownRecordName,
            targetUserRecordName: requesterUserRecordName,
            ownerUsername: try normalizedUsername(ownUsername),
            targetUsername: try normalizedUsername(requesterUsername),
            ownerDisplayName: publicDisplayName(ownDisplayName),
            shareURL: nil,
            status: .accepted
        )
    }

    func updateOwnConsentShareURL(
        targetUserRecordName: String,
        ownUsername: String,
        targetUsername: String,
        ownDisplayName: String,
        shareURL: URL,
        status: CloudFriendConsent.Status
    ) async throws -> CloudFriendConsent {
        try await saveConsent(
            ownerUserRecordName: try await currentUserRecordName(),
            targetUserRecordName: targetUserRecordName,
            ownerUsername: try normalizedUsername(ownUsername),
            targetUsername: try normalizedUsername(targetUsername),
            ownerDisplayName: publicDisplayName(ownDisplayName),
            shareURL: shareURL.absoluteString,
            status: status
        )
    }

    func blockOwnConsent(
        targetUserRecordName: String,
        ownUsername: String,
        targetUsername: String,
        ownDisplayName: String
    ) async throws -> CloudFriendConsent {
        try await saveConsent(
            ownerUserRecordName: try await currentUserRecordName(),
            targetUserRecordName: targetUserRecordName,
            ownerUsername: try normalizedUsername(ownUsername),
            targetUsername: normalizedUsernameIfPossible(targetUsername) ?? "unknown",
            ownerDisplayName: publicDisplayName(ownDisplayName),
            shareURL: nil,
            status: .blocked,
            clearsShareURL: true
        )
    }

    func incomingRequests(forOwnUserRecordName ownUserRecordName: String) async throws -> [CloudFriendConsent] {
        try await incomingConsents(forOwnUserRecordName: ownUserRecordName)
            .filter { $0.status == .requested }
    }

    func incomingConsents(forOwnUserRecordName ownUserRecordName: String) async throws -> [CloudFriendConsent] {
        let predicate = NSPredicate(
            format: "%K == %@",
            Field.targetUserRecordName,
            ownUserRecordName
        )
        let records = try await queryRecords(type: RecordType.consent, predicate: predicate, resultsLimit: 50)
        return try records.map(Self.consent(from:))
    }

    func outgoingConsents(forOwnUserRecordName ownUserRecordName: String) async throws -> [CloudFriendConsent] {
        let predicate = NSPredicate(
            format: "%K == %@",
            Field.ownerUserRecordName,
            ownUserRecordName
        )
        let records = try await queryRecords(type: RecordType.consent, predicate: predicate, resultsLimit: 50)
        return try records.map(Self.consent(from:))
    }

    func ensureConsentSubscriptions(forOwnUserRecordName ownUserRecordName: String) async throws {
        for scope in CloudFriendConsentSubscriptionScope.allCases {
            try await ensureConsentSubscription(
                forOwnUserRecordName: ownUserRecordName,
                scope: scope
            )
        }
    }

    func ensureIncomingConsentSubscription(forOwnUserRecordName ownUserRecordName: String) async throws {
        try await ensureConsentSubscription(
            forOwnUserRecordName: ownUserRecordName,
            scope: .incomingTarget
        )
    }

    private func ensureConsentSubscription(
        forOwnUserRecordName ownUserRecordName: String,
        scope: CloudFriendConsentSubscriptionScope
    ) async throws {
        let subscriptionID = CloudFriendConsentSubscriptionPolicy.subscriptionID(
            forOwnUserRecordName: ownUserRecordName,
            scope: scope
        )
        do {
            _ = try await fetchSubscription(subscriptionID: subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // The subscription is app-scoped on CloudKit, so only create it when it is absent.
        }

        let predicate = NSPredicate(
            format: "%K == %@",
            scope.fieldName,
            ownUserRecordName
        )
        let subscription = CKQuerySubscription(
            recordType: RecordType.consent,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await save(subscription)
    }

    private func saveConsent(
        ownerUserRecordName: String,
        targetUserRecordName: String,
        ownerUsername: String,
        targetUsername: String,
        ownerDisplayName: String,
        shareURL: String?,
        status: CloudFriendConsent.Status,
        clearsShareURL: Bool = false
    ) async throws -> CloudFriendConsent {
        let recordID = Self.consentRecordID(ownerUserRecordName: ownerUserRecordName, targetUserRecordName: targetUserRecordName)
        let existing = try await fetchRecordIfExists(recordID)
        let now = Date()
        let record = existing ?? CKRecord(recordType: RecordType.consent, recordID: recordID)
        record[Field.ownerUserRecordName] = ownerUserRecordName as CKRecordValue
        record[Field.targetUserRecordName] = targetUserRecordName as CKRecordValue
        record[Field.ownerUsername] = ownerUsername as CKRecordValue
        record[Field.targetUsername] = targetUsername as CKRecordValue
        record[Field.ownerDisplayName] = ownerDisplayName as CKRecordValue
        if let shareURL {
            record[Field.shareURL] = shareURL as CKRecordValue
        } else if clearsShareURL {
            record[Field.shareURL] = nil
        }
        record[Field.status] = status.rawValue as CKRecordValue
        if existing == nil {
            record[Field.createdAt] = now as CKRecordValue
        }
        record[Field.updatedAt] = now as CKRecordValue

        return try Self.consent(from: try await save(record, savePolicy: .changedKeys))
    }

    private func reclaimExistingProfileIfOwned(
        username: String,
        displayName: String,
        appUserID: UUID,
        ownerRecordName: String,
        existingOwnerIndex: CKRecord?
    ) async throws -> CloudFriendProfile {
        let record = try await fetchRecord(Self.profileRecordID(username: username))
        let profile = try Self.profile(from: record)
        guard CloudFriendProfileOwnershipPolicy.canReuseProfile(profile, currentUserRecordName: ownerRecordName) else {
            throw CloudKitSocialError.usernameTaken
        }

        let now = Date()
        applyProfileFields(
            to: record,
            username: username,
            displayName: displayName,
            appUserID: appUserID,
            ownerRecordName: ownerRecordName,
            now: now,
            isNewRecord: false
        )
        let ownerIndex = existingOwnerIndex ?? CKRecord(
            recordType: RecordType.profileOwnerIndex,
            recordID: Self.profileOwnerIndexRecordID(ownerUserRecordName: ownerRecordName)
        )
        applyOwnerIndexFields(
            to: ownerIndex,
            username: username,
            ownerRecordName: ownerRecordName,
            now: now,
            isNewRecord: existingOwnerIndex == nil
        )
        let savedRecords = try await save([record, ownerIndex], savePolicy: .changedKeys)
        return try Self.profile(from: try savedRecord(for: record.recordID, in: savedRecords))
    }

    private func fetchConsent(ownerUserRecordName: String, targetUserRecordName: String) async throws -> CloudFriendConsent {
        let recordID = Self.consentRecordID(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: targetUserRecordName
        )
        return try Self.consent(from: try await fetchRecord(recordID))
    }

    private func fetchConsentIfExists(ownerUserRecordName: String, targetUserRecordName: String) async throws -> CloudFriendConsent? {
        do {
            return try await fetchConsent(
                ownerUserRecordName: ownerUserRecordName,
                targetUserRecordName: targetUserRecordName
            )
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch CloudKitSocialError.profileNotFound {
            return nil
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
                    continuation.resume(throwing: CloudKitSocialError.accountUnavailable)
                    return
                }
                continuation.resume(returning: recordID)
            }
        }
    }

    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            publicDatabase.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let record else {
                    continuation.resume(throwing: CloudKitSocialError.profileNotFound)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    private func fetchRecordIfExists(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await fetchRecord(recordID)
        } catch {
            guard CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(error) else {
                throw error
            }
            return nil
        }
    }

    private func save(
        _ record: CKRecord,
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws -> CKRecord {
        let savedRecords = try await save([record], savePolicy: savePolicy)
        return try savedRecord(for: record.recordID, in: savedRecords)
    }

    private func save(
        _ records: [CKRecord],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    ) async throws -> [CKRecord.ID: CKRecord] {
        let result = try await publicDatabase.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: savePolicy,
            atomically: true
        )
        var savedRecords: [CKRecord.ID: CKRecord] = [:]
        for (recordID, recordResult) in result.saveResults {
            savedRecords[recordID] = try recordResult.get()
        }
        return savedRecords
    }

    private func savedRecord(for recordID: CKRecord.ID, in records: [CKRecord.ID: CKRecord]) throws -> CKRecord {
        guard let record = records[recordID] else {
            throw CloudKitSocialError.missingRecordField("savedRecord")
        }
        return record
    }

    private func queryRecords(type: String, predicate: NSPredicate, resultsLimit: Int) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await queryRecordPage(
                type: type,
                predicate: predicate,
                cursor: cursor,
                resultsLimit: resultsLimit
            )
            records.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        return records
    }

    private func queryRecordPage(
        type: String,
        predicate: NSPredicate,
        cursor: CKQueryOperation.Cursor?,
        resultsLimit: Int
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            var firstError: Error?
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: CKQuery(recordType: type, predicate: predicate))
            }
            operation.resultsLimit = resultsLimit
            operation.recordMatchedBlock = { _, result in
                switch result {
                case let .success(record):
                    records.append(record)
                case let .failure(error):
                    firstError = firstError ?? error
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case let .success(nextCursor):
                    if let firstError {
                        continuation.resume(throwing: firstError)
                    } else {
                        continuation.resume(returning: (records, nextCursor))
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            publicDatabase.add(operation)
        }
    }

    private func save(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            publicDatabase.save(subscription) { savedSubscription, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let savedSubscription else {
                    continuation.resume(throwing: CloudKitSocialError.missingRecordField("subscription"))
                    return
                }
                continuation.resume(returning: savedSubscription)
            }
        }
    }

    private func fetchSubscription(subscriptionID: String) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            publicDatabase.fetch(withSubscriptionID: subscriptionID) { subscription, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let subscription else {
                    continuation.resume(throwing: CloudKitSocialError.missingRecordField("subscription"))
                    return
                }
                continuation.resume(returning: subscription)
            }
        }
    }

    private func normalizedUsername(_ rawUsername: String) throws -> String {
        switch UserIDNormalizer.normalize(rawUsername) {
        case let .success(username):
            return username
        case let .failure(error):
            throw CloudKitSocialError.invalidUserID(error)
        }
    }

    private func normalizedUsernameIfPossible(_ rawUsername: String) -> String? {
        try? normalizedUsername(rawUsername)
    }

    private func publicDisplayName(_ rawDisplayName: String) -> String {
        let trimmed = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Liminalogユーザー" : trimmed
    }

    private static func profileRecordID(username: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile:\(username)")
    }

    private static func profileOwnerIndexRecordID(ownerUserRecordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile-owner:\(ownerUserRecordName)")
    }

    private func applyProfileFields(
        to record: CKRecord,
        username: String,
        displayName: String,
        appUserID: UUID,
        ownerRecordName: String,
        now: Date,
        isNewRecord: Bool
    ) {
        record[Field.username] = username as CKRecordValue
        record[Field.displayName] = publicDisplayName(displayName) as CKRecordValue
        record[Field.ownerUserRecordName] = ownerRecordName as CKRecordValue
        record[Field.ownerAppUserID] = appUserID.uuidString as CKRecordValue
        if isNewRecord {
            record[Field.createdAt] = now as CKRecordValue
        }
        record[Field.updatedAt] = now as CKRecordValue
    }

    private static func ownerIndexUsername(from record: CKRecord) throws -> String {
        guard let username = record[Field.username] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.username)
        }
        return username
    }

    private func applyOwnerIndexFields(
        to record: CKRecord,
        username: String,
        ownerRecordName: String,
        now: Date,
        isNewRecord: Bool
    ) {
        record[Field.username] = username as CKRecordValue
        record[Field.ownerUserRecordName] = ownerRecordName as CKRecordValue
        if isNewRecord {
            record[Field.createdAt] = now as CKRecordValue
        }
        record[Field.updatedAt] = now as CKRecordValue
    }

    private static func consentRecordID(ownerUserRecordName: String, targetUserRecordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "consent:\(ownerUserRecordName):\(targetUserRecordName)")
    }

    private static func profile(from record: CKRecord) throws -> CloudFriendProfile {
        guard let username = record[Field.username] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.username)
        }
        guard let displayName = record[Field.displayName] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.displayName)
        }
        guard let ownerUserRecordName = record[Field.ownerUserRecordName] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.ownerUserRecordName)
        }
        guard let ownerAppUserID = record[Field.ownerAppUserID] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.ownerAppUserID)
        }
        return CloudFriendProfile(
            username: username,
            displayName: displayName,
            ownerUserRecordName: ownerUserRecordName,
            ownerAppUserID: ownerAppUserID
        )
    }

    private static func consent(from record: CKRecord) throws -> CloudFriendConsent {
        guard let ownerUserRecordName = record[Field.ownerUserRecordName] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.ownerUserRecordName)
        }
        guard let targetUserRecordName = record[Field.targetUserRecordName] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.targetUserRecordName)
        }
        guard let ownerUsername = record[Field.ownerUsername] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.ownerUsername)
        }
        guard let targetUsername = record[Field.targetUsername] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.targetUsername)
        }
        guard let ownerDisplayName = record[Field.ownerDisplayName] as? String else {
            throw CloudKitSocialError.missingRecordField(Field.ownerDisplayName)
        }
        guard let rawStatus = record[Field.status] as? String,
              let status = CloudFriendConsent.Status(rawValue: rawStatus)
        else {
            throw CloudKitSocialError.missingRecordField(Field.status)
        }
        return CloudFriendConsent(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: targetUserRecordName,
            ownerUsername: ownerUsername,
            targetUsername: targetUsername,
            ownerDisplayName: ownerDisplayName,
            shareURL: record[Field.shareURL] as? String,
            status: status
        )
    }

    private static func isRecordConflict(_ error: CKError) -> Bool {
        error.code == .serverRecordChanged || error.code == .constraintViolation
    }
}

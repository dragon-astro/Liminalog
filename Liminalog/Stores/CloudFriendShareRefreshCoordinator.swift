import CloudKit
import Foundation
import SwiftData

@MainActor
final class CloudFriendShareRefreshCoordinator {
    static let refreshRequested = Notification.Name("LiminalogCloudFriendShareRefreshRequested")
    static let sharedRecordsDidChange = Notification.Name("LiminalogFriendSharedRecordsDidChange")
    static let pendingOutgoingRefreshDefaultsKey = "cloudFriendShare.pendingOutgoingRefresh"
    static let refreshReasonKey = "reason"
    static let changedPlanSourceIDsKey = "changedPlanSourceIDs"
    static let changedChapterSourceIDsKey = "changedChapterSourceIDs"
    static let requiresFullPublishKey = "requiresFullPublish"
    static let sharedRecordsDidChangeFriendIDKey = "friendID"
    static let sharedRecordsDidChangeRequiresFullReloadKey = "requiresFullReload"
    static let sharedRecordsDidChangeAffectedStartDatesKey = "affectedStartDates"
    static let sharedRecordsDidChangeAffectedEndDatesKey = "affectedEndDates"
    private static let batchedSourceIDFetchThreshold = 24

    private let modelContainer: ModelContainer
    private let cloudShareStore: CloudFriendShareStore
    private let cloudSocialStore: CloudKitSocialStore
    private var pendingOutgoingTask: Task<Void, Never>?
    private var pendingIncomingTask: Task<Void, Never>?
    private var pendingConsentTask: Task<Void, Never>?
    private var outgoingRefreshLane = CloudFriendShareRefreshLane()
    private var incomingRefreshLane = CloudFriendShareRefreshLane()
    private var consentRefreshLane = CloudFriendShareRefreshLane()

    init(
        modelContainer: ModelContainer,
        cloudShareStore: CloudFriendShareStore? = nil,
        cloudSocialStore: CloudKitSocialStore? = nil
    ) {
        self.modelContainer = modelContainer
        self.cloudShareStore = cloudShareStore ?? CloudFriendShareStore()
        self.cloudSocialStore = cloudSocialStore ?? CloudKitSocialStore()
    }

    static func requestRefresh(
        reason: String,
        changedPlanSourceIDs: Set<UUID> = [],
        changedChapterSourceIDs: Set<UUID> = [],
        requiresFullPublish: Bool? = nil
    ) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        markPendingOutgoingRefresh()
        let shouldPublishFull = requiresFullPublish ?? (changedPlanSourceIDs.isEmpty && changedChapterSourceIDs.isEmpty)
        NotificationCenter.default.post(
            name: refreshRequested,
            object: nil,
            userInfo: [
                refreshReasonKey: reason,
                changedPlanSourceIDsKey: changedPlanSourceIDs.map(\.uuidString),
                changedChapterSourceIDsKey: changedChapterSourceIDs.map(\.uuidString),
                requiresFullPublishKey: shouldPublishFull
            ]
        )
    }

    static var hasPendingOutgoingRefreshMarker: Bool {
        hasPendingOutgoingRefreshMarker()
    }

    static func markPendingOutgoingRefresh(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingOutgoingRefreshDefaultsKey)
    }

    static func hasPendingOutgoingRefreshMarker(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingOutgoingRefreshDefaultsKey)
    }

    static func clearPendingOutgoingRefreshMarker(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingOutgoingRefreshDefaultsKey)
    }

    static func postSharedRecordsDidChange(friendID: UUID) {
        postSharedRecordsDidChange(friendID: friendID, impact: .fullReload)
    }

    static func postSharedRecordsDidChange(friendID: UUID, impact: FriendSharedRecordChangeImpact) {
        NotificationCenter.default.post(
            name: sharedRecordsDidChange,
            object: nil,
            userInfo: [
                sharedRecordsDidChangeFriendIDKey: friendID.uuidString,
                sharedRecordsDidChangeRequiresFullReloadKey: impact.requiresFullReload,
                sharedRecordsDidChangeAffectedStartDatesKey: impact.affectedIntervals.map(\.start),
                sharedRecordsDidChangeAffectedEndDatesKey: impact.affectedIntervals.map(\.end)
            ]
        )
    }

    func scheduleRefresh(
        reason: String,
        changedPlanSourceIDs: Set<UUID> = [],
        changedChapterSourceIDs: Set<UUID> = [],
        requiresFullPublish: Bool = true
    ) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let request = CloudFriendShareRefreshRequest(
            reason: reason,
            changedPlanSourceIDs: changedPlanSourceIDs,
            changedChapterSourceIDs: changedChapterSourceIDs,
            requiresFullPublish: requiresFullPublish
        )
        pendingOutgoingTask?.cancel()
        pendingOutgoingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.runOutgoingRefresh(request: request)
        }
    }

    func scheduleIncomingRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        pendingIncomingTask?.cancel()
        pendingIncomingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.runIncomingRefresh(reason: reason)
        }
    }

    func scheduleConsentRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        pendingConsentTask?.cancel()
        pendingConsentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.runConsentRefresh(reason: reason)
        }
    }

    func ensureSubscriptionsIfPossible(reason: String) async {
        do {
            let context = modelContainer.mainContext
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).first else { return }
            guard !settings.cloudUserRecordName.isEmpty else { return }

            try await cloudSocialStore.ensureConsentSubscriptions(
                forOwnUserRecordName: settings.cloudUserRecordName
            )
            try await cloudShareStore.ensureIncomingShareSubscription()
        } catch {
            NSLog("Liminalog: failed to ensure friend CloudKit subscriptions on \(reason): \(String(describing: error))")
        }
    }

    func handleRemoteNotificationEvent(
        _ event: CloudKitFriendEventBridge.Event,
        reason: String
    ) async {
        switch event {
        case .friendConsent:
            await runConsentRefresh(reason: reason)
        case .friendShare:
            await runIncomingRefresh(reason: reason)
        }
    }

    private func runOutgoingRefresh(request initialRequest: CloudFriendShareRefreshRequest) async {
        guard outgoingRefreshLane.begin(request: initialRequest) else { return }
        defer {
            Self.clearPendingOutgoingRefreshMarker()
        }
        var request = initialRequest
        while true {
            outgoingRefreshLane.prepareForOperation()
            await publishAcceptedFriendShares(request: request)
            guard let nextRequest = outgoingRefreshLane.finishOperation() else { return }
            request = nextRequest
        }
    }

    private func runIncomingRefresh(reason initialReason: String) async {
        var request = CloudFriendShareRefreshRequest(reason: initialReason)
        guard incomingRefreshLane.begin(request: request) else { return }
        while true {
            incomingRefreshLane.prepareForOperation()
            await refreshAcceptedIncomingShares(reason: request.reason)
            guard let nextRequest = incomingRefreshLane.finishOperation() else { return }
            request = nextRequest
        }
    }

    private func runConsentRefresh(reason initialReason: String) async {
        var request = CloudFriendShareRefreshRequest(reason: initialReason)
        guard consentRefreshLane.begin(request: request) else { return }
        while true {
            consentRefreshLane.prepareForOperation()
            await refreshIncomingConsents(reason: request.reason)
            guard let nextRequest = consentRefreshLane.finishOperation() else { return }
            request = nextRequest
        }
    }

    func publishAcceptedFriendShares(reason: String) async {
        await publishAcceptedFriendShares(request: CloudFriendShareRefreshRequest(reason: reason))
    }

    func publishAcceptedFriendShares(request: CloudFriendShareRefreshRequest) async {
        do {
            let context = modelContainer.mainContext
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).first else { return }
            let ownUsername = settings.cloudUsernameNormalized
            guard !ownUsername.isEmpty else { return }
            let ownDisplayName = publicDisplayName(settings.profileDisplayName)

            let friends = try context.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            let acceptedFriends = friends.filter { $0.status == .accepted && !$0.userRecordID.isEmpty }
            guard !acceptedFriends.isEmpty else { return }

            let now = Date()
            let acceptedFriendIDs = Set(acceptedFriends.map(\.id))
            guard let preparedTargets = prepareOutgoingShares(
                acceptedFriends: acceptedFriends,
                ownUsername: ownUsername,
                ownDisplayName: ownDisplayName,
                acceptedFriendIDs: acceptedFriendIDs,
                modelContext: context,
                now: now,
                request: request
            ) else { return }
            // SwiftDataモデルを await 跨ぎで保持しない（同期が生きた今、await中のCloudKitインポートで
            // モデルが無効化されてクラッシュする。実機で観測）。ここではIDだけ控える。
            for target in preparedTargets {
                do {
                    try await cloudSocialStore.validateCanPublishOwnShare(
                        targetUserRecordName: target.userRecordID,
                        status: .accepted
                    )
                    let result = try await cloudShareStore.upsertOutgoingShare(snapshot: target.snapshot)
                    if let shareURL = result.shareURL {
                        _ = try await cloudSocialStore.updateOwnConsentShareURL(
                            targetUserRecordName: target.userRecordID,
                            ownUsername: ownUsername,
                            targetUsername: target.username,
                            ownDisplayName: ownDisplayName,
                            shareURL: shareURL,
                            status: .accepted
                        )
                    }
                    let items = result.didCreateRoot && !request.requiresFullPublish
                        ? fullSharedItems(
                            targetUserRecordName: target.userRecordID,
                            acceptedFriendIDs: acceptedFriendIDs,
                            modelContext: context,
                            now: now
                        ) ?? target.items
                        : target.items
                    await publishSharedItems(
                        targetUserRecordName: target.userRecordID,
                        items: items,
                        rootResult: result,
                        modelContext: context,
                        request: request
                    )
                } catch {
                    NSLog("Liminalog: skipped publishing friend share for \(target.userRecordID) on \(request.reason): \(String(describing: error))")
                }
            }
        } catch {
            NSLog("Liminalog: failed to publish friend shares on \(request.reason): \(String(describing: error))")
        }
    }

    func refreshAcceptedIncomingShares(reason: String) async {
        do {
            let context = modelContainer.mainContext
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).first else { return }
            guard !settings.cloudUserRecordName.isEmpty else { return }

            let incomingConsents = try await cloudSocialStore.incomingConsents(
                forOwnUserRecordName: settings.cloudUserRecordName
            )
            let outgoingConsents = try await cloudSocialStore.outgoingConsents(
                forOwnUserRecordName: settings.cloudUserRecordName
            )
            let restorations = CloudFriendConsentRestorePolicy.restorations(
                incomingConsents: incomingConsents,
                outgoingConsents: outgoingConsents
            )
            let acceptedCloudFriendRecordNames = CloudFriendConsentRestorePolicy.acceptedFriendUserRecordNames(
                in: restorations
            )
            let acceptedRestorations = restorations.filter { $0.status == .accepted }

            let visibilityPresets = try context.fetch(FetchDescriptor<VisibilityPreset>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            var friends = try context.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            var didUpdateFriends = false
            for restoration in acceptedRestorations {
                _ = upsertFriend(
                    from: restoration.consent,
                    direction: restoration.direction,
                    status: restoration.status,
                    friends: &friends,
                    visibilityPresets: visibilityPresets,
                    modelContext: context
                )
                didUpdateFriends = true
            }

            let acceptedFriends = friends.filter {
                $0.status == .accepted
                    && !$0.userRecordID.isEmpty
                    && !($0.shareURL?.isEmpty ?? true)
            }
            guard !acceptedFriends.isEmpty else {
                if didUpdateFriends {
                    try context.save()
                }
                return
            }

            let ownUserRecordName = settings.cloudUserRecordName
            // await 跨ぎでモデルを保持しない: ループはプレーン値で回し、書き込み時にIDで取り直す。
            let syncTargets = acceptedFriends.map { friend in
                (
                    friendID: friend.id,
                    userRecordID: friend.userRecordID,
                    shareURL: friend.shareURL.flatMap(URL.init(string:)),
                    hasConsent: acceptedCloudFriendRecordNames.contains(friend.userRecordID)
                )
            }
            for target in syncTargets {
                guard target.hasConsent else {
                    if let friend = aliveFriend(id: target.friendID, in: context) {
                        downgradeAcceptedCloudFriendWithoutConsent(friend)
                        postSharedRecordsDidChange(friend: friend, impact: .fullReload)
                        didUpdateFriends = true
                    }
                    try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: target.userRecordID)
                    continue
                }
                guard let shareURL = target.shareURL else { continue }
                do {
                    guard let friend = aliveFriend(id: target.friendID, in: context) else { continue }
                    try await syncIncomingShare(
                        friend: friend,
                        shareURL: shareURL,
                        ownUserRecordName: ownUserRecordName,
                        modelContext: context
                    )
                    didUpdateFriends = true
                } catch {
                    if CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error) {
                        if let friend = aliveFriend(id: target.friendID, in: context) {
                            CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
                            friend.shareURL = nil
                            postSharedRecordsDidChange(friend: friend, impact: .fullReload)
                            didUpdateFriends = true
                        }
                    } else {
                        NSLog("Liminalog: failed to refresh incoming friend share for \(target.userRecordID) on \(reason): \(String(describing: error))")
                    }
                }
            }
            // docs/20: 削除済み友達の個別行キャッシュを回収する（取りこぼし防止）。
            let purgedRecordCount = FriendSharedRecordStore(modelContext: context).purgeRecords(
                notBelongingTo: Set(friends.map(\.id))
            )
            if didUpdateFriends || purgedRecordCount > 0 {
                try context.save()
            }
        } catch {
            NSLog("Liminalog: failed to refresh incoming friend shares on \(reason): \(String(describing: error))")
        }
    }

    func refreshIncomingConsents(reason: String) async {
        do {
            let context = modelContainer.mainContext
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).first else { return }
            guard !settings.cloudUserRecordName.isEmpty else { return }

            let incomingConsents = try await cloudSocialStore.incomingConsents(
                forOwnUserRecordName: settings.cloudUserRecordName
            )
            let outgoingConsents = try await cloudSocialStore.outgoingConsents(
                forOwnUserRecordName: settings.cloudUserRecordName
            )

            let visibilityPresets = try context.fetch(FetchDescriptor<VisibilityPreset>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            var friends = try context.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            var didChange = false
            var shouldPublishAcceptedShares = false

            let restorations = CloudFriendConsentRestorePolicy.restorations(
                incomingConsents: incomingConsents,
                outgoingConsents: outgoingConsents
            )
            let acceptedCloudFriendRecordNames = CloudFriendConsentRestorePolicy.acceptedFriendUserRecordNames(
                in: restorations
            )
            for restoration in restorations {
                let status = restoration.status
                let friend = upsertFriend(
                    from: restoration.consent,
                    direction: restoration.direction,
                    status: status,
                    friends: &friends,
                    visibilityPresets: visibilityPresets,
                    modelContext: context
                )
                didChange = true

                // await 前にプレーン値を確保（モデル読みは await を跨がせない）。
                let friendID = friend.id
                let friendUserRecordID = friend.userRecordID
                let friendUsername = cloudUsername(from: friend)
                let friendShareURL = friend.shareURL.flatMap(URL.init(string:))

                if status == .blocked {
                    friend.blockedAt = Date()
                    friend.shareURL = nil
                    CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
                    postSharedRecordsDidChange(friend: friend, impact: .fullReload)
                    try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friendUserRecordID)
                    if restoration.direction == .incoming, !settings.cloudUsernameNormalized.isEmpty {
                        _ = try? await cloudSocialStore.blockOwnConsent(
                            targetUserRecordName: friendUserRecordID,
                            ownUsername: settings.cloudUsernameNormalized,
                            targetUsername: friendUsername,
                            ownDisplayName: publicDisplayName(settings.profileDisplayName)
                        )
                    }
                    continue
                }

                if status == .accepted {
                    shouldPublishAcceptedShares = true
                    if let shareURL = friendShareURL {
                        do {
                            guard let liveFriend = aliveFriend(id: friendID, in: context) else { continue }
                            try await syncIncomingShare(
                                friend: liveFriend,
                                shareURL: shareURL,
                                ownUserRecordName: settings.cloudUserRecordName,
                                modelContext: context
                            )
                        } catch {
                            if CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error) {
                                if let liveFriend = aliveFriend(id: friendID, in: context) {
                                    CloudFriendShareSnapshotApplier.clearCachedShare(from: liveFriend)
                                    liveFriend.shareURL = nil
                                    postSharedRecordsDidChange(friend: liveFriend, impact: .fullReload)
                                }
                            } else {
                                NSLog("Liminalog: failed to refresh accepted friend consent share for \(friendUserRecordID) on \(reason): \(String(describing: error))")
                            }
                        }
                    }
                }
            }

            let downgradeTargets = friends
                .filter { friend in
                    CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
                        status: friend.status,
                        userRecordID: friend.userRecordID,
                        acceptedCloudFriendRecordNames: acceptedCloudFriendRecordNames
                    )
                }
                .map { (friendID: $0.id, userRecordID: $0.userRecordID) }
            for target in downgradeTargets {
                if let friend = aliveFriend(id: target.friendID, in: context) {
                    downgradeAcceptedCloudFriendWithoutConsent(friend)
                    postSharedRecordsDidChange(friend: friend, impact: .fullReload)
                    didChange = true
                }
                try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: target.userRecordID)
            }

            if didChange {
                try context.save()
            }
            if shouldPublishAcceptedShares {
                await runOutgoingRefresh(request: CloudFriendShareRefreshRequest(reason: reason))
            }
        } catch {
            NSLog("Liminalog: failed to refresh incoming friend consents on \(reason): \(String(describing: error))")
        }
    }

    /// docs/20 §2.2: 共有ゾーンの差分だけを取得して行キャッシュへ反映する。
    /// 初回（共有未承認）やゾーン消失時は共有URLから承認し直して全件取得する。
    private func syncIncomingShare(
        friend: Friend,
        shareURL: URL,
        ownUserRecordName: String,
        modelContext: ModelContext
    ) async throws {
        let stateStore = FriendSharePublishStateStore(modelContext: modelContext)
        let owner = friend.userRecordID
        let changes: FriendShareZoneChanges
        do {
            changes = try await cloudShareStore.fetchSharedZoneChanges(
                ownerUserRecordName: owner,
                previousToken: stateStore.changeToken(ownerUserRecordName: owner)
            )
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            let snapshot = try await cloudShareStore.acceptIncomingShare(url: shareURL)
            CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
            stateStore.clearChangeToken(ownerUserRecordName: owner)
            changes = try await cloudShareStore.fetchSharedZoneChanges(
                ownerUserRecordName: owner,
                previousToken: nil
            )
        }
        applyZoneChanges(
            changes,
            to: friend,
            ownUserRecordName: ownUserRecordName,
            modelContext: modelContext,
            stateStore: stateStore
        )
    }

    private func applyZoneChanges(
        _ changes: FriendShareZoneChanges,
        to friend: Friend,
        ownUserRecordName: String,
        modelContext: ModelContext,
        stateStore: FriendSharePublishStateStore
    ) {
        guard let result = FriendShareZoneChangeApplier().apply(
            changes,
            to: friend,
            ownUserRecordName: ownUserRecordName,
            modelContext: modelContext,
            stateStore: stateStore
        ) else {
            return
        }
        NSLog("Liminalog: applied friend share zone changes from \(friend.userRecordID): \(changes.changedRecords.count) changed records, \(changes.deletedRecordNames.count) deletions, fullZone=\(changes.didFetchFullZone)")
        if result.shouldNotify {
            postSharedRecordsDidChange(friend: friend, impact: result.impact)
        }
    }

    /// 同期ブロックで、モデルから全友達分のステータススナップショットと公開アイテム（全てプレーン値）を組み立てる。
    /// 戻り値以降は SwiftData モデルへ触れずに済む。全履歴フェッチは友達人数ぶん繰り返さない。
    private func prepareOutgoingShares(
        acceptedFriends: [Friend],
        ownUsername: String,
        ownDisplayName: String,
        acceptedFriendIDs: Set<UUID>,
        modelContext: ModelContext,
        now: Date,
        request: CloudFriendShareRefreshRequest
    ) -> [PreparedOutgoingShare]? {
        guard let visibilityPresets = try? modelContext.fetch(FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )) else { return nil }
        let activeChapters = (try? modelContext.fetch(FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        ))) ?? []
        let snapshotChapters: [Chapter]
        let itemChapters: [Chapter]
        let planBlocks: [PlanBlock]
        if request.requiresFullPublish {
            guard let fetchedChapters = try? modelContext.fetch(FetchDescriptor<Chapter>(
                sortBy: [SortDescriptor(\.startTime)]
            )), let fetchedPlanBlocks = try? modelContext.fetch(FetchDescriptor<PlanBlock>(
                sortBy: [SortDescriptor(\.startTime)]
            )) else { return nil }
            snapshotChapters = fetchedChapters
            itemChapters = fetchedChapters
            planBlocks = fetchedPlanBlocks
        } else {
            let changedChapters = fetchChapters(
                sourceIDs: request.changedChapterSourceIDs,
                modelContext: modelContext
            )
            let chapterByID = Dictionary(
                (activeChapters + changedChapters).map { ($0.id, $0) },
                uniquingKeysWith: { lhs, _ in lhs }
            )
            snapshotChapters = Array(chapterByID.values).sorted { $0.startTime < $1.startTime }
            itemChapters = changedChapters.sorted { $0.startTime < $1.startTime }
            planBlocks = fetchPlanBlocks(
                sourceIDs: request.changedPlanSourceIDs,
                modelContext: modelContext
            )
        }

        let metrics = selfShareMetrics(modelContext: modelContext, now: now)
        return acceptedFriends.map { friend in
            let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
                for: friend,
                ownUsername: ownUsername,
                ownDisplayName: ownDisplayName,
                visibilityPresets: visibilityPresets,
                chapters: snapshotChapters,
                acceptedFriendIDs: acceptedFriendIDs,
                now: now,
                scoreProvider: { metrics.score(for: $0) },
                streakProvider: { metrics.streakCount }
            )
            let items = CloudFriendShareSnapshotBuilder.sharedItems(
                for: friend,
                visibilityPresets: visibilityPresets,
                chapters: itemChapters,
                planBlocks: planBlocks,
                acceptedFriendIDs: acceptedFriendIDs,
                now: now
            )
            return PreparedOutgoingShare(
                userRecordID: friend.userRecordID,
                username: cloudUsername(from: friend),
                snapshot: snapshot,
                items: items
            )
        }
    }

    private func fetchChapters(sourceIDs: Set<UUID>, modelContext: ModelContext) -> [Chapter] {
        guard !sourceIDs.isEmpty else { return [] }
        if sourceIDs.count > Self.batchedSourceIDFetchThreshold {
            return ((try? modelContext.fetch(FetchDescriptor<Chapter>(
                sortBy: [SortDescriptor(\.startTime)]
            ))) ?? []).filter { sourceIDs.contains($0.id) }
        }
        return sourceIDs.compactMap { sourceID in
            var descriptor = FetchDescriptor<Chapter>(
                predicate: #Predicate { $0.id == sourceID }
            )
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first
        }
    }

    private func fetchPlanBlocks(sourceIDs: Set<UUID>, modelContext: ModelContext) -> [PlanBlock] {
        guard !sourceIDs.isEmpty else { return [] }
        if sourceIDs.count > Self.batchedSourceIDFetchThreshold {
            return ((try? modelContext.fetch(FetchDescriptor<PlanBlock>(
                sortBy: [SortDescriptor(\.startTime)]
            ))) ?? []).filter { sourceIDs.contains($0.id) }
        }
        return sourceIDs.compactMap { sourceID in
            var descriptor = FetchDescriptor<PlanBlock>(
                predicate: #Predicate { $0.id == sourceID }
            )
            descriptor.fetchLimit = 1
            return (try? modelContext.fetch(descriptor))?.first
        }
    }

    private func fullSharedItems(
        targetUserRecordName: String,
        acceptedFriendIDs: Set<UUID>,
        modelContext: ModelContext,
        now: Date
    ) -> CloudFriendShareSnapshotBuilder.SharedItems? {
        var friendDescriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.userRecordID == targetUserRecordName }
        )
        friendDescriptor.fetchLimit = 1
        guard let friend = try? modelContext.fetch(friendDescriptor).first,
              let visibilityPresets = try? modelContext.fetch(FetchDescriptor<VisibilityPreset>(
                  sortBy: [SortDescriptor(\.sortOrder)]
              )),
              let chapters = try? modelContext.fetch(FetchDescriptor<Chapter>(
                  sortBy: [SortDescriptor(\.startTime)]
              )),
              let planBlocks = try? modelContext.fetch(FetchDescriptor<PlanBlock>(
                  sortBy: [SortDescriptor(\.startTime)]
              ))
        else { return nil }

        return CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: visibilityPresets,
            chapters: chapters,
            planBlocks: planBlocks,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )
    }

    /// docs/20 §2.1: 可視アイテムの全量と公開台帳を突合し、差分だけを個別レコードへ送る。
    /// `items` はプレーン値（await 跨ぎ安全）。
    private func publishSharedItems(
        targetUserRecordName target: String,
        items: CloudFriendShareSnapshotBuilder.SharedItems,
        rootResult: CloudFriendShareUpsertResult,
        modelContext: ModelContext,
        request: CloudFriendShareRefreshRequest
    ) async {
        let stateStore = FriendSharePublishStateStore(modelContext: modelContext)

        if rootResult.didCreateRoot {
            // ルートを作り直した場合、既存アイテムの parent が切れているため全量を再公開する。
            stateStore.clearPublishedItems(targetUserRecordName: target)
        }

        let desiredPlanFingerprints = Dictionary(
            items.plans.map { ($0.id, FriendSharePublishDiffPolicy.fingerprint($0)) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        let desiredChapterFingerprints = Dictionary(
            items.activities.map { ($0.id, FriendSharePublishDiffPolicy.fingerprint($0)) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        let publishedPlanFingerprints = request.requiresFullPublish
            ? stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.planKind
            )
            : stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.planKind,
                sourceIDs: request.changedPlanSourceIDs
            )
        let publishedChapterFingerprints = request.requiresFullPublish
            ? stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.chapterKind
            )
            : stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.chapterKind,
                sourceIDs: request.changedChapterSourceIDs
            )
        let planDiff = FriendSharePublishDiffPolicy.plan(
            desired: desiredPlanFingerprints,
            published: publishedPlanFingerprints
        )
        let chapterDiff = FriendSharePublishDiffPolicy.plan(
            desired: desiredChapterFingerprints,
            published: publishedChapterFingerprints
        )
        let request = FriendShareItemModifyRequest(
            upsertPlans: items.plans.filter { planDiff.upsertSourceIDs.contains($0.id) },
            upsertChapters: items.activities.filter { chapterDiff.upsertSourceIDs.contains($0.id) },
            deletePlanSourceIDs: planDiff.deleteSourceIDs,
            deleteChapterSourceIDs: chapterDiff.deleteSourceIDs
        )
        guard !request.isEmpty else {
            if rootResult.didCreateRoot {
                try? modelContext.save()
            }
            return
        }

        let outcome = await cloudShareStore.modifySharedItems(
            targetUserRecordName: target,
            rootRecordID: rootResult.rootRecordID,
            request: request
        )
        stateStore.applyPublishResult(
            targetUserRecordName: target,
            kind: FriendSharePublishStateStore.planKind,
            upserted: desiredPlanFingerprints.filter { outcome.appliedPlanUpserts.contains($0.key) },
            deleted: outcome.appliedPlanDeletes
        )
        stateStore.applyPublishResult(
            targetUserRecordName: target,
            kind: FriendSharePublishStateStore.chapterKind,
            upserted: desiredChapterFingerprints.filter { outcome.appliedChapterUpserts.contains($0.key) },
            deleted: outcome.appliedChapterDeletes
        )
        try? modelContext.save()
        NSLog("Liminalog: published friend share items for \(target): +\(outcome.appliedPlanUpserts.count + outcome.appliedChapterUpserts.count) upserts, -\(outcome.appliedPlanDeletes.count + outcome.appliedChapterDeletes.count) deletes (requested \(request.upsertPlans.count + request.upsertChapters.count)/\(request.deletePlanSourceIDs.count + request.deleteChapterSourceIDs.count))")
        if let failure = outcome.failure {
            NSLog("Liminalog: friend share item publish was partial for \(target): \(String(describing: failure))")
        }
    }

    private func upsertFriend(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection,
        status: FriendStatus,
        friends: inout [Friend],
        visibilityPresets: [VisibilityPreset],
        modelContext: ModelContext
    ) -> Friend {
        let friendUserRecordName = CloudFriendConsentRestorePolicy.friendUserRecordName(
            from: consent,
            direction: direction
        )
        let friendUsername = CloudFriendConsentRestorePolicy.friendUsername(
            from: consent,
            direction: direction
        )
        let existing = friends.first { $0.userRecordID == friendUserRecordName }
        let friend = existing ?? Friend(
            displayName: CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: direction),
            handle: "@\(friendUsername)",
            status: status
        )
        if existing == nil {
            modelContext.insert(friend)
            friends.append(friend)
        }
        friend.userRecordID = friendUserRecordName
        friend.displayName = existing == nil
            ? CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: direction)
            : friend.displayName
        if direction == .incoming || friend.displayName.isEmpty {
            friend.displayName = CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: direction)
        }
        friend.handle = "@\(friendUsername)"
        friend.inviteCode = friendUsername.uppercased()
        friend.status = status
        if status == .accepted {
            let incomingShareURL = CloudFriendConsentRestorePolicy.incomingShareURL(
                from: consent,
                direction: direction,
                restoredStatus: status
            )
            if CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: status, incomingShareURL: incomingShareURL) {
                friend.shareURL = incomingShareURL
            } else {
                friend.shareURL = nil
                CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
            }
        } else {
            friend.shareURL = nil
            CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
        }
        friend.updatedAt = Date()
        if status == .accepted {
            friend.acceptedAt = friend.acceptedAt ?? Date()
            friend.lastSeenAt = Date()
        }
        if friend.visibilityPresetID == nil {
            friend.visibilityPresetID = defaultVisibilityPresetID(in: visibilityPresets)
        }
        return friend
    }

    private func downgradeAcceptedCloudFriendWithoutConsent(_ friend: Friend) {
        friend.status = .pendingOutgoing
        friend.acceptedAt = nil
        friend.shareURL = nil
        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
        friend.updatedAt = Date()
    }

    private func defaultVisibilityPresetID(in visibilityPresets: [VisibilityPreset]) -> UUID? {
        visibilityPresets.first { $0.builtInKey == "acquaintances" }?.id
            ?? visibilityPresets.first { $0.name == "控えめ" }?.id
    }

    private func selfScore(for period: FriendScorePeriod, modelContext: ModelContext, now: Date) -> Double {
        switch period {
        case .day, .today:
            return ScoreSnapshotLoader.summary(on: now, modelContext: modelContext, now: now).totalScore
        case .yesterday:
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) else { return 0 }
            return ScoreSnapshotLoader.summary(on: yesterday, modelContext: modelContext, now: now).totalScore
        case .week:
            return averageSelfScore(in: dateInterval(.weekOfYear, containing: now), modelContext: modelContext, now: now)
        case .month:
            return averageSelfScore(in: dateInterval(.month, containing: now), modelContext: modelContext, now: now)
        case .year:
            return averageSelfScore(in: dateInterval(.year, containing: now), modelContext: modelContext, now: now)
        }
    }

    private func selfShareMetrics(modelContext: ModelContext, now: Date) -> SelfShareMetrics {
        SelfShareMetrics(
            today: selfScore(for: .today, modelContext: modelContext, now: now),
            yesterday: selfScore(for: .yesterday, modelContext: modelContext, now: now),
            week: selfScore(for: .week, modelContext: modelContext, now: now),
            month: selfScore(for: .month, modelContext: modelContext, now: now),
            year: selfScore(for: .year, modelContext: modelContext, now: now),
            streakCount: ScoreStore(modelContext: modelContext).streakCount(endingAt: now)
        )
    }

    private func averageSelfScore(in interval: DateInterval, modelContext: ModelContext, now: Date) -> Double {
        ScoreSnapshotLoader.averageScore(in: interval, modelContext: modelContext, now: now)
    }

    private func dateInterval(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return Calendar.japanese.dateInterval(of: component, for: date) ?? DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
    }

    /// await 跨ぎ後にモデルへ触る前の取り直し。統合/削除で消えていれば nil。
    private func aliveFriend(id: UUID, in context: ModelContext) -> Friend? {
        var descriptor = FetchDescriptor<Friend>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func cloudUsername(from friend: Friend) -> String {
        let handle = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return UserIDNormalizer.normalizedValue(rawUsername)
            ?? UserIDNormalizer.normalizedValue(friend.inviteCode)
            ?? friend.userRecordID
    }

    private func publicDisplayName(_ rawDisplayName: String) -> String {
        let trimmed = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Liminalogユーザー" : trimmed
    }

    private func postSharedRecordsDidChange(friend: Friend, impact: FriendSharedRecordChangeImpact) {
        Self.postSharedRecordsDidChange(friendID: friend.id, impact: impact)
    }
}

private struct PreparedOutgoingShare {
    let userRecordID: String
    let username: String
    let snapshot: CloudFriendShareSnapshot
    let items: CloudFriendShareSnapshotBuilder.SharedItems
}

private struct SelfShareMetrics {
    let today: Double
    let yesterday: Double
    let week: Double
    let month: Double
    let year: Double
    let streakCount: Int

    func score(for period: FriendScorePeriod) -> Double {
        switch period {
        case .day, .today:
            return today
        case .yesterday:
            return yesterday
        case .week:
            return week
        case .month:
            return month
        case .year:
            return year
        }
    }
}

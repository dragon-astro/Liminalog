import CloudKit
import Foundation
import SwiftData

@MainActor
final class CloudFriendShareRefreshCoordinator {
    static let refreshRequested = Notification.Name("LiminalogCloudFriendShareRefreshRequested")

    private let modelContainer: ModelContainer
    private let cloudShareStore: CloudFriendShareStore
    private let cloudSocialStore: CloudKitSocialStore
    private var pendingOutgoingTask: Task<Void, Never>?
    private var pendingIncomingTask: Task<Void, Never>?
    private var pendingConsentTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        cloudShareStore: CloudFriendShareStore? = nil,
        cloudSocialStore: CloudKitSocialStore? = nil
    ) {
        self.modelContainer = modelContainer
        self.cloudShareStore = cloudShareStore ?? CloudFriendShareStore()
        self.cloudSocialStore = cloudSocialStore ?? CloudKitSocialStore()
    }

    static func requestRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NotificationCenter.default.post(
            name: refreshRequested,
            object: nil,
            userInfo: ["reason": reason]
        )
    }

    func scheduleRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        pendingOutgoingTask?.cancel()
        pendingOutgoingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.publishAcceptedFriendShares(reason: reason)
        }
    }

    func scheduleIncomingRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        pendingIncomingTask?.cancel()
        pendingIncomingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshAcceptedIncomingShares(reason: reason)
        }
    }

    func scheduleConsentRefresh(reason: String) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        pendingConsentTask?.cancel()
        pendingConsentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshIncomingConsents(reason: reason)
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
            await refreshIncomingConsents(reason: reason)
        case .friendShare:
            await refreshAcceptedIncomingShares(reason: reason)
        }
    }

    func publishAcceptedFriendShares(reason: String) async {
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

            let visibilityPresets = try context.fetch(FetchDescriptor<VisibilityPreset>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            let chapters = try context.fetch(FetchDescriptor<Chapter>(
                sortBy: [SortDescriptor(\.startTime)]
            ))
            let planBlocks = try context.fetch(FetchDescriptor<PlanBlock>(
                sortBy: [SortDescriptor(\.startTime)]
            ))
            let now = Date()
            let acceptedFriendIDs = Set(acceptedFriends.map(\.id))

            for friend in acceptedFriends {
                do {
                    try await cloudSocialStore.validateCanPublishOwnShare(
                        targetUserRecordName: friend.userRecordID,
                        status: .accepted
                    )
                    let snapshot = outgoingShareSnapshot(
                        for: friend,
                        ownUsername: ownUsername,
                        ownDisplayName: ownDisplayName,
                        acceptedFriendIDs: acceptedFriendIDs,
                        visibilityPresets: visibilityPresets,
                        chapters: chapters,
                        modelContext: context,
                        now: now
                    )
                    let result = try await cloudShareStore.upsertOutgoingShare(snapshot: snapshot)
                    if let shareURL = result.shareURL {
                        _ = try await cloudSocialStore.updateOwnConsentShareURL(
                            targetUserRecordName: friend.userRecordID,
                            ownUsername: ownUsername,
                            targetUsername: cloudUsername(from: friend),
                            ownDisplayName: ownDisplayName,
                            shareURL: shareURL,
                            status: .accepted
                        )
                    }
                    await publishSharedItems(
                        for: friend,
                        rootResult: result,
                        acceptedFriendIDs: acceptedFriendIDs,
                        visibilityPresets: visibilityPresets,
                        chapters: chapters,
                        planBlocks: planBlocks,
                        modelContext: context,
                        now: now
                    )
                } catch {
                    NSLog("Liminalog: skipped publishing friend share for \(friend.userRecordID) on \(reason): \(String(describing: error))")
                }
            }
        } catch {
            NSLog("Liminalog: failed to publish friend shares on \(reason): \(String(describing: error))")
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
            for friend in acceptedFriends {
                guard acceptedCloudFriendRecordNames.contains(friend.userRecordID) else {
                    downgradeAcceptedCloudFriendWithoutConsent(friend)
                    try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friend.userRecordID)
                    didUpdateFriends = true
                    continue
                }
                guard let rawShareURL = friend.shareURL,
                      let shareURL = URL(string: rawShareURL)
                else { continue }
                do {
                    try await syncIncomingShare(
                        friend: friend,
                        shareURL: shareURL,
                        ownUserRecordName: ownUserRecordName,
                        modelContext: context
                    )
                    didUpdateFriends = true
                } catch {
                    if CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error) {
                        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
                        friend.shareURL = nil
                        didUpdateFriends = true
                    } else {
                        NSLog("Liminalog: failed to refresh incoming friend share for \(friend.userRecordID) on \(reason): \(String(describing: error))")
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

                if status == .blocked {
                    friend.blockedAt = Date()
                    friend.shareURL = nil
                    CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
                    try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friend.userRecordID)
                    if restoration.direction == .incoming, !settings.cloudUsernameNormalized.isEmpty {
                        _ = try? await cloudSocialStore.blockOwnConsent(
                            targetUserRecordName: friend.userRecordID,
                            ownUsername: settings.cloudUsernameNormalized,
                            targetUsername: cloudUsername(from: friend),
                            ownDisplayName: publicDisplayName(settings.profileDisplayName)
                        )
                    }
                    continue
                }

                if status == .accepted {
                    shouldPublishAcceptedShares = true
                    if let rawShareURL = friend.shareURL, let shareURL = URL(string: rawShareURL) {
                        do {
                            let snapshot = try await cloudShareStore.acceptIncomingShare(url: shareURL)
                            CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
                        } catch {
                            if CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error) {
                                CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
                                friend.shareURL = nil
                            } else {
                                NSLog("Liminalog: failed to refresh accepted friend consent share for \(friend.userRecordID) on \(reason): \(String(describing: error))")
                            }
                        }
                    }
                }
            }

            for friend in friends where CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
                status: friend.status,
                userRecordID: friend.userRecordID,
                acceptedCloudFriendRecordNames: acceptedCloudFriendRecordNames
            ) {
                downgradeAcceptedCloudFriendWithoutConsent(friend)
                try? await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friend.userRecordID)
                didChange = true
            }

            if didChange {
                try context.save()
            }
            if shouldPublishAcceptedShares {
                await publishAcceptedFriendShares(reason: reason)
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
        let recordStore = FriendSharedRecordStore(modelContext: modelContext)
        var changedPlans: [FriendSharedPlanSnapshot] = []
        var changedChapters: [FriendSharedActivitySnapshot] = []

        for record in changes.changedRecords {
            if let plan = FriendSharedItemRecordPolicy.planSnapshot(from: record) {
                changedPlans.append(plan)
            } else if let activity = FriendSharedItemRecordPolicy.activitySnapshot(from: record) {
                changedChapters.append(activity)
            } else if record.recordType == CloudFriendShareStore.rootRecordType {
                if let snapshot = try? CloudFriendShareStore.incomingStatusSnapshot(
                    from: record,
                    currentUserRecordName: ownUserRecordName
                ) {
                    CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
                }
            }
        }

        if changes.didFetchFullZone {
            // 全件取得＝そのゾーンの今の全量。差分適用ではなく突合して、消えた行も回収する。
            recordStore.reconcile(friendID: friend.id, plans: changedPlans, activities: changedChapters)
        } else {
            recordStore.applyChanges(
                friendID: friend.id,
                upsertPlans: changedPlans,
                upsertChapters: changedChapters,
                deletePlanSourceIDs: Set(
                    changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.planSourceID(fromRecordName:))
                ),
                deleteChapterSourceIDs: Set(
                    changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.chapterSourceID(fromRecordName:))
                )
            )
        }

        if let token = changes.changeToken {
            stateStore.setChangeToken(token, ownerUserRecordName: friend.userRecordID)
        }
        NSLog("Liminalog: applied friend share zone changes from \(friend.userRecordID): \(changedPlans.count) plans, \(changedChapters.count) chapters, \(changes.deletedRecordNames.count) deletions, fullZone=\(changes.didFetchFullZone)")
    }

    private func outgoingShareSnapshot(
        for friend: Friend,
        ownUsername: String,
        ownDisplayName: String,
        acceptedFriendIDs: Set<UUID>,
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        modelContext: ModelContext,
        now: Date
    ) -> CloudFriendShareSnapshot {
        CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: ownUsername,
            ownDisplayName: ownDisplayName,
            visibilityPresets: visibilityPresets,
            chapters: chapters,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now,
            scoreProvider: { period in
                self.selfScore(for: period, modelContext: modelContext, now: now)
            },
            streakProvider: {
                ScoreStore(modelContext: modelContext).streakCount(endingAt: now)
            }
        )
    }

    /// docs/20 §2.1: 可視アイテムの全量と公開台帳を突合し、差分だけを個別レコードへ送る。
    private func publishSharedItems(
        for friend: Friend,
        rootResult: CloudFriendShareUpsertResult,
        acceptedFriendIDs: Set<UUID>,
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        planBlocks: [PlanBlock],
        modelContext: ModelContext,
        now: Date
    ) async {
        let stateStore = FriendSharePublishStateStore(modelContext: modelContext)
        let target = friend.userRecordID

        if rootResult.didCreateRoot {
            // ルートを作り直した場合、既存アイテムの parent が切れているため全量を再公開する。
            stateStore.clearPublishedItems(targetUserRecordName: target)
        }

        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: visibilityPresets,
            chapters: chapters,
            planBlocks: planBlocks,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )

        let desiredPlanFingerprints = Dictionary(
            items.plans.map { ($0.id, FriendSharePublishDiffPolicy.fingerprint($0)) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        let desiredChapterFingerprints = Dictionary(
            items.activities.map { ($0.id, FriendSharePublishDiffPolicy.fingerprint($0)) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        let planDiff = FriendSharePublishDiffPolicy.plan(
            desired: desiredPlanFingerprints,
            published: stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.planKind
            )
        )
        let chapterDiff = FriendSharePublishDiffPolicy.plan(
            desired: desiredChapterFingerprints,
            published: stateStore.publishedFingerprints(
                targetUserRecordName: target,
                kind: FriendSharePublishStateStore.chapterKind
            )
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

    private func averageSelfScore(in interval: DateInterval, modelContext: ModelContext, now: Date) -> Double {
        ScoreSnapshotLoader.averageScore(in: interval, modelContext: modelContext, now: now)
    }

    private func dateInterval(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return Calendar.japanese.dateInterval(of: component, for: date) ?? DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
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
}

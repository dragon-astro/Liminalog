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
                let snapshot = outgoingShareSnapshot(
                    for: friend,
                    ownUsername: ownUsername,
                    ownDisplayName: ownDisplayName,
                    acceptedFriendIDs: acceptedFriendIDs,
                    visibilityPresets: visibilityPresets,
                    chapters: chapters,
                    planBlocks: planBlocks,
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
            }
        } catch {
            NSLog("Liminalog: failed to publish friend shares on \(reason): \(String(describing: error))")
        }
    }

    func refreshAcceptedIncomingShares(reason: String) async {
        do {
            let context = modelContainer.mainContext
            let friends = try context.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            let acceptedFriends = friends.filter {
                $0.status == .accepted
                    && !$0.userRecordID.isEmpty
                    && !($0.shareURL?.isEmpty ?? true)
            }
            guard !acceptedFriends.isEmpty else { return }

            for friend in acceptedFriends {
                guard let rawShareURL = friend.shareURL,
                      let shareURL = URL(string: rawShareURL)
                else { continue }
                let snapshot = try await cloudShareStore.acceptIncomingShare(url: shareURL)
                CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
            }
            try context.save()
        } catch {
            NSLog("Liminalog: failed to refresh incoming friend shares on \(reason): \(String(describing: error))")
        }
    }

    private func outgoingShareSnapshot(
        for friend: Friend,
        ownUsername: String,
        ownDisplayName: String,
        acceptedFriendIDs: Set<UUID>,
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        planBlocks: [PlanBlock],
        modelContext: ModelContext,
        now: Date
    ) -> CloudFriendShareSnapshot {
        CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: ownUsername,
            ownDisplayName: ownDisplayName,
            visibilityPresets: visibilityPresets,
            chapters: chapters,
            planBlocks: planBlocks,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now,
            scoreProvider: { period in
                self.selfScore(for: period, modelContext: modelContext, now: now)
            }
        )
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

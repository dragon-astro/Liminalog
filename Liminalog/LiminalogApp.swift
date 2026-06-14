import SwiftUI
import SwiftData
import Foundation
import UIKit

@main
struct LiminalogApp: App {
    @UIApplicationDelegateAdaptor(LiminalogAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudFriendShareRefreshCoordinator: CloudFriendShareRefreshCoordinator?
    @State private var lastLifecycleOutgoingShareRefreshAt: Date?
    @State private var pendingLifecycleCloudMaintenanceTask: Task<Void, Never>?
    @State private var pendingIncomingRefreshRequest: CloudFriendShareRefreshRequest?
    private static let lastLifecycleOutgoingShareRefreshDefaultsKey = "cloudFriendShare.lastLifecycleOutgoingRefreshAt"
    private static let outgoingPublishStateRepairVersionDefaultsKey = "cloudFriendShare.outgoingPublishStateRepairVersion"
    private static let currentOutgoingPublishStateRepairVersion = 1

    private let modelContainer: ModelContainer = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return (try? SharedModelContainer.inMemory()) ?? SharedModelContainer.shared
        }
        return SharedModelContainer.shared
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    guard cloudFriendShareRefreshCoordinator == nil else { return }
                    await waitForModelStoreReadiness(reason: "app launch")
                    let coordinator = CloudFriendShareRefreshCoordinator(modelContainer: modelContainer)
                    cloudFriendShareRefreshCoordinator = coordinator
                    if let pendingIncomingRefreshRequest {
                        coordinator.scheduleIncomingRefresh(
                            reason: pendingIncomingRefreshRequest.reason,
                            friendIDs: pendingIncomingRefreshRequest.incomingFriendIDs,
                            delay: pendingIncomingRefreshRequest.isTargetedIncomingRefresh ? 0 : 1.5
                        )
                        self.pendingIncomingRefreshRequest = nil
                    }
                    lastLifecycleOutgoingShareRefreshAt = Self.storedLifecycleOutgoingShareRefreshAt()
                    appDelegate.cloudFriendRemoteNotificationHandler = { event in
                        await coordinator.handleRemoteNotificationEvent(
                            event,
                            reason: "remote notification"
                        )
                    }
                    registerForRemoteNotificationsIfCloudFriendsEnabled()
                    scheduleLifecycleCloudMaintenance(reason: "app launch", delay: 25)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    registerForRemoteNotificationsIfCloudFriendsEnabled()
                    scheduleLifecycleCloudMaintenance(reason: "scene active", delay: 20)
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudFriendShareRefreshCoordinator.refreshRequested)) { notification in
                    let reason = notification.userInfo?[CloudFriendShareRefreshCoordinator.refreshReasonKey] as? String ?? "unknown"
                    let changedPlanSourceIDs = Self.uuidSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.changedPlanSourceIDsKey]
                    )
                    let changedChapterSourceIDs = Self.uuidSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.changedChapterSourceIDsKey]
                    )
                    let changedScoreDayStarts = Self.dateSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.changedScoreDayStartsKey]
                    )
                    let requiresFullPublish = notification.userInfo?[CloudFriendShareRefreshCoordinator.requiresFullPublishKey] as? Bool ?? true
                    let resetsPublishedItemState = notification.userInfo?[CloudFriendShareRefreshCoordinator.resetsPublishedItemStateKey] as? Bool ?? false
                    cloudFriendShareRefreshCoordinator?.scheduleRefresh(
                        reason: reason,
                        changedPlanSourceIDs: changedPlanSourceIDs,
                        changedChapterSourceIDs: changedChapterSourceIDs,
                        changedScoreDayStarts: changedScoreDayStarts,
                        requiresFullPublish: requiresFullPublish,
                        resetsPublishedItemState: resetsPublishedItemState
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudFriendShareRefreshCoordinator.incomingRefreshRequested)) { notification in
                    let reason = notification.userInfo?[CloudFriendShareRefreshCoordinator.refreshReasonKey] as? String ?? "friend calendar"
                    let incomingFriendIDs = Self.uuidSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.incomingFriendIDsKey]
                    )
                    if let coordinator = cloudFriendShareRefreshCoordinator {
                        coordinator.scheduleIncomingRefresh(
                            reason: reason,
                            friendIDs: incomingFriendIDs,
                            delay: incomingFriendIDs.isEmpty ? 1.5 : 0
                        )
                    } else {
                        pendingIncomingRefreshRequest = CloudFriendShareRefreshRequest(
                            reason: reason,
                            incomingFriendIDs: incomingFriendIDs
                        )
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudKitFriendEventBridge.friendShareDidChange)) { _ in
                    scheduleLifecycleCloudMaintenance(reason: "friend share push", delay: 10)
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudKitFriendEventBridge.friendConsentDidChange)) { _ in
                    scheduleLifecycleCloudMaintenance(reason: "friend consent push", delay: 10)
                }
        }
        .modelContainer(modelContainer)
    }

    private func registerForRemoteNotificationsIfCloudFriendsEnabled() {
        do {
            let context = modelContainer.mainContext
            guard let settings = try context.fetch(FetchDescriptor<UserSettings>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).first else { return }
            let hasRegisteredProfile = !settings.cloudUsernameNormalized.isEmpty
                || !settings.cloudUserRecordName.isEmpty
            let hasAcceptedCloudFriend = ((try? context.fetch(FetchDescriptor<Friend>())) ?? []).contains {
                $0.status == .accepted && !$0.userRecordID.isEmpty
            }
            guard hasRegisteredProfile || hasAcceptedCloudFriend else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            NSLog("Liminalog: failed to check CloudKit friend push registration state: \(String(describing: error))")
        }
    }

    private func waitForModelStoreReadiness(reason: String) async {
        let delays: [UInt64] = [
            150_000_000,
            350_000_000,
            750_000_000,
            1_500_000_000
        ]

        if modelStoreIsReadable() { return }
        for delay in delays {
            try? await Task.sleep(nanoseconds: delay)
            if modelStoreIsReadable() { return }
        }
        NSLog("Liminalog: Cloud friend sync starting before store readiness after retries (\(reason))")
    }

    private func modelStoreIsReadable() -> Bool {
        do {
            var descriptor = FetchDescriptor<UserSettings>()
            descriptor.fetchLimit = 1
            _ = try modelContainer.mainContext.fetch(descriptor)
            return true
        } catch {
            return false
        }
    }

    private func scheduleCloudFriendRefresh(reason: String) {
        cloudFriendShareRefreshCoordinator?.scheduleConsentRefresh(reason: reason)
        cloudFriendShareRefreshCoordinator?.scheduleIncomingRefresh(reason: reason)
        if scheduleOutgoingPublishStateRepairIfNeeded(reason: reason) {
            return
        }
        scheduleOutgoingLifecycleShareRefresh(reason: reason)
    }

    private func scheduleLifecycleCloudMaintenance(reason: String, delay: TimeInterval) {
        pendingLifecycleCloudMaintenanceTask?.cancel()
        pendingLifecycleCloudMaintenanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            guard !Task.isCancelled else { return }
            await cloudFriendShareRefreshCoordinator?.ensureSubscriptionsIfPossible(reason: reason)
            guard !Task.isCancelled else { return }
            scheduleCloudFriendRefresh(reason: reason)
            pendingLifecycleCloudMaintenanceTask = nil
        }
    }

    private func scheduleOutgoingLifecycleShareRefresh(reason: String) {
        let now = Date()
        guard CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh(
            hasPendingExplicitRefresh: CloudFriendShareRefreshCoordinator.hasPendingOutgoingRefreshMarker,
            lastAutomaticScheduledAt: lastLifecycleOutgoingShareRefreshAt,
            now: now
        ) else { return }
        lastLifecycleOutgoingShareRefreshAt = now
        UserDefaults.standard.set(now, forKey: Self.lastLifecycleOutgoingShareRefreshDefaultsKey)
        cloudFriendShareRefreshCoordinator?.scheduleRefresh(reason: reason)
    }

    @discardableResult
    private func scheduleOutgoingPublishStateRepairIfNeeded(reason: String) -> Bool {
        guard UserDefaults.standard.integer(forKey: Self.outgoingPublishStateRepairVersionDefaultsKey) < Self.currentOutgoingPublishStateRepairVersion else {
            return false
        }
        let now = Date()
        lastLifecycleOutgoingShareRefreshAt = now
        UserDefaults.standard.set(now, forKey: Self.lastLifecycleOutgoingShareRefreshDefaultsKey)
        UserDefaults.standard.set(
            Self.currentOutgoingPublishStateRepairVersion,
            forKey: Self.outgoingPublishStateRepairVersionDefaultsKey
        )
        cloudFriendShareRefreshCoordinator?.scheduleRefresh(
            reason: "\(reason) outgoing publish state repair",
            requiresFullPublish: true,
            resetsPublishedItemState: true
        )
        return true
    }

    private static func uuidSet(from value: Any?) -> Set<UUID> {
        guard let strings = value as? [String] else { return [] }
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private static func dateSet(from value: Any?) -> Set<Date> {
        guard let intervals = value as? [TimeInterval] else { return [] }
        return Set(intervals.map { Date(timeIntervalSince1970: $0) })
    }

    private static func storedLifecycleOutgoingShareRefreshAt() -> Date? {
        UserDefaults.standard.object(forKey: lastLifecycleOutgoingShareRefreshDefaultsKey) as? Date
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}

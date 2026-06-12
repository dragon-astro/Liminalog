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
    private static let lastLifecycleOutgoingShareRefreshDefaultsKey = "cloudFriendShare.lastLifecycleOutgoingRefreshAt"

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
                    let coordinator = CloudFriendShareRefreshCoordinator(modelContainer: modelContainer)
                    cloudFriendShareRefreshCoordinator = coordinator
                    lastLifecycleOutgoingShareRefreshAt = Self.storedLifecycleOutgoingShareRefreshAt()
                    appDelegate.cloudFriendRemoteNotificationHandler = { event in
                        await coordinator.handleRemoteNotificationEvent(
                            event,
                            reason: "remote notification"
                        )
                    }
                    registerForRemoteNotificationsIfCloudFriendsEnabled()
                    await coordinator.ensureSubscriptionsIfPossible(reason: "app launch")
                    scheduleCloudFriendRefresh(reason: "app launch")
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    registerForRemoteNotificationsIfCloudFriendsEnabled()
                    Task {
                        await cloudFriendShareRefreshCoordinator?.ensureSubscriptionsIfPossible(reason: "scene active")
                        scheduleCloudFriendRefresh(reason: "scene active")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudFriendShareRefreshCoordinator.refreshRequested)) { notification in
                    let reason = notification.userInfo?[CloudFriendShareRefreshCoordinator.refreshReasonKey] as? String ?? "unknown"
                    let changedPlanSourceIDs = Self.uuidSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.changedPlanSourceIDsKey]
                    )
                    let changedChapterSourceIDs = Self.uuidSet(
                        from: notification.userInfo?[CloudFriendShareRefreshCoordinator.changedChapterSourceIDsKey]
                    )
                    let requiresFullPublish = notification.userInfo?[CloudFriendShareRefreshCoordinator.requiresFullPublishKey] as? Bool ?? true
                    cloudFriendShareRefreshCoordinator?.scheduleRefresh(
                        reason: reason,
                        changedPlanSourceIDs: changedPlanSourceIDs,
                        changedChapterSourceIDs: changedChapterSourceIDs,
                        requiresFullPublish: requiresFullPublish
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudKitFriendEventBridge.friendShareDidChange)) { _ in
                    cloudFriendShareRefreshCoordinator?.scheduleIncomingRefresh(reason: "friend share push")
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudKitFriendEventBridge.friendConsentDidChange)) { _ in
                    cloudFriendShareRefreshCoordinator?.scheduleConsentRefresh(reason: "friend consent push")
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
            guard !settings.cloudUsernameNormalized.isEmpty else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            NSLog("Liminalog: failed to check CloudKit friend push registration state: \(String(describing: error))")
        }
    }

    private func scheduleCloudFriendRefresh(reason: String) {
        cloudFriendShareRefreshCoordinator?.scheduleConsentRefresh(reason: reason)
        cloudFriendShareRefreshCoordinator?.scheduleIncomingRefresh(reason: reason)
        scheduleOutgoingLifecycleShareRefresh(reason: reason)
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

    private static func uuidSet(from value: Any?) -> Set<UUID> {
        guard let strings = value as? [String] else { return [] }
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private static func storedLifecycleOutgoingShareRefreshAt() -> Date? {
        UserDefaults.standard.object(forKey: lastLifecycleOutgoingShareRefreshDefaultsKey) as? Date
    }
}

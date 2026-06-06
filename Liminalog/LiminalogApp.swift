import SwiftUI
import SwiftData
import Foundation
import UIKit

@main
struct LiminalogApp: App {
    @UIApplicationDelegateAdaptor(LiminalogAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudFriendShareRefreshCoordinator: CloudFriendShareRefreshCoordinator?

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
                    let reason = notification.userInfo?["reason"] as? String ?? "unknown"
                    cloudFriendShareRefreshCoordinator?.scheduleRefresh(reason: reason)
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
        cloudFriendShareRefreshCoordinator?.scheduleRefresh(reason: reason)
    }
}

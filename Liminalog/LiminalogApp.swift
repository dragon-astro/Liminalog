import SwiftUI
import SwiftData
import Foundation

@main
struct LiminalogApp: App {
    @UIApplicationDelegateAdaptor(LiminalogAppDelegate.self) private var appDelegate
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
                    cloudFriendShareRefreshCoordinator = CloudFriendShareRefreshCoordinator(modelContainer: modelContainer)
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudFriendShareRefreshCoordinator.refreshRequested)) { notification in
                    let reason = notification.userInfo?["reason"] as? String ?? "unknown"
                    cloudFriendShareRefreshCoordinator?.scheduleRefresh(reason: reason)
                }
        }
        .modelContainer(modelContainer)
    }
}

import CloudKit
import UIKit

enum CloudKitFriendEventBridge {
    enum Event: Equatable {
        case friendConsent
        case friendShare
    }

    static let friendConsentDidChange = Notification.Name("LiminalogCloudKitFriendConsentDidChange")
    static let friendShareDidChange = Notification.Name("LiminalogCloudKitFriendShareDidChange")
    static let friendConsentSubscriptionPrefix = "friend-consent:"
    static let friendShareSubscriptionID = "friend-share-updates"

    static func event(forSubscriptionID subscriptionID: String?) -> Event? {
        guard let subscriptionID else { return nil }
        if subscriptionID.hasPrefix(friendConsentSubscriptionPrefix) {
            return .friendConsent
        }
        if subscriptionID == friendShareSubscriptionID {
            return .friendShare
        }
        return nil
    }

    static func notificationName(for event: Event) -> Notification.Name {
        switch event {
        case .friendConsent:
            return friendConsentDidChange
        case .friendShare:
            return friendShareDidChange
        }
    }
}

final class LiminalogAppDelegate: NSObject, UIApplicationDelegate {
    var cloudFriendRemoteNotificationHandler: ((CloudKitFriendEventBridge.Event) async -> Void)?

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard let event = CloudKitFriendEventBridge.event(forSubscriptionID: notification?.subscriptionID) else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(
            name: CloudKitFriendEventBridge.notificationName(for: event),
            object: nil
        )
        guard let cloudFriendRemoteNotificationHandler else {
            completionHandler(.newData)
            return
        }

        Task {
            await cloudFriendRemoteNotificationHandler(event)
            completionHandler(.newData)
        }
    }
}

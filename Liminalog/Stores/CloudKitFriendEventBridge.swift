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
}

final class LiminalogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        switch CloudKitFriendEventBridge.event(forSubscriptionID: notification?.subscriptionID) {
        case .friendConsent:
            NotificationCenter.default.post(name: CloudKitFriendEventBridge.friendConsentDidChange, object: nil)
            completionHandler(.newData)
        case .friendShare:
            NotificationCenter.default.post(name: CloudKitFriendEventBridge.friendShareDidChange, object: nil)
            completionHandler(.newData)
        case nil:
            completionHandler(.noData)
        }
    }
}

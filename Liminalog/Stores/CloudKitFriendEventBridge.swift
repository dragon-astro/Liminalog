import CloudKit
import UIKit

enum CloudKitFriendEventBridge {
    static let friendConsentDidChange = Notification.Name("LiminalogCloudKitFriendConsentDidChange")
    static let friendShareDidChange = Notification.Name("LiminalogCloudKitFriendShareDidChange")
    static let friendConsentSubscriptionPrefix = "friend-consent:"
    static let friendShareSubscriptionID = "friend-share-updates"
}

final class LiminalogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard let subscriptionID = notification?.subscriptionID else {
            completionHandler(.noData)
            return
        }

        if subscriptionID.hasPrefix(CloudKitFriendEventBridge.friendConsentSubscriptionPrefix) {
            NotificationCenter.default.post(name: CloudKitFriendEventBridge.friendConsentDidChange, object: nil)
            completionHandler(.newData)
        } else if subscriptionID == CloudKitFriendEventBridge.friendShareSubscriptionID {
            NotificationCenter.default.post(name: CloudKitFriendEventBridge.friendShareDidChange, object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}

import CloudKit
import UIKit

enum CloudKitFriendEventBridge {
    static let friendConsentDidChange = Notification.Name("LiminalogCloudKitFriendConsentDidChange")
    static let friendConsentSubscriptionPrefix = "friend-consent:"
}

final class LiminalogAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID?.hasPrefix(CloudKitFriendEventBridge.friendConsentSubscriptionPrefix) == true else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(name: CloudKitFriendEventBridge.friendConsentDidChange, object: nil)
        completionHandler(.newData)
    }
}

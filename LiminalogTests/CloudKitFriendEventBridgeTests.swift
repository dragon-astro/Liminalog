import Testing
@testable import Liminalog

struct CloudKitFriendEventBridgeTests {
    @Test
    func consentSubscriptionIDsRouteToConsentRefresh() {
        #expect(CloudKitFriendEventBridge.event(
            forSubscriptionID: "friend-consent:target:_currentUser"
        ) == .friendConsent)
        #expect(CloudKitFriendEventBridge.event(
            forSubscriptionID: "friend-consent:owner:_currentUser"
        ) == .friendConsent)
    }

    @Test
    func sharedDatabaseSubscriptionRoutesToShareRefresh() {
        #expect(CloudKitFriendEventBridge.event(
            forSubscriptionID: "friend-share-updates"
        ) == .friendShare)
    }

    @Test
    func eventsMapToNotificationNames() {
        #expect(CloudKitFriendEventBridge.notificationName(
            for: .friendConsent
        ) == CloudKitFriendEventBridge.friendConsentDidChange)
        #expect(CloudKitFriendEventBridge.notificationName(
            for: .friendShare
        ) == CloudKitFriendEventBridge.friendShareDidChange)
    }

    @Test
    func unrelatedOrMissingSubscriptionIDsAreIgnored() {
        #expect(CloudKitFriendEventBridge.event(forSubscriptionID: nil) == nil)
        #expect(CloudKitFriendEventBridge.event(forSubscriptionID: "") == nil)
        #expect(CloudKitFriendEventBridge.event(forSubscriptionID: "other") == nil)
        #expect(CloudKitFriendEventBridge.event(forSubscriptionID: "friend-share-updates-old") == nil)
    }
}

import Testing
@testable import Liminalog

struct CloudFriendConsentSubscriptionPolicyTests {
    @Test
    func subscriptionScopesCoverIncomingAndOutgoingConsentChanges() {
        #expect(CloudFriendConsentSubscriptionScope.allCases == [.incomingTarget, .outgoingOwner])
    }

    @Test
    func subscriptionIDsStayUnderFriendConsentPushPrefix() {
        let recordName = "_currentUser"

        #expect(
            CloudFriendConsentSubscriptionPolicy.subscriptionID(
                forOwnUserRecordName: recordName,
                scope: .incomingTarget
            ) == "friend-consent:target:_currentUser"
        )
        #expect(
            CloudFriendConsentSubscriptionPolicy.subscriptionID(
                forOwnUserRecordName: recordName,
                scope: .outgoingOwner
            ) == "friend-consent:owner:_currentUser"
        )
    }

    @Test
    func subscriptionScopesUseQueryableConsentFields() {
        #expect(CloudFriendConsentSubscriptionScope.incomingTarget.fieldName == "targetUserRecordName")
        #expect(CloudFriendConsentSubscriptionScope.outgoingOwner.fieldName == "ownerUserRecordName")
    }
}

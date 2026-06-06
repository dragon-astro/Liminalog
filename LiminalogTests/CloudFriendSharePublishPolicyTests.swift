import Testing
@testable import Liminalog

struct CloudFriendSharePublishPolicyTests {
    @Test
    func doesNotPublishForPendingRequest() {
        #expect(!CloudFriendSharePublishPolicy.shouldPublishOutgoingShare(consentStatus: .requested))
    }

    @Test
    func publishesAfterMutualConsent() {
        #expect(CloudFriendSharePublishPolicy.shouldPublishOutgoingShare(consentStatus: .accepted))
    }

    @Test
    func doesNotPublishForBlockedConsent() {
        #expect(!CloudFriendSharePublishPolicy.shouldPublishOutgoingShare(consentStatus: .blocked))
    }
}

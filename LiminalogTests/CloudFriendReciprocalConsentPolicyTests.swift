import Testing
@testable import Liminalog

struct CloudFriendReciprocalConsentPolicyTests {
    @Test
    func acceptedRequestKeepsReciprocalShareURL() {
        #expect(CloudFriendReciprocalConsentPolicy.incomingShareURL(
            outgoingStatus: .accepted,
            reciprocalShareURL: "https://example.com/share"
        ) == "https://example.com/share")
    }

    @Test
    func requestedRequestDoesNotUseReciprocalShareURL() {
        #expect(CloudFriendReciprocalConsentPolicy.incomingShareURL(
            outgoingStatus: .requested,
            reciprocalShareURL: "https://example.com/share"
        ) == nil)
    }

    @Test
    func acceptedRequestAllowsMissingReciprocalShareURL() {
        #expect(CloudFriendReciprocalConsentPolicy.incomingShareURL(
            outgoingStatus: .accepted,
            reciprocalShareURL: nil
        ) == nil)
    }
}

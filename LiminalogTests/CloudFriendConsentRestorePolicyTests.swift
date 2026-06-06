import Testing
@testable import Liminalog

struct CloudFriendConsentRestorePolicyTests {
    @Test
    func incomingRequestRestoresAsPendingIncoming() {
        #expect(CloudFriendConsentRestorePolicy.friendStatus(
            consentStatus: .requested,
            direction: .incoming
        ) == .pendingIncoming)
    }

    @Test
    func outgoingRequestRestoresAsPendingOutgoing() {
        #expect(CloudFriendConsentRestorePolicy.friendStatus(
            consentStatus: .requested,
            direction: .outgoing
        ) == .pendingOutgoing)
    }

    @Test
    func acceptedConsentRestoresAsAcceptedInBothDirections() {
        #expect(CloudFriendConsentRestorePolicy.friendStatus(
            consentStatus: .accepted,
            direction: .incoming
        ) == .accepted)
        #expect(CloudFriendConsentRestorePolicy.friendStatus(
            consentStatus: .accepted,
            direction: .outgoing
        ) == .accepted)
    }

    @Test
    func incomingConsentUsesOwnerIdentityAsFriend() {
        let consent = makeConsent()

        #expect(CloudFriendConsentRestorePolicy.friendUserRecordName(from: consent, direction: .incoming) == "_owner")
        #expect(CloudFriendConsentRestorePolicy.friendUsername(from: consent, direction: .incoming) == "owner")
        #expect(CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: .incoming) == "Owner")
        #expect(CloudFriendConsentRestorePolicy.incomingShareURL(from: consent, direction: .incoming) == "https://example.com/share")
    }

    @Test
    func outgoingConsentUsesTargetIdentityAsFriendAndDoesNotImportOwnShareURL() {
        let consent = makeConsent()

        #expect(CloudFriendConsentRestorePolicy.friendUserRecordName(from: consent, direction: .outgoing) == "_target")
        #expect(CloudFriendConsentRestorePolicy.friendUsername(from: consent, direction: .outgoing) == "target")
        #expect(CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: .outgoing) == "@target")
        #expect(CloudFriendConsentRestorePolicy.incomingShareURL(from: consent, direction: .outgoing) == nil)
    }

    private func makeConsent() -> CloudFriendConsent {
        CloudFriendConsent(
            ownerUserRecordName: "_owner",
            targetUserRecordName: "_target",
            ownerUsername: "owner",
            targetUsername: "target",
            ownerDisplayName: "Owner",
            shareURL: "https://example.com/share",
            status: .accepted
        )
    }
}

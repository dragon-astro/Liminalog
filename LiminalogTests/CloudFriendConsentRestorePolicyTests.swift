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

    @Test
    func reciprocalAcceptedConsentWinsOverStaleIncomingRequest() throws {
        let incoming = makeConsent(
            ownerUserRecordName: "_friend",
            targetUserRecordName: "_me",
            ownerUsername: "friend",
            targetUsername: "me",
            ownerDisplayName: "Friend",
            status: .requested
        )
        let outgoing = makeConsent(
            ownerUserRecordName: "_me",
            targetUserRecordName: "_friend",
            ownerUsername: "me",
            targetUsername: "friend",
            ownerDisplayName: "Me",
            status: .accepted
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [incoming],
            outgoingConsents: [outgoing]
        ).first)

        #expect(restoration.status == .accepted)
        #expect(restoration.direction == .incoming)
        #expect(CloudFriendConsentRestorePolicy.friendUserRecordName(
            from: restoration.consent,
            direction: restoration.direction
        ) == "_friend")
    }

    @Test
    func reciprocalAcceptedConsentWinsOverStaleOutgoingRequest() throws {
        let incoming = makeConsent(
            ownerUserRecordName: "_friend",
            targetUserRecordName: "_me",
            ownerUsername: "friend",
            targetUsername: "me",
            ownerDisplayName: "Friend",
            shareURL: "https://example.com/friend-share",
            status: .accepted
        )
        let outgoing = makeConsent(
            ownerUserRecordName: "_me",
            targetUserRecordName: "_friend",
            ownerUsername: "me",
            targetUsername: "friend",
            ownerDisplayName: "Me",
            status: .requested
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [incoming],
            outgoingConsents: [outgoing]
        ).first)

        #expect(restoration.status == .accepted)
        #expect(CloudFriendConsentRestorePolicy.incomingShareURL(
            from: restoration.consent,
            direction: restoration.direction
        ) == "https://example.com/friend-share")
    }

    @Test
    func mutualRequestedConsentsRestoreAsAccepted() throws {
        let incoming = makeConsent(
            ownerUserRecordName: "_friend",
            targetUserRecordName: "_me",
            ownerUsername: "friend",
            targetUsername: "me",
            ownerDisplayName: "Friend",
            status: .requested
        )
        let outgoing = makeConsent(
            ownerUserRecordName: "_me",
            targetUserRecordName: "_friend",
            ownerUsername: "me",
            targetUsername: "friend",
            ownerDisplayName: "Me",
            status: .requested
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [incoming],
            outgoingConsents: [outgoing]
        ).first)

        #expect(restoration.status == .accepted)
    }

    @Test
    func blockedConsentWinsOverAcceptedReciprocalConsent() throws {
        let incoming = makeConsent(
            ownerUserRecordName: "_friend",
            targetUserRecordName: "_me",
            ownerUsername: "friend",
            targetUsername: "me",
            ownerDisplayName: "Friend",
            status: .blocked
        )
        let outgoing = makeConsent(
            ownerUserRecordName: "_me",
            targetUserRecordName: "_friend",
            ownerUsername: "me",
            targetUsername: "friend",
            ownerDisplayName: "Me",
            status: .accepted
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [incoming],
            outgoingConsents: [outgoing]
        ).first)

        #expect(restoration.status == .blocked)
    }

    private func makeConsent(
        ownerUserRecordName: String = "_owner",
        targetUserRecordName: String = "_target",
        ownerUsername: String = "owner",
        targetUsername: String = "target",
        ownerDisplayName: String = "Owner",
        shareURL: String? = "https://example.com/share",
        status: CloudFriendConsent.Status = .accepted
    ) -> CloudFriendConsent {
        CloudFriendConsent(
            ownerUserRecordName: ownerUserRecordName,
            targetUserRecordName: targetUserRecordName,
            ownerUsername: ownerUsername,
            targetUsername: targetUsername,
            ownerDisplayName: ownerDisplayName,
            shareURL: shareURL,
            status: status
        )
    }
}

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
            direction: restoration.direction,
            restoredStatus: restoration.status
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
    func oneSidedIncomingAcceptedConsentDoesNotRestoreAsAcceptedOrImportShareURL() throws {
        let incoming = makeConsent(
            ownerUserRecordName: "_friend",
            targetUserRecordName: "_me",
            ownerUsername: "friend",
            targetUsername: "me",
            ownerDisplayName: "Friend",
            shareURL: "https://example.com/stale-share",
            status: .accepted
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [incoming],
            outgoingConsents: []
        ).first)

        #expect(restoration.status == .pendingIncoming)
        #expect(CloudFriendConsentRestorePolicy.incomingShareURL(
            from: restoration.consent,
            direction: restoration.direction,
            restoredStatus: restoration.status
        ) == nil)
    }

    @Test
    func oneSidedOutgoingAcceptedConsentDoesNotRestoreAsAccepted() throws {
        let outgoing = makeConsent(
            ownerUserRecordName: "_me",
            targetUserRecordName: "_friend",
            ownerUsername: "me",
            targetUsername: "friend",
            ownerDisplayName: "Me",
            status: .accepted
        )

        let restoration = try #require(CloudFriendConsentRestorePolicy.restorations(
            incomingConsents: [],
            outgoingConsents: [outgoing]
        ).first)

        #expect(restoration.status == .pendingOutgoing)
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

    @Test
    func acceptedFriendUserRecordNamesOnlyIncludesMutualAcceptedRestorations() {
        let restorations = [
            CloudFriendConsentRestoration(
                consent: makeConsent(
                    ownerUserRecordName: "_accepted",
                    targetUserRecordName: "_me",
                    ownerUsername: "accepted",
                    targetUsername: "me",
                    ownerDisplayName: "Accepted",
                    status: .accepted
                ),
                direction: .incoming,
                status: .accepted
            ),
            CloudFriendConsentRestoration(
                consent: makeConsent(
                    ownerUserRecordName: "_pending",
                    targetUserRecordName: "_me",
                    ownerUsername: "pending",
                    targetUsername: "me",
                    ownerDisplayName: "Pending",
                    status: .requested
                ),
                direction: .incoming,
                status: .pendingIncoming
            ),
            CloudFriendConsentRestoration(
                consent: makeConsent(
                    ownerUserRecordName: "_me",
                    targetUserRecordName: "_blocked",
                    ownerUsername: "me",
                    targetUsername: "blocked",
                    ownerDisplayName: "Me",
                    status: .blocked
                ),
                direction: .outgoing,
                status: .blocked
            )
        ]

        #expect(CloudFriendConsentRestorePolicy.acceptedFriendUserRecordNames(
            in: restorations
        ) == ["_accepted"])
    }

    @Test
    func incomingShareRefreshTargetsOnlyMutualAcceptedIncomingShares() {
        let acceptedIncoming = CloudFriendConsentRestoration(
            consent: makeConsent(
                ownerUserRecordName: "_friend",
                targetUserRecordName: "_me",
                ownerUsername: "friend",
                targetUsername: "me",
                ownerDisplayName: "Friend",
                shareURL: "https://example.com/friend-share",
                status: .accepted
            ),
            direction: .incoming,
            status: .accepted
        )
        let acceptedOutgoing = CloudFriendConsentRestoration(
            consent: makeConsent(
                ownerUserRecordName: "_me",
                targetUserRecordName: "_other",
                ownerUsername: "me",
                targetUsername: "other",
                ownerDisplayName: "Me",
                shareURL: "https://example.com/own-share",
                status: .accepted
            ),
            direction: .outgoing,
            status: .accepted
        )
        let pendingIncoming = CloudFriendConsentRestoration(
            consent: makeConsent(
                ownerUserRecordName: "_pending",
                targetUserRecordName: "_me",
                ownerUsername: "pending",
                targetUsername: "me",
                ownerDisplayName: "Pending",
                shareURL: "https://example.com/pending-share",
                status: .accepted
            ),
            direction: .incoming,
            status: .pendingIncoming
        )

        let targets = CloudFriendIncomingShareRefreshPolicy.acceptedIncomingShareRestorations(
            in: [acceptedIncoming, acceptedOutgoing, pendingIncoming]
        )

        #expect(targets == [acceptedIncoming])
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

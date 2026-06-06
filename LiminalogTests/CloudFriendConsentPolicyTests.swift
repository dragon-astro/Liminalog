import Testing
@testable import Liminalog

struct CloudFriendConsentPolicyTests {
    @Test
    func outgoingRequestIsRequestedWithoutReciprocalConsent() throws {
        let status = try CloudFriendConsentPolicy.statusForOutgoingRequest(
            existingOwnStatus: nil,
            reciprocalStatus: nil
        )

        #expect(status == .requested)
    }

    @Test
    func outgoingRequestAcceptsWhenReciprocalRequestExists() throws {
        let status = try CloudFriendConsentPolicy.statusForOutgoingRequest(
            existingOwnStatus: nil,
            reciprocalStatus: .requested
        )

        #expect(status == .accepted)
    }

    @Test
    func outgoingRequestKeepsExistingAcceptedConsentWithoutReciprocalConsent() throws {
        let status = try CloudFriendConsentPolicy.statusForOutgoingRequest(
            existingOwnStatus: .accepted,
            reciprocalStatus: nil
        )

        #expect(status == .accepted)
    }

    @Test
    func outgoingRequestAcceptsWhenReciprocalAcceptedConsentExists() throws {
        let status = try CloudFriendConsentPolicy.statusForOutgoingRequest(
            existingOwnStatus: .requested,
            reciprocalStatus: .accepted
        )

        #expect(status == .accepted)
    }

    @Test
    func outgoingRequestDoesNotOverrideOwnBlock() {
        expectRequestBlocked {
            _ = try CloudFriendConsentPolicy.statusForOutgoingRequest(
                existingOwnStatus: .blocked,
                reciprocalStatus: nil
            )
        }
    }

    @Test
    func outgoingRequestDoesNotTreatReciprocalBlockAsAccepted() {
        expectRequestBlocked {
            _ = try CloudFriendConsentPolicy.statusForOutgoingRequest(
                existingOwnStatus: nil,
                reciprocalStatus: .blocked
            )
        }
    }

    @Test
    func acceptingRequestDoesNotOverrideOwnBlock() {
        expectRequestBlocked {
            try CloudFriendConsentPolicy.validateAcceptingRequest(
                existingOwnStatus: .blocked,
                incomingRequestStatus: .requested
            )
        }
    }

    @Test
    func acceptingRequestAllowsIncomingRequest() throws {
        try CloudFriendConsentPolicy.validateAcceptingRequest(
            existingOwnStatus: nil,
            incomingRequestStatus: .requested
        )
    }

    @Test
    func acceptingRequestRequiresIncomingRequest() {
        expectRequestNotFound {
            try CloudFriendConsentPolicy.validateAcceptingRequest(
                existingOwnStatus: nil,
                incomingRequestStatus: nil
            )
        }
    }

    @Test
    func acceptingRequestDoesNotAcceptIncomingBlock() {
        expectRequestBlocked {
            try CloudFriendConsentPolicy.validateAcceptingRequest(
                existingOwnStatus: nil,
                incomingRequestStatus: .blocked
            )
        }
    }

    @Test
    func shareURLUpdateAllowsAcceptedConsentWithReciprocalRequest() throws {
        try CloudFriendConsentPolicy.validateUpdatingShareURL(
            existingOwnStatus: .accepted,
            reciprocalStatus: .requested,
            updatedStatus: .accepted
        )
    }

    @Test
    func shareURLUpdateAllowsAcceptedConsentWithReciprocalAcceptedConsent() throws {
        try CloudFriendConsentPolicy.validateUpdatingShareURL(
            existingOwnStatus: .accepted,
            reciprocalStatus: .accepted,
            updatedStatus: .accepted
        )
    }

    @Test
    func shareURLUpdateAllowsCrossRequestAfterReciprocalRequest() throws {
        try CloudFriendConsentPolicy.validateUpdatingShareURL(
            existingOwnStatus: .requested,
            reciprocalStatus: .requested,
            updatedStatus: .accepted
        )
    }

    @Test
    func shareURLUpdateAllowsExistingRequestAfterReciprocalAccepts() throws {
        try CloudFriendConsentPolicy.validateUpdatingShareURL(
            existingOwnStatus: .requested,
            reciprocalStatus: .accepted,
            updatedStatus: .accepted
        )
    }

    @Test
    func shareURLUpdateDoesNotOverrideOwnBlock() {
        expectRequestBlocked {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: .blocked,
                reciprocalStatus: .accepted,
                updatedStatus: .accepted
            )
        }
    }

    @Test
    func shareURLUpdateDoesNotOverrideReciprocalBlock() {
        expectRequestBlocked {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: .accepted,
                reciprocalStatus: .blocked,
                updatedStatus: .accepted
            )
        }
    }

    @Test
    func shareURLUpdateRequiresAcceptedStatus() {
        expectRequestNotFound {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: .requested,
                reciprocalStatus: .accepted,
                updatedStatus: .requested
            )
        }
    }

    @Test
    func shareURLUpdateRequiresOwnConsentBeforePublishing() {
        expectRequestNotFound {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: nil,
                reciprocalStatus: .accepted,
                updatedStatus: .accepted
            )
        }
    }

    @Test
    func shareURLUpdateDoesNotPublishForOneSidedOwnRequest() {
        expectRequestNotFound {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: .requested,
                reciprocalStatus: nil,
                updatedStatus: .accepted
            )
        }
    }

    @Test
    func shareURLUpdateDoesNotPublishForOneSidedOwnAccept() {
        expectRequestNotFound {
            try CloudFriendConsentPolicy.validateUpdatingShareURL(
                existingOwnStatus: .accepted,
                reciprocalStatus: nil,
                updatedStatus: .accepted
            )
        }
    }

    private func expectRequestBlocked(_ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected requestBlocked error")
        } catch CloudKitSocialError.requestBlocked {
            return
        } catch {
            Issue.record("Expected requestBlocked error, got \(error)")
        }
    }

    private func expectRequestNotFound(_ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected requestNotFound error")
        } catch CloudKitSocialError.requestNotFound {
            return
        } catch {
            Issue.record("Expected requestNotFound error, got \(error)")
        }
    }
}

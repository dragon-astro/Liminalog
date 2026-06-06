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
            try CloudFriendConsentPolicy.validateAcceptingRequest(existingOwnStatus: .blocked)
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
}

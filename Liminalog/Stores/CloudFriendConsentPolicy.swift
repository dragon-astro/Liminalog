import Foundation

enum CloudFriendConsentPolicy {
    static func statusForOutgoingRequest(
        existingOwnStatus: CloudFriendConsent.Status?,
        reciprocalStatus: CloudFriendConsent.Status?
    ) throws -> CloudFriendConsent.Status {
        if existingOwnStatus == .blocked || reciprocalStatus == .blocked {
            throw CloudKitSocialError.requestBlocked
        }
        if existingOwnStatus == .accepted || reciprocalStatus == .accepted {
            return .accepted
        }
        guard reciprocalStatus != nil else {
            return .requested
        }
        return .accepted
    }

    static func validateAcceptingRequest(
        existingOwnStatus: CloudFriendConsent.Status?,
        incomingRequestStatus: CloudFriendConsent.Status?
    ) throws {
        if existingOwnStatus == .blocked || incomingRequestStatus == .blocked {
            throw CloudKitSocialError.requestBlocked
        }
        guard incomingRequestStatus != nil else {
            throw CloudKitSocialError.requestNotFound
        }
    }

    static func validateUpdatingShareURL(
        existingOwnStatus: CloudFriendConsent.Status?,
        reciprocalStatus: CloudFriendConsent.Status?,
        updatedStatus: CloudFriendConsent.Status
    ) throws {
        if existingOwnStatus == .blocked || reciprocalStatus == .blocked {
            throw CloudKitSocialError.requestBlocked
        }
        guard updatedStatus == .accepted else {
            throw CloudKitSocialError.requestNotFound
        }
        if existingOwnStatus == .accepted,
           reciprocalStatus == .requested || reciprocalStatus == .accepted {
            return
        }
        if existingOwnStatus == .requested,
           reciprocalStatus == .requested || reciprocalStatus == .accepted {
            return
        }
        throw CloudKitSocialError.requestNotFound
    }
}

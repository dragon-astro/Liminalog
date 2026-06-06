import Foundation

enum CloudFriendConsentPolicy {
    static func statusForOutgoingRequest(
        existingOwnStatus: CloudFriendConsent.Status?,
        reciprocalStatus: CloudFriendConsent.Status?
    ) throws -> CloudFriendConsent.Status {
        if existingOwnStatus == .blocked || reciprocalStatus == .blocked {
            throw CloudKitSocialError.requestBlocked
        }
        guard reciprocalStatus != nil else {
            return .requested
        }
        return .accepted
    }

    static func validateAcceptingRequest(existingOwnStatus: CloudFriendConsent.Status?) throws {
        if existingOwnStatus == .blocked {
            throw CloudKitSocialError.requestBlocked
        }
    }
}

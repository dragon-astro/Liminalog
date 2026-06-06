import Foundation

enum CloudFriendSharePublishPolicy {
    static func shouldPublishOutgoingShare(consentStatus: CloudFriendConsent.Status) -> Bool {
        consentStatus == .accepted
    }
}

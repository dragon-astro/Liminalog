import Foundation

enum CloudFriendReciprocalConsentPolicy {
    static func incomingShareURL(
        outgoingStatus: CloudFriendConsent.Status,
        reciprocalShareURL: String?
    ) -> String? {
        guard outgoingStatus == .accepted else { return nil }
        return reciprocalShareURL
    }
}

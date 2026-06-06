import Foundation

enum CloudFriendConsentDirection: Equatable {
    case incoming
    case outgoing
}

enum CloudFriendConsentRestorePolicy {
    static func friendStatus(
        consentStatus: CloudFriendConsent.Status,
        direction: CloudFriendConsentDirection
    ) -> FriendStatus {
        switch consentStatus {
        case .accepted:
            return .accepted
        case .blocked:
            return .blocked
        case .requested:
            return direction == .incoming ? .pendingIncoming : .pendingOutgoing
        }
    }

    static func friendUserRecordName(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerUserRecordName
        case .outgoing:
            return consent.targetUserRecordName
        }
    }

    static func friendUsername(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerUsername
        case .outgoing:
            return consent.targetUsername
        }
    }

    static func friendDisplayName(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String {
        switch direction {
        case .incoming:
            return consent.ownerDisplayName
        case .outgoing:
            return "@\(consent.targetUsername)"
        }
    }

    static func incomingShareURL(
        from consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection
    ) -> String? {
        direction == .incoming ? consent.shareURL : nil
    }
}

import Foundation

enum CloudFriendLocalStatePolicy {
    static let cloudRequestAutomaticRefreshCooldown: TimeInterval = 120
    static let outgoingLifecycleRefreshCooldown: TimeInterval = 600

    static func canAcceptWithoutCloudConsent(userRecordID: String) -> Bool {
        userRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldKeepIncomingShare(status: FriendStatus, incomingShareURL: String?) -> Bool {
        guard status == .accepted else { return false }
        return !(incomingShareURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func shouldRejectOutgoingRequest(existingStatus: FriendStatus?) -> Bool {
        existingStatus == .blocked
    }

    static func shouldDowngradeAcceptedCloudFriend(
        status: FriendStatus,
        userRecordID: String,
        acceptedCloudFriendRecordNames: Set<String>
    ) -> Bool {
        guard status == .accepted else { return false }
        let trimmedRecordID = userRecordID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRecordID.isEmpty else { return false }
        return !acceptedCloudFriendRecordNames.contains(trimmedRecordID)
    }

    static func shouldRefreshCloudRequests(
        trigger: CloudFriendRequestRefreshTrigger,
        currentUserRecordName: String?,
        loadedUserRecordName: String?,
        lastAutomaticAttemptAt: Date?,
        now: Date,
        cooldown: TimeInterval = cloudRequestAutomaticRefreshCooldown
    ) -> Bool {
        let currentUserRecordName = currentUserRecordName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !currentUserRecordName.isEmpty else { return false }

        switch trigger {
        case .manual, .event:
            return true
        case .automatic:
            if loadedUserRecordName == currentUserRecordName {
                return false
            }
            if let lastAutomaticAttemptAt, now.timeIntervalSince(lastAutomaticAttemptAt) < cooldown {
                return false
            }
            return true
        }
    }

    static func shouldScheduleOutgoingLifecycleShareRefresh(
        hasPendingExplicitRefresh: Bool,
        lastAutomaticScheduledAt: Date?,
        now: Date,
        cooldown: TimeInterval = outgoingLifecycleRefreshCooldown
    ) -> Bool {
        if hasPendingExplicitRefresh {
            return true
        }
        guard let lastAutomaticScheduledAt else {
            return true
        }
        return now.timeIntervalSince(lastAutomaticScheduledAt) >= cooldown
    }
}

enum CloudFriendRequestRefreshTrigger {
    case automatic
    case event
    case manual
}

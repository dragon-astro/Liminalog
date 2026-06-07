import Foundation

enum CloudFriendLocalStatePolicy {
    static func canAcceptWithoutCloudConsent(userRecordID: String) -> Bool {
        userRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldKeepIncomingShare(status: FriendStatus, incomingShareURL: String?) -> Bool {
        guard status == .accepted else { return false }
        return !(incomingShareURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
}

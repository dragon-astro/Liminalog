import Foundation

enum CloudFriendLocalStatePolicy {
    static func canAcceptWithoutCloudConsent(userRecordID: String) -> Bool {
        userRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldKeepIncomingShare(status: FriendStatus, incomingShareURL: String?) -> Bool {
        guard status == .accepted else { return false }
        return !(incomingShareURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

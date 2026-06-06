import Foundation

enum CloudFriendLocalStatePolicy {
    static func canAcceptWithoutCloudConsent(userRecordID: String) -> Bool {
        userRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldKeepIncomingShare(status: FriendStatus) -> Bool {
        status == .accepted
    }
}

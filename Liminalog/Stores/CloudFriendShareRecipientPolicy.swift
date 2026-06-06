import Foundation

enum CloudFriendShareRecipientPolicy {
    static func canApplySnapshot(_ snapshot: CloudFriendShareSnapshot, currentUserRecordName: String) -> Bool {
        snapshot.targetUserRecordName == currentUserRecordName
    }
}

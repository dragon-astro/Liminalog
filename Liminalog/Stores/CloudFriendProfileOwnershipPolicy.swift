import Foundation

enum CloudFriendProfileOwnershipPolicy {
    static func canReuseProfile(_ profile: CloudFriendProfile, currentUserRecordName: String) -> Bool {
        profile.ownerUserRecordName == currentUserRecordName
    }
}

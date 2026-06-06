import CloudKit
import Foundation

enum CloudFriendShareRefreshFailurePolicy {
    static func shouldClearCachedShare(after error: Error) -> Bool {
        switch error {
        case CloudFriendShareError.missingRootRecord,
             CloudFriendShareError.invalidSnapshotPayload:
            return true
        default:
            break
        }

        guard let cloudError = error as? CKError else { return false }
        switch cloudError.code {
        case .unknownItem, .permissionFailure:
            return true
        default:
            return false
        }
    }
}

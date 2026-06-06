import Foundation

enum CloudFriendShareUpsertRepairPolicy {
    static func shouldRecreateRootAndShare(after error: Error) -> Bool {
        guard let shareError = error as? CloudFriendShareError else {
            return false
        }
        switch shareError {
        case .missingShareURL:
            return true
        case .accountUnavailable,
             .missingRootRecord,
             .invalidSnapshotPayload,
             .snapshotTargetMismatch,
             .saveResultMissing:
            return false
        }
    }
}

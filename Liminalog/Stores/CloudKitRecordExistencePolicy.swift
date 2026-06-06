import CloudKit
import Foundation

enum CloudKitRecordExistencePolicy {
    static func shouldTreatFetchErrorAsMissing(_ error: Error) -> Bool {
        if let cloudError = error as? CKError {
            return cloudError.code == .unknownItem
        }
        if let socialError = error as? CloudKitSocialError {
            switch socialError {
            case .profileNotFound:
                return true
            case .accountUnavailable,
                 .invalidUserID,
                 .usernameTaken,
                 .usernameAlreadyRegistered,
                 .ownProfileMissing,
                 .cannotRequestSelf,
                 .requestBlocked,
                 .requestNotFound,
                 .missingRecordField:
                return false
            }
        }
        if let shareError = error as? CloudFriendShareError {
            switch shareError {
            case .missingRootRecord:
                return true
            case .accountUnavailable,
                 .missingShareURL,
                 .invalidSnapshotPayload,
                 .snapshotTargetMismatch,
                 .saveResultMissing:
                return false
            }
        }
        return false
    }
}

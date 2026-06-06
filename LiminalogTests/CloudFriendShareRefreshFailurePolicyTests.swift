import CloudKit
import Foundation
import Testing
@testable import Liminalog

struct CloudFriendShareRefreshFailurePolicyTests {
    @Test
    func clearsCacheWhenSharedRootRecordIsMissing() {
        #expect(CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: CloudFriendShareError.missingRootRecord))
    }

    @Test
    func clearsCacheWhenSharedPayloadIsUnreadable() {
        #expect(CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: CloudFriendShareError.invalidSnapshotPayload))
    }

    @Test
    func clearsCacheWhenSnapshotTargetsAnotherUser() {
        #expect(CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: CloudFriendShareError.snapshotTargetMismatch))
    }

    @Test
    func clearsCacheWhenCloudKitRecordDisappears() {
        let error = CKError(.unknownItem)

        #expect(CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error))
    }

    @Test
    func keepsCacheForTransientNetworkFailure() {
        let error = CKError(.networkUnavailable)

        #expect(!CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error))
    }
}

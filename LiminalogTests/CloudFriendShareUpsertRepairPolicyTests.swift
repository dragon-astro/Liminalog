import CloudKit
import Testing
@testable import Liminalog

struct CloudFriendShareUpsertRepairPolicyTests {
    @Test
    func recreatesShareWhenExistingRootLostShareURL() {
        #expect(CloudFriendShareUpsertRepairPolicy.shouldRecreateRootAndShare(
            after: CloudFriendShareError.missingShareURL
        ))
    }

    @Test
    func doesNotRecreateShareForTransientCloudKitErrors() {
        let error = CKError(.networkUnavailable)

        #expect(!CloudFriendShareUpsertRepairPolicy.shouldRecreateRootAndShare(after: error))
    }

    @Test
    func doesNotRecreateShareForInvalidIncomingSnapshotErrors() {
        #expect(!CloudFriendShareUpsertRepairPolicy.shouldRecreateRootAndShare(
            after: CloudFriendShareError.snapshotTargetMismatch
        ))
    }
}

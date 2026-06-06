import Foundation
import Testing
@testable import Liminalog

struct CloudFriendShareRecipientPolicyTests {
    @Test
    func acceptsSnapshotTargetedToCurrentUser() {
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "owner",
            ownerDisplayName: "Owner",
            targetUserRecordName: "_current"
        )

        #expect(CloudFriendShareRecipientPolicy.canApplySnapshot(snapshot, currentUserRecordName: "_current"))
    }

    @Test
    func rejectsSnapshotTargetedToAnotherUser() {
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "owner",
            ownerDisplayName: "Owner",
            targetUserRecordName: "_other"
        )

        #expect(!CloudFriendShareRecipientPolicy.canApplySnapshot(snapshot, currentUserRecordName: "_current"))
    }
}

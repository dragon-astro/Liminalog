import Testing
@testable import Liminalog

struct CloudFriendProfileOwnershipPolicyTests {
    @Test
    func canReuseProfileOwnedByCurrentICloudUser() {
        let profile = CloudFriendProfile(
            username: "ryu",
            displayName: "Ryu",
            ownerUserRecordName: "_owner",
            ownerAppUserID: "app-user"
        )

        #expect(CloudFriendProfileOwnershipPolicy.canReuseProfile(profile, currentUserRecordName: "_owner"))
    }

    @Test
    func cannotReuseProfileOwnedByAnotherICloudUser() {
        let profile = CloudFriendProfile(
            username: "ryu",
            displayName: "Ryu",
            ownerUserRecordName: "_other",
            ownerAppUserID: "app-user"
        )

        #expect(!CloudFriendProfileOwnershipPolicy.canReuseProfile(profile, currentUserRecordName: "_owner"))
    }
}

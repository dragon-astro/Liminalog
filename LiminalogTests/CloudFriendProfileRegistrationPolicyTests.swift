import Testing
@testable import Liminalog

struct CloudFriendProfileRegistrationPolicyTests {
    @Test
    func allowsFirstProfileRegistration() {
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu",
            existingOwnerUsername: nil
        ))
    }

    @Test
    func allowsReclaimingSameProfileAfterLocalDataLoss() {
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu",
            existingOwnerUsername: "ryu"
        ))
    }

    @Test
    func blocksChangingUsernameForSameCloudOwner() {
        #expect(!CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "new.ryu",
            existingOwnerUsername: "ryu"
        ))
    }
}

import Testing
@testable import Liminalog

struct CloudFriendProfileRegistrationPolicyTests {
    @Test
    func allowsFirstProfileRegistration() {
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu",
            registeredUsername: nil
        ))
    }

    @Test
    func allowsReclaimingSameProfileAfterLocalDataLoss() {
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu",
            registeredUsername: "ryu"
        ))
    }

    @Test
    func blocksChangingUsernameForSameCloudOwner() {
        #expect(!CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "new.ryu",
            registeredUsername: "ryu"
        ))
    }

    @Test
    func allowsReclaimingSameProfileWhenOwnerIndexHasMixedCase() {
        let registered = CloudFriendProfileRegistrationPolicy.registeredUsername(
            requestedUsername: "ryu.log",
            ownerIndexUsername: "Ryu.Log",
            ownedProfileUsernames: []
        )

        #expect(registered == "ryu.log")
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu.log",
            registeredUsername: registered
        ))
    }

    @Test
    func detectsLegacyProfilesCaseInsensitively() {
        let registered = CloudFriendProfileRegistrationPolicy.registeredUsername(
            requestedUsername: "ryu.log",
            ownerIndexUsername: nil,
            ownedProfileUsernames: ["Ryu.Log"]
        )

        #expect(registered == "ryu.log")
        #expect(CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu.log",
            registeredUsername: registered
        ))
    }

    @Test
    func usesOwnerIndexBeforeLegacyProfiles() {
        #expect(CloudFriendProfileRegistrationPolicy.registeredUsername(
            requestedUsername: "ryu",
            ownerIndexUsername: "indexed",
            ownedProfileUsernames: ["legacy"]
        ) == "indexed")
    }

    @Test
    func detectsLegacyProfileWhenOwnerIndexIsMissing() {
        #expect(CloudFriendProfileRegistrationPolicy.registeredUsername(
            requestedUsername: "new.ryu",
            ownerIndexUsername: nil,
            ownedProfileUsernames: ["ryu"]
        ) == "ryu")
    }

    @Test
    func blocksLegacyInconsistentMultipleProfiles() {
        let registered = CloudFriendProfileRegistrationPolicy.registeredUsername(
            requestedUsername: "ryu",
            ownerIndexUsername: nil,
            ownedProfileUsernames: ["ryu", "new.ryu"]
        )

        #expect(registered == "new.ryu")
        #expect(!CloudFriendProfileRegistrationPolicy.canRegister(
            requestedUsername: "ryu",
            registeredUsername: registered
        ))
    }
}

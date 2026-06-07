import Testing
@testable import Liminalog

struct CloudFriendLocalStatePolicyTests {
    @Test
    func localInviteCanBeAcceptedWithoutCloudConsent() {
        #expect(CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: ""))
        #expect(CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: "   "))
    }

    @Test
    func cloudFriendRequiresCloudConsentBeforeLocalAccept() {
        #expect(!CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: "_cloud-user-record"))
    }

    @Test
    func incomingShareIsKeptOnlyAfterAcceptance() {
        #expect(CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .accepted,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .accepted, incomingShareURL: nil))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .accepted, incomingShareURL: "   "))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .pendingIncoming,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .pendingOutgoing,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .blocked,
            incomingShareURL: "https://example.com/share"
        ))
    }

    @Test
    func acceptedCloudFriendDowngradesWhenAcceptedConsentIsMissing() {
        #expect(CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: ["_friend"]
        ))
    }

    @Test
    func localOrNonAcceptedFriendsDoNotDowngradeOnMissingConsent() {
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "   ",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .pendingOutgoing,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .blocked,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
    }
}

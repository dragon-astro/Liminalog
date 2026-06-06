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
        #expect(CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .accepted))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .pendingIncoming))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .pendingOutgoing))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .blocked))
    }
}

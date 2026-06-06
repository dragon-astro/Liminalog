import Testing
@testable import Liminalog

struct CloudFriendProfileRecordIDPolicyTests {
    @Test
    func profileRecordNameDoesNotEmbedRawUsername() {
        let username = "りゅう/ログ with spaces and symbols !!!"
        let recordName = CloudFriendProfileRecordIDPolicy.recordName(username: username)

        #expect(recordName.hasPrefix("profile:v2:"))
        #expect(!recordName.contains(username))
        #expect(recordName.count == "profile:v2:".count + 64)
    }

    @Test
    func profileLookupIncludesCurrentAndLegacyRecordNames() {
        let names = CloudFriendProfileRecordIDPolicy.lookupRecordNames(username: "ryu-log")

        #expect(names.count == 2)
        #expect(names[0] == CloudFriendProfileRecordIDPolicy.recordName(username: "ryu-log"))
        #expect(names[1] == "profile:ryu-log")
    }

    @Test
    func profileRecordNameIsStableForSameNormalizedUsername() {
        #expect(
            CloudFriendProfileRecordIDPolicy.recordName(username: "ryu-log")
                == CloudFriendProfileRecordIDPolicy.recordName(username: "ryu-log")
        )
        #expect(
            CloudFriendProfileRecordIDPolicy.recordName(username: "ryu-log")
                != CloudFriendProfileRecordIDPolicy.recordName(username: "ryu.log")
        )
    }
}

import Foundation
import Testing
@testable import Liminalog

struct FriendInvitePayloadTests {
    @Test
    func inviteURLRoundTrips() throws {
        let payload = FriendInvitePayload(
            code: "abc-123",
            displayName: "Ryu"
        )

        let decoded = try #require(FriendInvitePayload(url: payload.url))

        #expect(decoded.code == "ABC123")
        #expect(decoded.displayName == "Ryu")
        #expect(decoded.username == nil)
    }

    @Test
    func cloudUsernameInviteURLRoundTrips() throws {
        let payload = FriendInvitePayload(
            username: "ryu.log-01",
            displayName: "Ryu"
        )

        let decoded = try #require(FriendInvitePayload(url: payload.url))

        #expect(decoded.code == "RYU.LOG01")
        #expect(decoded.displayName == "Ryu")
        #expect(decoded.username == "ryu.log-01")
    }

    @Test
    func plainCodeInputIsAccepted() throws {
        let payload = try #require(FriendInvitePayload(text: " abcd-1234 "))

        #expect(payload.code == "ABCD1234")
        #expect(payload.displayName == "Liminalogユーザー")
    }

    @Test
    func otherURLSchemeIsRejected() {
        let payload = FriendInvitePayload(text: "https://example.com/friend?code=ABC")

        #expect(payload == nil)
    }
}

import Testing
@testable import Liminalog

@Suite("FriendRankingEngine")
struct FriendRankingEngineTests {
    @Test("スコアが高い順に連番ランクを付ける")
    func ranksByScoreDescending() {
        let placements = FriendRankingEngine.placements(for: [
            candidate("a", score: 120, name: "Aoi"),
            candidate("b", score: 220, name: "Beni"),
            candidate("c", score: 80, name: "Chika")
        ])

        #expect(placements.map(\.id) == ["b", "a", "c"])
        #expect(placements.map(\.rank) == [1, 2, 3])
    }

    @Test("完全同点では自分を先に置く")
    func currentUserWinsExactTie() {
        let placements = FriendRankingEngine.placements(for: [
            candidate("friend", score: 100, name: "Aoi"),
            candidate("me", score: 100, name: "Zed", isCurrentUser: true)
        ])

        #expect(placements.map(\.id) == ["me", "friend"])
    }

    @Test("同点では名前、ハンドル、安定IDの順に決定する")
    func tieBreaksByNameHandleAndStableID() {
        let placements = FriendRankingEngine.placements(for: [
            candidate("later", stableID: "z-id", score: 100, name: "Ren", handle: "ren"),
            candidate("first-id", stableID: "a-id", score: 100, name: "Ren", handle: "ren"),
            candidate("handle", stableID: "b-id", score: 100, name: "Ren", handle: "aki"),
            candidate("name", stableID: "c-id", score: 100, name: "Mika", handle: "mika")
        ])

        #expect(placements.map(\.id) == ["name", "handle", "first-id", "later"])
    }

    private func candidate(
        _ id: String,
        stableID: String? = nil,
        score: Double,
        name: String,
        handle: String = "",
        isCurrentUser: Bool = false
    ) -> FriendRankingCandidate<String> {
        FriendRankingCandidate(
            id: id,
            sortKey: FriendRankingSortKey(
                stableID: stableID ?? id,
                score: score,
                displayName: name,
                handle: handle,
                isCurrentUser: isCurrentUser
            )
        )
    }
}

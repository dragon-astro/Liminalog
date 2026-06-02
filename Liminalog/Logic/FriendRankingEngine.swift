import Foundation

struct FriendRankingSortKey: Equatable, Sendable {
    let stableID: String
    let score: Double
    let displayName: String
    let handle: String
    let isCurrentUser: Bool
}

struct FriendRankingCandidate<ID: Hashable & Sendable>: Equatable, Sendable {
    let id: ID
    let sortKey: FriendRankingSortKey
}

struct FriendRankingPlacement<ID: Hashable & Sendable>: Equatable, Sendable {
    let id: ID
    let rank: Int
}

enum FriendRankingEngine {
    nonisolated static func placements<ID: Hashable & Sendable>(for candidates: [FriendRankingCandidate<ID>]) -> [FriendRankingPlacement<ID>] {
        candidates
            .sorted(by: shouldPrecede)
            .enumerated()
            .map { index, candidate in
                FriendRankingPlacement(id: candidate.id, rank: index + 1)
            }
    }

    nonisolated private static func shouldPrecede<ID: Hashable & Sendable>(
        _ lhs: FriendRankingCandidate<ID>,
        _ rhs: FriendRankingCandidate<ID>
    ) -> Bool {
        let lhsKey = lhs.sortKey
        let rhsKey = rhs.sortKey

        if lhsKey.score != rhsKey.score {
            return lhsKey.score > rhsKey.score
        }

        if lhsKey.isCurrentUser != rhsKey.isCurrentUser {
            return lhsKey.isCurrentUser
        }

        let nameComparison = normalizedName(lhsKey).localizedStandardCompare(normalizedName(rhsKey))
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        let handleComparison = normalizedHandle(lhsKey).localizedStandardCompare(normalizedHandle(rhsKey))
        if handleComparison != .orderedSame {
            return handleComparison == .orderedAscending
        }

        return lhsKey.stableID < rhsKey.stableID
    }

    nonisolated private static func normalizedName(_ key: FriendRankingSortKey) -> String {
        let name = key.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? normalizedHandle(key) : name
    }

    nonisolated private static func normalizedHandle(_ key: FriendRankingSortKey) -> String {
        key.handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

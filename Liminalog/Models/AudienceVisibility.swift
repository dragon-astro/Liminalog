import Foundation

enum AudienceSource: String, Codable, CaseIterable {
    case categoryDefaultSnapshot
    case custom
}

enum AudienceResolver {
    static func acceptedFriendIDs(from friends: [Friend]) -> Set<UUID> {
        Set(friends.filter { $0.status == .accepted }.map(\.id))
    }

    static func resolve(
        friendSetIDs: [UUID],
        includedFriendIDs: [UUID],
        excludedFriendIDs: [UUID],
        friendSets: [FriendSet],
        friends: [Friend]
    ) -> [UUID] {
        let selectedSetIDs = Set(friendSetIDs)
        let accepted = acceptedFriendIDs(from: friends)
        let setMembers = friendSets
            .filter { selectedSetIDs.contains($0.id) }
            .flatMap(\.memberFriendIDs)

        let resolved = Set(setMembers)
            .union(includedFriendIDs)
            .subtracting(excludedFriendIDs)
            .intersection(accepted)

        return friends
            .filter { resolved.contains($0.id) }
            .map(\.id)
    }

    static func categoryDefaultAudience(
        for category: Category?,
        friendSets: [FriendSet],
        friends: [Friend]
    ) -> [UUID] {
        guard let category else { return [] }
        return resolve(
            friendSetIDs: category.defaultAudienceFriendSetIDs,
            includedFriendIDs: category.defaultAudienceIncludedFriendIDs,
            excludedFriendIDs: category.defaultAudienceExcludedFriendIDs,
            friendSets: friendSets,
            friends: friends
        )
    }

    static func isFriendInAudience(
        isPublic: Bool,
        audienceFriendIDs: [UUID],
        hasAudienceSnapshot: Bool,
        friendID: UUID,
        acceptedFriendIDs: Set<UUID>
    ) -> Bool {
        guard isPublic else { return false }
        guard acceptedFriendIDs.contains(friendID) else { return false }
        if !hasAudienceSnapshot {
            return true
        }
        return audienceFriendIDs.contains(friendID)
    }
}

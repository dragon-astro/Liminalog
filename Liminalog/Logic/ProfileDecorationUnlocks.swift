import Foundation

struct ProfileDecorationUnlocks {
    static let defaultNameBadgeID = "starter"
    static let defaultIconFrameID = "halo"
    static let defaultStreakIconID = "flame"
    static let defaultCardStyleID = "clean"

    let nameBadgeIDs: Set<String>
    let iconFrameIDs: Set<String>
    let streakIconIDs: Set<String>
    let cardStyleIDs: Set<String>

    init(unlockItems: [UnlockItem]) {
        self.nameBadgeIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .nameBadge,
            defaultID: Self.defaultNameBadgeID
        )
        self.iconFrameIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .iconFrame,
            defaultID: Self.defaultIconFrameID
        )
        self.streakIconIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .streakIcon,
            defaultID: Self.defaultStreakIconID
        )
        self.cardStyleIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .cardStyle,
            defaultID: Self.defaultCardStyleID
        )
    }

    func badgeIsUnlocked(_ id: String) -> Bool {
        nameBadgeIDs.contains(id)
    }

    func iconFrameIsUnlocked(_ id: String) -> Bool {
        iconFrameIDs.contains(id)
    }

    func streakIconIsUnlocked(_ id: String) -> Bool {
        streakIconIDs.contains(id)
    }

    func cardStyleIsUnlocked(_ id: String) -> Bool {
        cardStyleIDs.contains(id)
    }

    func equippedBadgeID(_ requestedID: String?) -> String {
        equippedID(requestedID, unlockedIDs: nameBadgeIDs, defaultID: Self.defaultNameBadgeID)
    }

    func equippedIconFrameID(_ requestedID: String?) -> String {
        equippedID(requestedID, unlockedIDs: iconFrameIDs, defaultID: Self.defaultIconFrameID)
    }

    func equippedStreakIconID(_ requestedID: String?) -> String {
        equippedID(requestedID, unlockedIDs: streakIconIDs, defaultID: Self.defaultStreakIconID)
    }

    func equippedCardStyleID(_ requestedID: String?) -> String {
        equippedID(requestedID, unlockedIDs: cardStyleIDs, defaultID: Self.defaultCardStyleID)
    }

    private static func unlockedTargetIDs(
        in unlockItems: [UnlockItem],
        kind: UnlockKind,
        defaultID: String
    ) -> Set<String> {
        var ids = Set([defaultID])
        ids.formUnion(
            unlockItems
                .filter { $0.kind == kind && $0.unlockedAt != nil && !$0.targetID.isEmpty }
                .map(\.targetID)
        )
        return ids
    }

    private func equippedID(
        _ requestedID: String?,
        unlockedIDs: Set<String>,
        defaultID: String
    ) -> String {
        guard let requestedID, unlockedIDs.contains(requestedID) else {
            return defaultID
        }
        return requestedID
    }
}

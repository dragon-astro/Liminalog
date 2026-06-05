import Foundation

struct ProfileDecorationUnlocks {
    static let noNameBadgeID = "none"
    static let noIconFrameID = "none"
    static let noStreakIconID = "none"
    static let noCardStyleID = "none"
    static let defaultNameBadgeID = "starter"
    static let defaultIconFrameID = "clear_air"
    static let defaultStreakIconID = "flame"
    static let defaultCardStyleID = "quiet_sky"
    static let defaultThemeID = LiminalThemeCatalog.systemThemeID
    static let fixedDefaultThemeIDs = Set(LiminalThemeCatalog.fixedDefaultThemes.map(\.id))

    let nameBadgeIDs: Set<String>
    let iconFrameIDs: Set<String>
    let streakIconIDs: Set<String>
    let cardStyleIDs: Set<String>
    let themeIDs: Set<String>

    init(unlockItems: [UnlockItem], includesLockedCatalogItems: Bool = false) {
        var themeIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .theme,
            defaultID: Self.defaultThemeID,
            unequippedID: nil
        )
        var nameBadgeIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .nameBadge,
            defaultID: Self.defaultNameBadgeID,
            unequippedID: Self.noNameBadgeID
        )
        var iconFrameIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .iconFrame,
            defaultID: Self.defaultIconFrameID,
            unequippedID: Self.noIconFrameID
        )
        var streakIconIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .streakIcon,
            defaultID: Self.defaultStreakIconID,
            unequippedID: nil
        )
        var cardStyleIDs = Self.unlockedTargetIDs(
            in: unlockItems,
            kind: .cardStyle,
            defaultID: Self.defaultCardStyleID,
            unequippedID: Self.noCardStyleID
        )

        #if DEBUG
        if includesLockedCatalogItems {
            themeIDs.formUnion(Self.targetIDs(in: unlockItems, kind: .theme))
            nameBadgeIDs.formUnion(Self.targetIDs(in: unlockItems, kind: .nameBadge))
            iconFrameIDs.formUnion(Self.targetIDs(in: unlockItems, kind: .iconFrame))
            streakIconIDs.formUnion(Self.targetIDs(in: unlockItems, kind: .streakIcon))
            cardStyleIDs.formUnion(Self.targetIDs(in: unlockItems, kind: .cardStyle))
        }
        #endif

        self.themeIDs = themeIDs
        self.nameBadgeIDs = nameBadgeIDs
        self.iconFrameIDs = iconFrameIDs
        self.streakIconIDs = streakIconIDs
        self.cardStyleIDs = cardStyleIDs
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

    func themeIsUnlocked(_ id: String) -> Bool {
        id == Self.defaultThemeID || Self.fixedDefaultThemeIDs.contains(id) || themeIDs.contains(id)
    }

    func equippedThemeID(_ requestedID: String?) -> String {
        guard let requestedID, requestedID != Self.defaultThemeID else { return Self.defaultThemeID }
        if Self.fixedDefaultThemeIDs.contains(requestedID) { return requestedID }
        return themeIDs.contains(requestedID) ? requestedID : Self.defaultThemeID
    }

    static func freshUnlockedItems(
        unlockItems: [UnlockItem],
        settings: UserSettings?,
        visibleThemeIDs: Set<String>
    ) -> [UnlockItem] {
        let unlocks = ProfileDecorationUnlocks(unlockItems: unlockItems)
        let seenKeys = Set(settings?.seenUnlockItemKeys ?? [])
            .union(settings?.equippedUnlockItemKeys ?? [])
        let equippedBadgeID = unlocks.equippedBadgeID(settings?.profileBadgeID)
        let equippedIconFrameID = unlocks.equippedIconFrameID(settings?.profileIconFrameID)
        let equippedStreakIconID = unlocks.equippedStreakIconID(settings?.profileStreakIconID)
        let equippedCardStyleID = unlocks.equippedCardStyleID(settings?.profileCardStyleID)
        let equippedThemeID = unlocks.equippedThemeID(settings?.themeName)

        return unlockItems
            .filter { item in
                guard
                    item.unlockedAt != nil,
                    !item.key.isEmpty,
                    !item.targetID.isEmpty,
                    !seenKeys.contains(item.key)
                else { return false }

                switch item.kind {
                case .nameBadge:
                    return item.targetID != equippedBadgeID
                case .iconFrame:
                    return item.targetID != equippedIconFrameID
                case .streakIcon:
                    return item.targetID != equippedStreakIconID
                case .cardStyle:
                    return item.targetID != equippedCardStyleID
                case .theme:
                    return visibleThemeIDs.contains(item.targetID) && item.targetID != equippedThemeID
                case .iconSet, .barStyle, .monthArt:
                    return false
                }
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.key < $1.key
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func markEquippedItem(
        kind: UnlockKind,
        targetID: String,
        unlockItems: [UnlockItem],
        settings: UserSettings
    ) {
        let kindKeys = Set(
            unlockItems
                .filter { $0.kind == kind && !$0.key.isEmpty }
                .map(\.key)
        )
        if !kindKeys.isEmpty {
            settings.equippedUnlockItemKeys.removeAll { kindKeys.contains($0) }
        }

        guard
            let key = unlockItems.first(where: { item in
                item.kind == kind
                    && item.targetID == targetID
                    && item.unlockedAt != nil
                    && !item.key.isEmpty
            })?.key
        else { return }

        settings.equippedUnlockItemKeys.append(key)
    }

    private static func unlockedTargetIDs(
        in unlockItems: [UnlockItem],
        kind: UnlockKind,
        defaultID: String,
        unequippedID: String?
    ) -> Set<String> {
        var ids = Set([defaultID])
        if let unequippedID {
            ids.insert(unequippedID)
        }
        ids.formUnion(
            unlockItems
                .filter { $0.kind == kind && $0.unlockedAt != nil && !$0.targetID.isEmpty }
                .map(\.targetID)
        )
        return ids
    }

    private static func targetIDs(in unlockItems: [UnlockItem], kind: UnlockKind) -> Set<String> {
        Set(
            unlockItems
                .filter { $0.kind == kind && !$0.targetID.isEmpty }
                .map(\.targetID)
        )
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

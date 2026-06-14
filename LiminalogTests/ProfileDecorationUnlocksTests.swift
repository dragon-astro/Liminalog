import Foundation
import Testing
@testable import Liminalog

@MainActor
struct ProfileDecorationUnlocksTests {
    @Test
    func defaultProfileDecorationsAreAlwaysAvailable() {
        let unlocks = ProfileDecorationUnlocks(unlockItems: [])

        #expect(unlocks.badgeIsUnlocked("starter"))
        #expect(unlocks.iconFrameIsUnlocked("clear_air"))
        #expect(unlocks.streakIconIsUnlocked("flame"))
        #expect(unlocks.cardStyleIsUnlocked("quiet_sky"))
        #expect(unlocks.iconFrameIsUnlocked("none"))
        #expect(!unlocks.streakIconIsUnlocked("none"))
        #expect(!unlocks.cardStyleIsUnlocked("none"))
        #expect(unlocks.equippedBadgeID("locked_badge") == "starter")
        #expect(unlocks.equippedIconFrameID("locked_frame") == "clear_air")
        #expect(unlocks.equippedIconFrameID("none") == "none")
        #expect(unlocks.equippedStreakIconID("none") == "flame")
        #expect(unlocks.equippedStreakIconID("purple_flame") == "flame")
        #expect(unlocks.equippedCardStyleID("locked_card") == "quiet_sky")
        #expect(unlocks.equippedCardStyleID("none") == "quiet_sky")
        #expect(unlocks.themeIsUnlocked("default"))
        #expect(unlocks.themeIsUnlocked("dusk"))
        #expect(unlocks.themeIsUnlocked("daybreak"))
        #expect(unlocks.equippedThemeID("dusk") == "dusk")
        #expect(unlocks.equippedThemeID("daybreak") == "daybreak")
    }

    @Test
    func unlockedItemsExposeTheirTargetIDsByDecorationKind() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let ironFrame = try unlockedItem(key: "frame.free_instrument_iron", now: now)
        let yellowFlame = try unlockedItem(key: "streak.yellow_flame", now: now)
        let threadCard = try unlockedItem(key: "card.free_thread_border_panel", now: now)
        let lockedPlatinum = try #require(UnlockCatalog.items.first { $0.key == "frame.free_instrument_platinum" }).item()

        let unlocks = ProfileDecorationUnlocks(
            unlockItems: [planner, ironFrame, yellowFlame, threadCard, lockedPlatinum]
        )

        #expect(unlocks.badgeIsUnlocked("planner"))
        #expect(unlocks.iconFrameIsUnlocked("free_instrument_iron"))
        #expect(unlocks.streakIconIsUnlocked("yellow_flame"))
        #expect(unlocks.cardStyleIsUnlocked("free_thread_border_panel"))
        #expect(!unlocks.iconFrameIsUnlocked("free_instrument_platinum"))
        #expect(unlocks.equippedBadgeID("planner") == "planner")
        #expect(unlocks.equippedIconFrameID("free_instrument_iron") == "free_instrument_iron")
        #expect(unlocks.equippedStreakIconID("yellow_flame") == "yellow_flame")
        #expect(unlocks.equippedCardStyleID("free_thread_border_panel") == "free_thread_border_panel")
        #expect(unlocks.equippedIconFrameID("free_instrument_platinum") == "clear_air")
    }

    @Test
    func cardStyleNoneIsLegacyOnlyAndDefaultCardIsVisible() {
        let unlocks = ProfileDecorationUnlocks(unlockItems: [])

        #expect(!unlocks.cardStyleIDs.contains(ProfileDecorationUnlocks.noCardStyleID))
        #expect(unlocks.cardStyleIDs.contains(ProfileDecorationUnlocks.defaultCardStyleID))
        #expect(!ProfileCardStyleCatalog.visibleItems.contains { $0.id == ProfileDecorationUnlocks.noCardStyleID })
        #expect(ProfileCardStyleCatalog.visibleItems.first?.id == ProfileDecorationUnlocks.defaultCardStyleID)
    }

    @Test
    func freshUnlockedItemsIgnoreSeenEquippedAndHiddenItems() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let threadCard = try unlockedItem(key: "card.free_thread_border_panel", now: now)
        let auroraTheme = try unlockedItem(key: "theme.aurora", now: now)
        // 非表示テーマ（カタログ外）の解放行を模す。掃除前のDBに残っていても通知に出ないこと。
        let futureTheme = UnlockItem()
        futureTheme.key = "theme.akane"
        futureTheme.kindRawValue = UnlockKind.theme.rawValue
        futureTheme.targetID = "akane"
        futureTheme.unlockedAt = now
        let settings = UserSettings()
        settings.profileBadgeID = "planner"
        settings.seenUnlockItemKeys = ["card.free_thread_border_panel"]

        let fresh = ProfileDecorationUnlocks.freshUnlockedItems(
            unlockItems: [planner, threadCard, auroraTheme, futureTheme],
            settings: settings,
            visibleThemeIDs: Set(["aurora"])
        )

        #expect(fresh.map(\.key) == ["theme.aurora"])
    }

    @Test
    func markingEquippedItemStoresOnlyCurrentUnlockedKeyForEachKind() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let keeper = try unlockedItem(key: "badge.promise_keeper", now: now)
        let ironFrame = try unlockedItem(key: "frame.free_instrument_iron", now: now)
        let lockedPlatinum = try lockedItem(key: "frame.free_instrument_platinum")
        let settings = UserSettings()

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .nameBadge,
            targetID: "planner",
            unlockItems: [planner, keeper, ironFrame, lockedPlatinum],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .nameBadge,
            targetID: "promise_keeper",
            unlockItems: [planner, keeper, ironFrame, lockedPlatinum],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: "free_instrument_iron",
            unlockItems: [planner, keeper, ironFrame, lockedPlatinum],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: "free_instrument_platinum",
            unlockItems: [planner, keeper, ironFrame, lockedPlatinum],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["badge.promise_keeper"])
    }

    @Test
    func equippingNoFrameClearsStaleFrameKeys() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let ironFrame = try unlockedItem(key: "frame.free_instrument_iron", now: now)
        let threadCard = try unlockedItem(key: "card.free_thread_border_panel", now: now)
        let settings = UserSettings()
        settings.equippedUnlockItemKeys = [
            "frame.none",
            "frame.free_instrument_bronze",
            "frame.free_instrument_iron",
            "card.free_thread_border_panel"
        ]

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: ProfileDecorationUnlocks.noIconFrameID,
            unlockItems: [ironFrame, threadCard],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["card.free_thread_border_panel", "frame.none"])
    }

    @Test
    func equippingFrameClearsStaleNoFrameKey() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let ironFrame = try unlockedItem(key: "frame.free_instrument_iron", now: now)
        let settings = UserSettings()
        settings.equippedUnlockItemKeys = ["frame.none"]

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: "free_instrument_iron",
            unlockItems: [ironFrame],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["frame.free_instrument_iron"])
    }

    @Test
    func equippingDefaultFrameClearsNoFrameKey() {
        let settings = UserSettings()
        settings.equippedUnlockItemKeys = ["frame.none"]

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: ProfileDecorationUnlocks.defaultIconFrameID,
            unlockItems: [],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["frame.clear_air"])
    }

    @Test
    func equippedFramePrefersLatestEquippedFrameKeyOverStaleProfileID() {
        let settings = UserSettings()
        settings.profileIconFrameID = ProfileDecorationUnlocks.noIconFrameID
        settings.equippedUnlockItemKeys = [
            "frame.none",
            "frame.clear_air"
        ]
        let unlocks = ProfileDecorationUnlocks(unlockItems: [])

        #expect(unlocks.equippedIconFrameID(settings: settings) == ProfileDecorationUnlocks.defaultIconFrameID)
    }

    @Test
    func equippedFrameKeepsNoneWhenNoneIsTheLatestEquippedKey() {
        let settings = UserSettings()
        settings.profileIconFrameID = ProfileDecorationUnlocks.defaultIconFrameID
        settings.equippedUnlockItemKeys = [
            "frame.clear_air",
            "frame.none"
        ]
        let unlocks = ProfileDecorationUnlocks(unlockItems: [])

        #expect(unlocks.equippedIconFrameID(settings: settings) == ProfileDecorationUnlocks.noIconFrameID)
    }

    @Test
    func equippingDefaultCardClearsPreviousCardKey() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let threadCard = try unlockedItem(key: "card.free_thread_border_panel", now: now)
        let settings = UserSettings()

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .cardStyle,
            targetID: "free_thread_border_panel",
            unlockItems: [threadCard],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["card.free_thread_border_panel"])

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .cardStyle,
            targetID: ProfileDecorationUnlocks.noCardStyleID,
            unlockItems: [threadCard],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys.isEmpty)
    }

    @Test
    func badgeNamesDescribeTheEquippedItemNotTheCondition() {
        let badgeItems = UnlockCatalog.items.filter { $0.kind == .nameBadge }

        #expect(badgeItems.count == 32)
        #expect(badgeItems.first { $0.key == "badge.planner" }?.displayName == "予定実行型")
        #expect(badgeItems.first { $0.key == "badge.promise_keeper" }?.displayName == "予定安定型")
        #expect(badgeItems.first { $0.key == "badge.study_habit" }?.displayName == "勉強習慣型")
        #expect(badgeItems.first { $0.key == "badge.hobby_habit" }?.displayName == "趣味習慣型")
        #expect(!badgeItems.contains { $0.displayName.contains("有言実行5回") || $0.displayName.contains("自己最長3回") })
    }

}

private extension UnlockCatalogItem {
    func item() -> UnlockItem {
        UnlockItem(seed: self)
    }
}

private func unlockedItem(key: String, now: Date) throws -> UnlockItem {
    let item = try lockedItem(key: key)
    item.unlockedAt = now
    return item
}

private func lockedItem(key: String) throws -> UnlockItem {
    try #require(UnlockCatalog.items.first { $0.key == key }).item()
}

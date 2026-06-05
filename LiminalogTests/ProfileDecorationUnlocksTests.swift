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
        #expect(unlocks.cardStyleIsUnlocked("none"))
        #expect(unlocks.equippedBadgeID("locked_badge") == "starter")
        #expect(unlocks.equippedIconFrameID("locked_frame") == "clear_air")
        #expect(unlocks.equippedIconFrameID("none") == "none")
        #expect(unlocks.equippedStreakIconID("none") == "flame")
        #expect(unlocks.equippedStreakIconID("spark") == "flame")
        #expect(unlocks.equippedCardStyleID("locked_card") == "quiet_sky")
        #expect(unlocks.equippedCardStyleID("none") == "none")
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
        let cloudFrame = try unlockedItem(key: "frame.cloud_veil", now: now)
        let goldFlame = try unlockedItem(key: "streak.gold_flame", now: now)
        let threadCard = try unlockedItem(key: "card.thread_panel", now: now)
        let lockedHorizon = try #require(UnlockCatalog.items.first { $0.key == "frame.horizon_wreath" }).item()

        let unlocks = ProfileDecorationUnlocks(
            unlockItems: [planner, cloudFrame, goldFlame, threadCard, lockedHorizon]
        )

        #expect(unlocks.badgeIsUnlocked("planner"))
        #expect(unlocks.iconFrameIsUnlocked("cloud_veil"))
        #expect(unlocks.streakIconIsUnlocked("bolt"))
        #expect(unlocks.cardStyleIsUnlocked("thread_panel"))
        #expect(!unlocks.iconFrameIsUnlocked("horizon_wreath"))
        #expect(unlocks.equippedBadgeID("planner") == "planner")
        #expect(unlocks.equippedIconFrameID("cloud_veil") == "cloud_veil")
        #expect(unlocks.equippedStreakIconID("bolt") == "bolt")
        #expect(unlocks.equippedCardStyleID("thread_panel") == "thread_panel")
        #expect(unlocks.equippedIconFrameID("horizon_wreath") == "clear_air")
    }

    @Test
    func freshUnlockedItemsIgnoreSeenEquippedAndHiddenItems() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let threadCard = try unlockedItem(key: "card.thread_panel", now: now)
        let auroraTheme = try unlockedItem(key: "theme.aurora", now: now)
        let futureTheme = try unlockedItem(key: "theme.akane", now: now)
        let settings = UserSettings()
        settings.profileBadgeID = "planner"
        settings.seenUnlockItemKeys = ["card.thread_panel"]

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
        let cloudFrame = try unlockedItem(key: "frame.cloud_veil", now: now)
        let lockedHorizon = try lockedItem(key: "frame.horizon_wreath")
        let settings = UserSettings()

        ProfileDecorationUnlocks.markEquippedItem(
            kind: .nameBadge,
            targetID: "planner",
            unlockItems: [planner, keeper, cloudFrame, lockedHorizon],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .nameBadge,
            targetID: "promise_keeper",
            unlockItems: [planner, keeper, cloudFrame, lockedHorizon],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: "cloud_veil",
            unlockItems: [planner, keeper, cloudFrame, lockedHorizon],
            settings: settings
        )
        ProfileDecorationUnlocks.markEquippedItem(
            kind: .iconFrame,
            targetID: "horizon_wreath",
            unlockItems: [planner, keeper, cloudFrame, lockedHorizon],
            settings: settings
        )

        #expect(settings.equippedUnlockItemKeys == ["badge.promise_keeper"])
    }

}

@MainActor
struct ProfileUnlockTargetsTests {
    @Test
    func targetsSortByProgressAndLimit() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let threadCard = try lockedItem(key: "card.thread_panel")
        let cloudFrame = try lockedItem(key: "frame.cloud_veil")
        let goldFlame = try lockedItem(key: "streak.gold_flame")

        let targets = ProfileUnlockTargetCatalog.targets(
            metrics: UnlockMetrics(cumulativeScore: 800),
            unlockItems: [cloudFrame, goldFlame, planner, threadCard],
            limit: 2
        )

        #expect(targets.map(\.key) == ["frame.cloud_veil", "card.thread_panel"])
        #expect(targets[0].remainingValue == 0)
        #expect(targets[0].progressPercent == 100)
        #expect(targets[0].conditionText == "継続XP 300pt")
        #expect(targets[0].progressText == "300 / 300pt・100%")
        #expect(targets[0].kindTitle == "フレーム")
        #expect(targets[1].requirementKind == .cumulativeScore)
        #expect(targets[1].remainingValue == 1_900)
        #expect(targets[1].remainingText == "あと 1,900pt")
        #expect(targets[1].progressText == "800 / 2,700pt・29%")
    }

    @Test
    func badgeNamesDescribeTheEquippedItemNotTheCondition() throws {
        let badgeItems = UnlockCatalog.items.filter { $0.kind == .nameBadge }

        #expect(badgeItems.count == 20)
        #expect(badgeItems.first { $0.key == "badge.planner" }?.displayName == "計画派")
        #expect(badgeItems.first { $0.key == "badge.promise_keeper" }?.displayName == "約束の人")
        #expect(!badgeItems.contains { $0.displayName.contains("有言実行5回") || $0.displayName.contains("自己最長3回") })
    }

    @Test
    func targetsReturnEmptyWhenEverythingIsUnlocked() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let planner = try unlockedItem(key: "badge.planner", now: now)
        let threadCard = try unlockedItem(key: "card.thread_panel", now: now)

        let targets = ProfileUnlockTargetCatalog.targets(
            cumulativeScore: 10_000,
            unlockItems: [planner, threadCard]
        )

        #expect(targets.isEmpty)
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

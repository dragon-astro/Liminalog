import Foundation
import Testing
@testable import Liminalog

@MainActor
struct ProfileDecorationUnlocksTests {
    @Test
    func defaultProfileDecorationsAreAlwaysAvailable() {
        let unlocks = ProfileDecorationUnlocks(unlockItems: [])

        #expect(unlocks.badgeIsUnlocked("starter"))
        #expect(unlocks.iconFrameIsUnlocked("halo"))
        #expect(unlocks.streakIconIsUnlocked("flame"))
        #expect(unlocks.cardStyleIsUnlocked("clean"))
        #expect(unlocks.equippedBadgeID("locked_badge") == "starter")
        #expect(unlocks.equippedIconFrameID("crown") == "halo")
        #expect(unlocks.equippedStreakIconID("spark") == "flame")
        #expect(unlocks.equippedCardStyleID("mint") == "clean")
    }

    @Test
    func unlockedItemsExposeTheirTargetIDsByDecorationKind() throws {
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let firstRecord = try unlockedItem(key: "badge.first_record", now: now)
        let signalFrame = try unlockedItem(key: "frame.signal", now: now)
        let goldFlame = try unlockedItem(key: "streak.gold_flame", now: now)
        let glassCard = try unlockedItem(key: "card.glass", now: now)
        let lockedCrown = try #require(UnlockCatalog.items.first { $0.key == "frame.crown" }).item()

        let unlocks = ProfileDecorationUnlocks(
            unlockItems: [firstRecord, signalFrame, goldFlame, glassCard, lockedCrown]
        )

        #expect(unlocks.badgeIsUnlocked("first_record"))
        #expect(unlocks.iconFrameIsUnlocked("signal"))
        #expect(unlocks.streakIconIsUnlocked("bolt"))
        #expect(unlocks.cardStyleIsUnlocked("glass"))
        #expect(!unlocks.iconFrameIsUnlocked("crown"))
        #expect(unlocks.equippedBadgeID("first_record") == "first_record")
        #expect(unlocks.equippedIconFrameID("signal") == "signal")
        #expect(unlocks.equippedStreakIconID("bolt") == "bolt")
        #expect(unlocks.equippedCardStyleID("glass") == "glass")
        #expect(unlocks.equippedIconFrameID("crown") == "halo")
    }

    private func unlockedItem(key: String, now: Date) throws -> UnlockItem {
        let item = try #require(UnlockCatalog.items.first { $0.key == key }).item()
        item.unlockedAt = now
        return item
    }
}

private extension UnlockCatalogItem {
    func item() -> UnlockItem {
        UnlockItem(seed: self)
    }
}

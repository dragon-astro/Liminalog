import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct UnlockRulesTests {
    @Test
    func catalogMatchesOneYearReleaseCurve() {
        let items = UnlockCatalog.items
        let thresholds = items.map(\.requiredCumulativeScore)

        #expect(items.count == 26)
        #expect(Set(items.map(\.key)).count == 26)
        #expect(Set(items.map(\.sortOrder)).count == 26)
        #expect(thresholds == thresholds.sorted())
        #expect(thresholds.first == 7 * UnlockCatalog.scorePerPassingDay)
        #expect(thresholds.last == 365 * UnlockCatalog.scorePerPassingDay)
        #expect(Array(UnlockCatalog.releaseScheduleDays.prefix(12)) == [7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84])
        #expect(Array(UnlockCatalog.releaseScheduleDays.suffix(3)) == [300, 330, 365])
    }

    @Test
    func rulesUnlockItemsAtCumulativeScoreThresholds() {
        #expect(UnlockRules.unlockedKeys(cumulativeScore: -1).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 0).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 419).isEmpty)

        let firstThresholdKeys = UnlockRules.unlockedKeys(cumulativeScore: 420)
        #expect(firstThresholdKeys == Set(["badge.first_record"]))

        let secondThresholdKeys = UnlockRules.unlockedKeys(cumulativeScore: 840)
        #expect(secondThresholdKeys == Set(["badge.first_record", "card.glass"]))

        let allKeys = UnlockRules.unlockedKeys(cumulativeScore: 21_900)
        #expect(allKeys.count == 26)
        #expect(allKeys.contains("theme.ruri"))
    }

    @Test
    func storeSeedsMasterItemsAndDoesNotDuplicateOnRepeatedSeed() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = UnlockStore(modelContext: context)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        store.seedMasterItems(now: now)
        store.seedMasterItems(now: now)

        let items = try context.fetch(FetchDescriptor<UnlockItem>())
        #expect(items.count == 26)
        #expect(Set(items.map(\.key)).count == 26)
        let first = try #require(items.first { $0.key == "badge.first_record" })
        #expect(first.kind == .nameBadge)
        #expect(first.requiredCumulativeScore == 420)
        #expect(first.targetID == "first_record")
    }

    @Test
    func storeConsolidatesDuplicateKeysAndKeepsEarliestUnlockDate() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let seed = try #require(UnlockCatalog.items.first { $0.key == "card.glass" })
        let olderCreatedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let olderUnlock = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let newerCreatedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        let newerUnlock = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let primary = UnlockItem(seed: seed, now: olderCreatedAt)
        primary.unlockedAt = newerUnlock
        let duplicate = UnlockItem(seed: seed, now: newerCreatedAt)
        duplicate.unlockedAt = olderUnlock
        context.insert(primary)
        context.insert(duplicate)
        try context.save()

        UnlockStore(modelContext: context).seedMasterItems(now: now)

        let items = try context.fetch(FetchDescriptor<UnlockItem>())
        let glassItems = items.filter { $0.key == "card.glass" }
        #expect(items.count == 26)
        #expect(glassItems.count == 1)
        #expect(glassItems.first?.id == primary.id)
        #expect(glassItems.first?.unlockedAt == olderUnlock)
    }

    @Test
    func refreshUnlocksOnlyNewlyReachedItemsAndNeverRelocks() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = UnlockStore(modelContext: context)
        let firstUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let secondUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))

        let firstBatch = store.refresh(cumulativeScore: 840, now: firstUnlockTime)
        #expect(firstBatch.map(\.key) == ["badge.first_record", "card.glass"])

        let repeated = store.refresh(cumulativeScore: 840, now: secondUnlockTime)
        #expect(repeated.isEmpty)

        let lowerScore = store.refresh(cumulativeScore: 0, now: secondUnlockTime)
        #expect(lowerScore.isEmpty)

        let unlocked = try context.fetch(FetchDescriptor<UnlockItem>())
            .filter { $0.unlockedAt != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(unlocked.map(\.key) == ["badge.first_record", "card.glass"])
        #expect(unlocked.allSatisfy { $0.unlockedAt == firstUnlockTime })

        let next = try #require(store.nextLockedItem(cumulativeScore: 840))
        #expect(next.key == "frame.signal")
        #expect(UnlockRules.progress(cumulativeScore: 840, toward: next) > 0)
        #expect(UnlockRules.progress(cumulativeScore: 840, toward: next) < 1)
    }
}

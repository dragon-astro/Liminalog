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
        #expect(Set(UnlockKind.allCases) == Set([
            .theme,
            .iconFrame,
            .nameBadge,
            .streakIcon,
            .cardStyle,
            .iconSet,
            .barStyle,
            .monthArt
        ]))
        #expect(Set(items.map(\.kind)) == Set(UnlockKind.allCases))
        #expect(Array(UnlockCatalog.releaseScheduleDays.prefix(12)) == [7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84])
        #expect(Array(UnlockCatalog.releaseScheduleDays.suffix(3)) == [300, 330, 365])
        #expect(Set(items.map(\.requirementKind)).isSuperset(of: [
            .cumulativeScore,
            .recordedDays,
            .recordedHours,
            .streakDays,
            .earlyRecordDays,
            .lateNightRecordDays,
            .distinctCategoryCount
        ]))
    }

    @Test
    func rulesUnlockItemsAtRequirementThresholds() {
        #expect(UnlockRules.unlockedKeys(cumulativeScore: -1).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 0).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 839).isEmpty)

        let firstRecordKeys = UnlockRules.unlockedKeys(metrics: UnlockMetrics(recordedDays: 1))
        #expect(firstRecordKeys == Set(["badge.first_record"]))

        let firstScoreKeys = UnlockRules.unlockedKeys(cumulativeScore: 840)
        #expect(firstScoreKeys == Set(["card.glass"]))

        let patternKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                streakDays: 7,
                earlyRecordDays: 1,
                distinctCategoryCount: 3
            )
        )
        #expect(patternKeys == Set(["frame.signal", "streak.gold_flame", "badge.morning", "badge.seven_streak"]))

        let allKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                cumulativeScore: 21_900,
                recordedDays: 365,
                recordedHours: 10,
                streakDays: 30,
                earlyRecordDays: 7,
                lateNightRecordDays: 7,
                distinctCategoryCount: 5
            )
        )
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
        #expect(first.requirementKind == .recordedDays)
        #expect(first.requiredValue == 1)
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
    func storeMigratesLegacyUnlockKindsToEightItemModel() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let unlockedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let legacy = UnlockItem()
        legacy.key = "stamp.daybreak"
        legacy.kindRawValue = "stamp"
        legacy.displayName = "Daybreak Stamp"
        legacy.targetID = "daybreak"
        legacy.isBuiltIn = true
        legacy.unlockedAt = unlockedAt
        context.insert(legacy)
        try context.save()

        UnlockStore(modelContext: context).seedMasterItems(now: now)

        let items = try context.fetch(FetchDescriptor<UnlockItem>())
        #expect(items.count == 26)
        #expect(items.allSatisfy { !UnlockCatalog.legacyKeyReplacements.keys.contains($0.key) })
        let migrated = try #require(items.first { $0.key == "icon_set.daybreak" })
        #expect(migrated.kind == .iconSet)
        #expect(migrated.unlockedAt == unlockedAt)
        #expect(migrated.targetID == "daybreak")
    }

    @Test
    func refreshUnlocksOnlyNewlyReachedItemsAndNeverRelocks() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = UnlockStore(modelContext: context)
        let firstUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let secondUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))

        let metrics = UnlockMetrics(cumulativeScore: 840, recordedDays: 1)
        let firstBatch = store.refresh(metrics: metrics, now: firstUnlockTime)
        #expect(firstBatch.map(\.key) == ["badge.first_record", "card.glass"])

        let repeated = store.refresh(metrics: metrics, now: secondUnlockTime)
        #expect(repeated.isEmpty)

        let lowerScore = store.refresh(cumulativeScore: 0, now: secondUnlockTime)
        #expect(lowerScore.isEmpty)

        let unlocked = try context.fetch(FetchDescriptor<UnlockItem>())
            .filter { $0.unlockedAt != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(unlocked.map(\.key) == ["badge.first_record", "card.glass"])
        #expect(unlocked.allSatisfy { $0.unlockedAt == firstUnlockTime })

        let next = try #require(store.nextLockedItem(metrics: metrics))
        #expect(next.key == "badge.three_days")
        #expect(UnlockRules.progress(metrics: metrics, toward: next) > 0)
        #expect(UnlockRules.progress(metrics: metrics, toward: next) < 1)
    }

    @Test
    func refreshUnlocksPatternAndStreakItems() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = UnlockStore(modelContext: context)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let unlocked = store.refresh(
            metrics: UnlockMetrics(
                streakDays: 7,
                earlyRecordDays: 1,
                distinctCategoryCount: 3
            ),
            now: now
        )

        #expect(unlocked.map(\.key) == [
            "frame.signal",
            "streak.gold_flame",
            "badge.morning",
            "badge.seven_streak"
        ])
    }
}

import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct UnlockRulesTests {
    @Test
    func catalogMatchesOneYearReleaseCurve() {
        let items = UnlockCatalog.items

        #expect(items.count == 69)
        #expect(Set(items.map(\.key)).count == 69)
        #expect(Set(items.map(\.sortOrder)).count == 69)
        #expect(items.filter { $0.kind == .iconFrame }.count == 20)
        #expect(items.filter { $0.kind == .cardStyle }.count == 20)
        #expect(items.filter { $0.kind == .nameBadge }.count == 20)
        #expect(items.filter { $0.kind == .streakIcon }.count == 3)
        #expect(items.filter { $0.kind == .theme }.count == 6)
        #expect(Set(items.map(\.kind)) == Set([.theme, .iconFrame, .nameBadge, .streakIcon, .cardStyle]))
        #expect(Array(UnlockCatalog.releaseScheduleDays.prefix(12)) == [7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84])
        #expect(Array(UnlockCatalog.releaseScheduleDays.suffix(3)) == [300, 330, 365])
        #expect(Set(items.map(\.requirementKind)).isSuperset(of: [
            .cumulativeScore,
            .recordedDays,
            .recordedHours,
            .streakDays,
            .earlyRecordDays,
            .lateNightRecordDays,
            .planMatchedDays,
            .chargeDays,
            .morningPersonaDays,
            .nightPersonaDays,
            .recordingHabitDays,
            .personalBestDays,
            .returnAfterGapDays,
            .firstRecordDays,
            .balancedDays,
            .focusedDays,
            .changeSignalDays
        ]))
    }

    @Test
    func rulesUnlockItemsAtRequirementThresholds() {
        #expect(UnlockRules.unlockedKeys(cumulativeScore: -1).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 0).isEmpty)
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 21_900).count == 40)

        let plannerKeys = UnlockRules.unlockedKeys(metrics: UnlockMetrics(planMatchedDays: 5))
        #expect(plannerKeys == Set(["badge.planner"]))

        let patternKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                streakDays: 7,
                chargeDays: 5,
                personalBestDays: 3
            )
        )
        #expect(patternKeys == Set(["streak.gold_flame", "badge.restorer", "badge.updater"]))

        let allKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                cumulativeScore: 21_900,
                recordedDays: 10,
                recordedHours: 200,
                streakDays: 60,
                earlyRecordDays: 21,
                lateNightRecordDays: 14,
                distinctCategoryCount: 6,
                planMatchedDays: 30,
                chargeDays: 15,
                morningPersonaDays: 15,
                nightPersonaDays: 15,
                recordingHabitDays: 15,
                personalBestDays: 10,
                returnAfterGapDays: 8,
                firstRecordDays: 12,
                balancedDays: 5,
                focusedDays: 5,
                changeSignalDays: 10
            )
        )
        #expect(allKeys.count == 69)
        #expect(allKeys.contains("theme.tsukishiro"))
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
        #expect(items.count == 69)
        #expect(Set(items.map(\.key)).count == 69)
        let first = try #require(items.first { $0.key == "frame.cloud_veil" })
        #expect(first.kind == .iconFrame)
        #expect(first.requiredCumulativeScore == 300)
        #expect(first.requirementKind == .cumulativeScore)
        #expect(first.requiredValue == 300)
        #expect(first.targetID == "cloud_veil")
    }

    @Test
    func storeConsolidatesDuplicateKeysAndKeepsEarliestUnlockDate() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let seed = try #require(UnlockCatalog.items.first { $0.key == "card.thread_panel" })
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
        let threadItems = items.filter { $0.key == "card.thread_panel" }
        #expect(items.count == 69)
        #expect(threadItems.count == 1)
        #expect(threadItems.first?.id == primary.id)
        #expect(threadItems.first?.unlockedAt == olderUnlock)
    }

    @Test
    func storeRemovesRetiredBuiltInDecorationItems() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let unlockedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let retiredBadge = UnlockItem()
        retiredBadge.key = "badge.first_record"
        retiredBadge.kind = .nameBadge
        retiredBadge.displayName = "ファーストログ"
        retiredBadge.targetID = "first_record"
        retiredBadge.isBuiltIn = true
        retiredBadge.unlockedAt = unlockedAt
        context.insert(retiredBadge)
        try context.save()

        UnlockStore(modelContext: context).seedMasterItems(now: now)

        let items = try context.fetch(FetchDescriptor<UnlockItem>())
        #expect(items.count == 69)
        #expect(!items.contains { $0.key == "badge.first_record" })
    }

    @Test
    func sevenDayStreakLegacyKeyDoesNotBecomeRecordedDaysBadge() {
        #expect(UnlockCatalog.legacyKeyReplacements["badge.seven_streak"] == nil)
    }

    @Test
    func refreshUnlocksOnlyNewlyReachedItemsAndNeverRelocks() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = UnlockStore(modelContext: context)
        let firstUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let secondUnlockTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))

        let metrics = UnlockMetrics(cumulativeScore: 450)
        let firstBatch = store.refresh(metrics: metrics, now: firstUnlockTime)
        #expect(firstBatch.map(\.key) == ["frame.cloud_veil", "card.cloud_panel"])

        let repeated = store.refresh(metrics: metrics, now: secondUnlockTime)
        #expect(repeated.isEmpty)

        let lowerScore = store.refresh(cumulativeScore: 0, now: secondUnlockTime)
        #expect(lowerScore.isEmpty)

        let unlocked = try context.fetch(FetchDescriptor<UnlockItem>())
            .filter { $0.unlockedAt != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(unlocked.map(\.key) == ["frame.cloud_veil", "card.cloud_panel"])
        #expect(unlocked.allSatisfy { $0.unlockedAt == firstUnlockTime })

        let next = try #require(store.nextLockedItem(metrics: metrics))
        #expect(next.key == "frame.ripple_ring")
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
                planMatchedDays: 5,
                chargeDays: 5
            ),
            now: now
        )

        #expect(unlocked.map(\.key) == [
            "badge.planner",
            "badge.restorer",
            "streak.gold_flame",
        ])
    }
}

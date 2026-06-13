import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct UnlockRulesTests {
    @Test
    func catalogMatchesOneYearReleaseCurve() {
        let items = UnlockCatalog.items

        #expect(items.count == 87)
        #expect(Set(items.map(\.key)).count == 87)
        #expect(Set(items.map(\.sortOrder)).count == 87)
        #expect(items.filter { $0.kind == .iconFrame }.count == 40)
        #expect(items.filter { $0.kind == .cardStyle }.count == 20)
        #expect(items.filter { $0.kind == .nameBadge }.count == 20)
        #expect(items.filter { $0.kind == .streakIcon }.count == 6)
        #expect(items.filter { $0.kind == .theme }.count == 1)
        #expect(Set(items.map(\.kind)) == Set([.theme, .iconFrame, .nameBadge, .streakIcon, .cardStyle]))
        #expect(Array(UnlockCatalog.releaseScheduleDays.prefix(12)) == [7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84])
        #expect(Array(UnlockCatalog.releaseScheduleDays.suffix(3)) == [300, 330, 365])
        #expect(Set(items.map(\.requirementKind)).isSuperset(of: [
            .cumulativeScore,
            .recordedDays,
            .recordedHours,
            .streakDays,
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
        // スコアで自動解放されるのは紋（封環）シリーズ5件のみ。個性装飾40件は交換制（.exchange）で自動解放されない。
        #expect(UnlockRules.unlockedKeys(cumulativeScore: 21_900).count == 5)

        let plannerKeys = UnlockRules.unlockedKeys(metrics: UnlockMetrics(planMatchedDays: 5))
        #expect(plannerKeys == Set(["frame.free_instrument_iron_crest", "badge.planner"]))

        let patternKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                streakDays: 7,
                chargeDays: 5,
                personalBestDays: 3
            )
        )
        #expect(patternKeys == Set(["streak.orange_flame", "streak.yellow_flame", "badge.restorer", "badge.updater"]))

        let allKeys = UnlockRules.unlockedKeys(
            metrics: UnlockMetrics(
                cumulativeScore: 21_900,
                recordedDays: 365,
                recordedHours: 8_000,
                streakDays: 90,
                earlyRecordDays: 21,
                lateNightRecordDays: 14,
                distinctCategoryCount: 6,
                planMatchedDays: 365,
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
        // 全87件のうち交換制の個性装飾40件は指標で解放されない
        #expect(allKeys.count == 47)
        #expect(allKeys.contains("theme.aurora"))
        #expect(!allKeys.contains("card.free_dawn_horizon_panel"))
        #expect(!allKeys.contains("frame.free_dawn_horizon"))
    }

    @Test
    func streakFlamesFollowHueOrderAndUnlockByConsecutiveDays() {
        #expect(ProfileStreakIconCatalog.equippableItems.map(\.id) == [
            "flame",
            "orange_flame",
            "yellow_flame",
            "lime_flame",
            "green_flame",
            "blue_flame",
            "purple_flame",
        ])

        let streakItems = UnlockCatalog.items
            .filter { $0.kind == .streakIcon }
            .sorted { $0.requiredValue < $1.requiredValue }

        #expect(streakItems.map(\.targetID) == [
            "orange_flame",
            "yellow_flame",
            "lime_flame",
            "green_flame",
            "blue_flame",
            "purple_flame",
        ])
        #expect(streakItems.allSatisfy { $0.requirementKind == .streakDays })
        #expect(streakItems.map(\.requiredValue) == [3, 7, 14, 30, 60, 90])
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
        #expect(items.count == 87)
        #expect(Set(items.map(\.key)).count == 87)
        let first = try #require(items.first { $0.key == "frame.free_instrument_iron" })
        #expect(first.kind == .iconFrame)
        #expect(first.requiredCumulativeScore == 420)
        #expect(first.requirementKind == .recordedDays)
        #expect(first.requiredValue == 3)
        #expect(first.targetID == "free_instrument_iron")
    }

    @Test
    func storeConsolidatesDuplicateKeysAndKeepsEarliestUnlockDate() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let seed = try #require(UnlockCatalog.items.first { $0.key == "card.free_thread_border_panel" })
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
        let threadItems = items.filter { $0.key == "card.free_thread_border_panel" }
        #expect(items.count == 87)
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
        #expect(items.count == 87)
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

        let metrics = UnlockMetrics(cumulativeScore: 450, recordedDays: 3)
        let firstBatch = store.refresh(metrics: metrics, now: firstUnlockTime)
        // カードは交換制（.exchange）になったため自動解放されない
        #expect(firstBatch.map(\.key) == ["frame.free_instrument_iron"])

        let repeated = store.refresh(metrics: metrics, now: secondUnlockTime)
        #expect(repeated.isEmpty)

        let lowerScore = store.refresh(cumulativeScore: 0, now: secondUnlockTime)
        #expect(lowerScore.isEmpty)

        let unlocked = try context.fetch(FetchDescriptor<UnlockItem>())
            .filter { $0.unlockedAt != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(unlocked.map(\.key) == ["frame.free_instrument_iron"])
        #expect(unlocked.allSatisfy { $0.unlockedAt == firstUnlockTime })

        let next = try #require(store.nextLockedItem(metrics: metrics))
        #expect(next.key == "frame.free_instrument_bronze")
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
            "frame.free_instrument_iron_crest",
            "badge.planner",
            "badge.restorer",
            "streak.orange_flame",
            "streak.yellow_flame",
        ])
    }
}

import Foundation
import Testing
@testable import Liminalog

struct LevelProgressTests {
    @Test
    func levelCurveBoundaries() {
        // Lv.n 到達スコア = 15n(n−1)
        #expect(LiminalLevel.requiredScore(for: 1) == 0)
        #expect(LiminalLevel.requiredScore(for: 2) == 30)
        #expect(LiminalLevel.requiredScore(for: 10) == 1_350)
        #expect(LiminalLevel.requiredScore(for: 21) == 6_300)
        #expect(LiminalLevel.requiredScore(for: 40) == 23_400)

        #expect(LiminalLevel.level(forScore: 0) == 1)
        #expect(LiminalLevel.level(forScore: 29) == 1)
        #expect(LiminalLevel.level(forScore: 30) == 2)
        #expect(LiminalLevel.level(forScore: 1_349) == 9)
        #expect(LiminalLevel.level(forScore: 1_350) == 10)
        #expect(LiminalLevel.level(forScore: 23_400) == 40)
        // 1年想定（21,900 ≒ 60pt/日 × 365日）でおよそLv.38〜39
        #expect(LiminalLevel.level(forScore: 21_900) >= 38)
    }

    @Test
    func levelIsMonotonicAndConsistentWithThresholds() {
        var previous = 1
        for score in stride(from: 0, through: 30_000, by: 7) {
            let level = LiminalLevel.level(forScore: score)
            #expect(level >= previous)
            #expect(LiminalLevel.requiredScore(for: level) <= score)
            #expect(LiminalLevel.requiredScore(for: level + 1) > score)
            previous = level
        }
    }

    @Test
    func progressToNextLevelStaysInRange() {
        let start = LiminalLevel.progressToNextLevel(score: 0)
        #expect(start.current == 0)
        #expect(start.required == 30)
        #expect(start.fraction == 0)

        let mid = LiminalLevel.progressToNextLevel(score: 45)
        // Lv.2(30)〜Lv.3(90) の区間で 15/60
        #expect(mid.current == 15)
        #expect(mid.required == 60)
        #expect(abs(mid.fraction - 0.25) < 0.0001)
    }

    @Test
    func fragmentBalanceIsDerivedAndNeverNegative() {
        // Lv.1 はかけら0枚
        #expect(LiminalLevel.earnedFragments(forScore: 0) == 0)
        // Lv.5（300pt）= 4枚
        #expect(LiminalLevel.earnedFragments(forScore: 300) == 4)

        #expect(LiminalLevel.fragmentBalance(score: 300, exchangedCount: 0) == 4)
        #expect(LiminalLevel.fragmentBalance(score: 300, exchangedCount: 3) == 1)
        // 端末マージ等で交換数が獲得数を上回っても負にならない
        #expect(LiminalLevel.fragmentBalance(score: 300, exchangedCount: 9) == 0)
    }

    @Test
    func exchangedCountCountsOnlyExchangedExchangeItems() throws {
        let exchanged = UnlockItem(seed: try #require(UnlockCatalog.items.first { $0.key == "card.free_dawn_horizon_panel" }))
        exchanged.unlockedAt = Date()
        let exchangedFrame = UnlockItem(seed: try #require(UnlockCatalog.items.first { $0.key == "frame.free_dawn_horizon" }))
        exchangedFrame.unlockedAt = Date()
        let notExchanged = UnlockItem(seed: try #require(UnlockCatalog.items.first { $0.key == "card.free_ripple_border_panel" }))
        let nonExchangeUnlocked = UnlockItem(seed: try #require(UnlockCatalog.items.first { $0.key == "frame.free_instrument_iron" }))
        nonExchangeUnlocked.unlockedAt = Date()

        #expect(LiminalLevel.exchangedCount(in: [exchanged, exchangedFrame, notExchanged, nonExchangeUnlocked]) == 2)
    }
}

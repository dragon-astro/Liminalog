import Foundation
import SwiftData
import Testing
@testable import Liminalog

@Suite("ScoreCalculator")
struct ScoreCalculatorTests {
    @Test("カテゴリ達成率80%と時間軸一致率20%で合算する")
    func weightedScoreUsesCategoryAndTimelineScores() throws {
        let calendar = Calendar.liminalogTest
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28)))
        let plan = PlanBlock(
            category: category,
            title: "勉強",
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 11)))
        )
        let chapter = Chapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9, minute: 5)))
        )
        chapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10, minute: 55))

        let summary = ScoreCalculator.summary(date: day, plans: [plan], chapters: [chapter], calendar: calendar)

        #expect(abs(summary.categoryScore - 91.666) < 0.01)
        #expect(abs(summary.timelineScore - 100) < 0.01)
        #expect(abs(summary.totalScore - 93.333) < 0.01)
    }

    @Test("日付またぎ予定と実績は対象日の範囲だけで計算する")
    func crossDayEntriesAreClippedToTargetDay() throws {
        let calendar = Calendar.liminalogTest
        let category = Category(name: "睡眠", colorHex: "#8B5CF6")
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28)))
        let plan = PlanBlock(
            category: category,
            title: "睡眠",
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))
        )
        let chapter = Chapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23, minute: 30)))
        )
        chapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1))

        let summary = ScoreCalculator.summary(date: day, plans: [plan], chapters: [chapter], calendar: calendar)

        #expect(summary.plannedDuration == 60 * 60)
        #expect(summary.recordedDuration == 60 * 60)
        #expect(summary.totalScore == 100)
    }
}

@MainActor
@Suite("ScoreStore")
struct ScoreStoreTests {
    @Test("30点以上の日だけストリークとして連続カウントする")
    func streakCountStopsAtFirstMissingOrLowScoreDay() throws {
        let calendar = Calendar.current
        let todayNoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let clock = MutableTestClock(now: todayNoon)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)

        let today = calendar.startOfDay(for: todayNoon)
        for offset in 0...1 {
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            let start = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
            let end = try #require(calendar.date(byAdding: .hour, value: 1, to: start))
            context.insert(PlanBlock(category: category, title: "勉強", startTime: start, endTime: end))
            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = calendar.date(byAdding: .minute, value: 30, to: start)
            context.insert(chapter)
        }

        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let unmatchedStart = try #require(calendar.date(byAdding: .hour, value: 9, to: twoDaysAgo))
        let unmatchedEnd = try #require(calendar.date(byAdding: .hour, value: 1, to: unmatchedStart))
        let otherCategory = Category(name: "仕事", colorHex: "#8B5CF6")
        context.insert(otherCategory)
        context.insert(PlanBlock(category: category, title: "勉強", startTime: unmatchedStart, endTime: unmatchedEnd))
        let unmatchedChapter = Chapter(category: otherCategory, startTime: unmatchedStart)
        unmatchedChapter.endTime = unmatchedEnd
        context.insert(unmatchedChapter)
        try context.save()

        let store = ScoreStore(modelContext: context, clock: clock)

        #expect(store.streakCount(endingAt: todayNoon) == 2)
    }

    @Test("今日が未達成でも昨日以前の連続を数える（進行中の今日は連続を切らない）")
    func streakCountKeepsYesterdayStreakWhenTodayIncomplete() throws {
        let calendar = Calendar.current
        let todayNoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let clock = MutableTestClock(now: todayNoon)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)

        let today = calendar.startOfDay(for: todayNoon)
        // 昨日・一昨日は予定どおり達成。今日は予定も記録も無し（進行中・未達）。
        for offset in 1...2 {
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            let start = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
            let end = try #require(calendar.date(byAdding: .hour, value: 1, to: start))
            context.insert(PlanBlock(category: category, title: "勉強", startTime: start, endTime: end))
            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            context.insert(chapter)
        }
        try context.save()

        let store = ScoreStore(modelContext: context, clock: clock)

        // 今日が0でも、昨日・一昨日の連続2日が保たれる。
        #expect(store.streakCount(endingAt: todayNoon) == 2)
    }

    @Test("累積スコアは365日より前の獲得分も含める")
    func cumulativeScoreIncludesScoresOlderThanOneYear() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12)))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)

        func insertPerfectDay(year: Int, month: Int, day: Int) throws -> (PlanBlock, Chapter) {
            let start = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)))
            let end = try #require(calendar.date(byAdding: .hour, value: 1, to: start))
            let plan = PlanBlock(category: category, title: "勉強", startTime: start, endTime: end)
            context.insert(plan)
            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            context.insert(chapter)
            return (plan, chapter)
        }

        let oldDay = try insertPerfectDay(year: 2025, month: 5, day: 1)
        _ = try insertPerfectDay(year: 2026, month: 6, day: 13)
        try context.save()

        let cumulativeScore = ScoreSnapshotLoader.cumulativeScore(
            modelContext: context,
            now: now,
            calendar: calendar
        )

        #expect(cumulativeScore == 200)

        let scoreSnapshots = try context.fetch(FetchDescriptor<DailyScoreSnapshot>())
        #expect(scoreSnapshots.count == 1)
        #expect(scoreSnapshots.first?.score == 100)
        #expect(scoreSnapshots.first?.hasRecord == true)
        #expect(scoreSnapshots.first?.recordedDuration == 3_600)
        #expect(scoreSnapshots.first?.categoryIDs == [category.id])

        let settings = try #require(try context.fetch(FetchDescriptor<UserSettings>()).first)
        #expect(settings.isFinalizedScoreLedgerInitialized)
        #expect(settings.finalizedCumulativeScore == 100)

        context.delete(oldDay.0)
        context.delete(oldDay.1)
        try context.save()

        let scoreAfterSourceChanges = ScoreSnapshotLoader.cumulativeScore(
            modelContext: context,
            now: now,
            calendar: calendar
        )

        #expect(scoreAfterSourceChanges == 200)
        #expect(settings.finalizedCumulativeScore == 100)
        #expect(try context.fetch(FetchDescriptor<DailyScoreSnapshot>()).count == 1)
    }
}

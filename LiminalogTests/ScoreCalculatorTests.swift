import Foundation
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
        chapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10, minute: 55)))

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
        chapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))

        let summary = ScoreCalculator.summary(date: day, plans: [plan], chapters: [chapter], calendar: calendar)

        #expect(summary.plannedDuration == 60 * 60)
        #expect(summary.recordedDuration == 60 * 60)
        #expect(summary.totalScore == 100)
    }
}


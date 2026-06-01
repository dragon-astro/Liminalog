import Foundation
import Testing
@testable import Liminalog

struct StatsEngineTests {
    @Test("StatsEngine はデイリーカード検出器をロジック層から返す")
    func dailyCardPatternExcludesRestThroughSharedEngine() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let boundary = DayBoundary(date: day, calendar: calendar)
        let sleep = Category(name: "睡眠", colorHex: "#6C5CE7", icon: "moon.fill")
        let study = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill")
        let sleepChapter = try makeChapter(category: sleep, day: day, calendar: calendar, startHour: 0, durationMinutes: 420)
        let studyChapter = try makeChapter(category: study, day: day, calendar: calendar, startHour: 9, durationMinutes: 120)

        let pattern = StatsEngine.dailyCardPattern(
            chapters: [sleepChapter, studyChapter],
            historyChapters: [],
            categoryRows: [(sleep, 7 * 60 * 60), (study, 2 * 60 * 60)],
            recordedDuration: 9 * 60 * 60,
            dayBoundary: boundary
        )

        #expect(pattern.restWasExcluded)
        #expect(pattern.discretionaryDuration == 2 * 60 * 60)
        #expect(pattern.focusCategory?.category.id == study.id)
    }

    @Test("StatsEngine は期間内の日別 ScoreSummary を共通生成する")
    func dailyScoreSummariesBuildsOneSummaryPerDay() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let interval = DateInterval(start: day, end: try #require(calendar.date(byAdding: .day, value: 2, to: day)))
        let category = Category(name: "制作", colorHex: "#2F80ED", icon: "hammer.fill")
        let plan = PlanBlock(
            category: category,
            title: "制作",
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 11)))
        )
        let chapter = try makeChapter(category: category, day: day, calendar: calendar, startHour: 9, durationMinutes: 120)

        let summaries = StatsEngine.dailyScoreSummaries(
            in: interval,
            chapters: [chapter],
            plans: [plan],
            now: nextDay,
            calendar: calendar
        )

        #expect(summaries.count == 2)
        #expect(summaries[0].plannedDuration == 2 * 60 * 60)
        #expect(summaries[0].recordedDuration == 2 * 60 * 60)
        #expect(summaries[1].plannedDuration == 0)
    }

    private func makeChapter(
        category: Liminalog.Category,
        day: Date,
        calendar: Calendar,
        startHour: Int,
        durationMinutes: Int
    ) throws -> Chapter {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let start = try #require(calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: startHour
        )))
        let chapter = Chapter(category: category, startTime: start)
        chapter.endTime = calendar.date(byAdding: .minute, value: durationMinutes, to: start)
        return chapter
    }
}

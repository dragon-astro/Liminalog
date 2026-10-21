import Foundation
import Testing
@testable import Liminalog

struct StatsEngineTests {
    @Test("日別バケット集計は日跨ぎ・うるう日・DST・部分日でも従来の全フィールドと一致する",
          arguments: ["Asia/Tokyo", "America/Los_Angeles"])
    func bucketedScoresMatchReference(timeZone: String) throws {
        var calendar = Calendar.liminalogTest
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 20, hour: 12)))
        let end = try #require(calendar.date(byAdding: .day, value: 35, to: start))
        let interval = DateInterval(start: start, end: end)
        let category = Category(name: "制作", colorHex: "#2F80ED", icon: "hammer.fill")
        var plans: [PlanBlock] = []
        var chapters: [Chapter] = []
        for index in 0..<100 {
            let time = start.addingTimeInterval(Double(index - 4) * 8 * 3600)
            plans.append(PlanBlock(category: index % 3 == 0 ? nil : category, title: "予定", startTime: time,
                                   endTime: time.addingTimeInterval(index % 4 == 0 ? 100_000 : 7200),
                                   isAllDay: index % 7 == 0))
            let chapter = Chapter(category: category, startTime: time.addingTimeInterval(-300))
            if index % 3 == 0 { chapter.category = nil }
            chapter.endTime = index == 99 ? nil : time.addingTimeInterval(index % 6 == 0 ? 10 : 7500)
            chapters.append(chapter)
        }
        let actual = StatsEngine.dailyScoreSummaries(in: interval, chapters: chapters, plans: plans, now: end, calendar: calendar)
        var day = DayBoundary.dayStart(for: start, calendar: calendar)
        var expected: [ScoreSummary] = []
        while day < end {
            let boundary = DayBoundary(date: day, calendar: calendar)
            expected.append(ScoreCalculator.summary(date: day,
                plans: plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart },
                chapters: chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? end) > boundary.dayStart },
                calendar: calendar, now: end))
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
        #expect(actual.count == expected.count)
        for (lhs, rhs) in zip(actual, expected) {
            #expect(lhs.date == rhs.date)
            #expect(lhs.totalScore == rhs.totalScore)
            #expect(lhs.categoryScore == rhs.categoryScore)
            #expect(lhs.timelineScore == rhs.timelineScore)
            #expect(lhs.plannedDuration == rhs.plannedDuration)
            #expect(lhs.recordedDuration == rhs.recordedDuration)
            #expect(lhs.matchedDuration == rhs.matchedDuration)
        }
    }

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

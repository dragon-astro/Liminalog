import Foundation
import Testing
@testable import Liminalog

struct DailyCardEngineTests {
    @Test("主要休息ブロックを実績扱いせず裁量時間として表示する")
    func factsExcludeMajorRestBlocks() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let boundary = DayBoundary(date: day, calendar: calendar)
        let sleep = Category(name: "睡眠", colorHex: "#6C5CE7", icon: "bed.double.fill")
        let study = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill")

        let sleepChapter = Chapter(category: sleep, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 0))))
        sleepChapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7)))
        let studyChapter = Chapter(category: study, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))))
        studyChapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 11)))

        let persona = DailyPersona.make(
            summary: ScoreSummary(date: day, categoryScore: 0, timelineScore: 0, totalScore: 0, plannedDuration: 0, recordedDuration: 9 * 60 * 60, matchedDuration: 0),
            chapters: [sleepChapter, studyChapter],
            historyChapters: [],
            categoryRows: [(sleep, 7 * 60 * 60), (study, 2 * 60 * 60)],
            recordedDuration: 9 * 60 * 60,
            dayBoundary: boundary
        )

        #expect(persona.facts.first?.title == "裁量時間")
        #expect(persona.facts.first?.value == "2時間")
    }

    @Test("高スコア予定一致の称号と本文は同じ意味を補強する")
    func highScorePersonaDoesNotBorrowUnrelatedSignalCopy() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let category = Category(name: "趣味", colorHex: "#F2994A", icon: "sparkles")
        let chapter = Chapter(category: category, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 20))))
        chapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 22)))

        let persona = DailyPersona.make(
            summary: ScoreSummary(date: day, categoryScore: 100, timelineScore: 90, totalScore: 95, plannedDuration: 2 * 60 * 60, recordedDuration: 2 * 60 * 60, matchedDuration: 2 * 60 * 60),
            chapters: [chapter],
            historyChapters: [],
            categoryRows: [(category, 2 * 60 * 60)],
            recordedDuration: 2 * 60 * 60,
            dayBoundary: DayBoundary(date: day, calendar: calendar)
        )

        #expect(persona.title == "有言実行の人")
        #expect(persona.message.contains("予定"))
        #expect(!persona.message.contains("趣味"))
    }

    @Test("コールドスタートの共有コピーに内部事情メタ文言を出さない")
    func coldStartCopyDoesNotExposeDataScarcityMetaText() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let category = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill")
        let chapter = Chapter(category: category, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))))
        chapter.endTime = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))

        let persona = DailyPersona.make(
            summary: ScoreSummary(date: day, categoryScore: 0, timelineScore: 0, totalScore: 0, plannedDuration: 0, recordedDuration: 3 * 60 * 60, matchedDuration: 0),
            chapters: [chapter],
            historyChapters: [],
            categoryRows: [(category, 3 * 60 * 60)],
            recordedDuration: 3 * 60 * 60,
            dayBoundary: DayBoundary(date: day, calendar: calendar)
        )

        #expect(!persona.message.contains("データ"))
        #expect(!persona.message.contains("少な"))
    }
}

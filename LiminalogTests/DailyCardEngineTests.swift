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

    @Test("形ベース称号は時間帯と集中形の分類から選ばれる")
    func shapePersonaTitlesUseChronotypeAndFocusShape() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let category = Category(name: "制作", colorHex: "#2F80ED", icon: "hammer.fill")

        let morning = try makePersona(
            day: day,
            calendar: calendar,
            chapters: [
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 6, durationMinutes: 120)
            ],
            category: category
        )
        #expect(morning.title == "朝の短距離走者")

        let daytime = try makePersona(
            day: day,
            calendar: calendar,
            chapters: [
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 11, durationMinutes: 30),
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 12, startMinute: 10, durationMinutes: 30),
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 13, startMinute: 20, durationMinutes: 30),
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 14, startMinute: 30, durationMinutes: 30)
            ],
            category: category
        )
        #expect(daytime.title == "平常運転マスター")

        let evening = try makePersona(
            day: day,
            calendar: calendar,
            chapters: try (0..<8).map { index in
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 17 + index / 2, startMinute: (index % 2) * 30, durationMinutes: 20)
            },
            category: category
        )
        #expect(evening.title == "夜のザッピング")

        let midnight = try makePersona(
            day: day,
            calendar: calendar,
            chapters: [
                try makeChapter(category: category, day: day, calendar: calendar, startHour: 1, durationMinutes: 120)
            ],
            category: category
        )
        #expect(midnight.title == "丑三つの天才")
    }

    @Test("履歴にないカテゴリは初記録signalとして称号とfactに出る")
    func firstRecordSignalBecomesPersonaAndFact() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let study = Category(name: "勉強", colorHex: "#2F80ED", icon: "book.fill")
        let cooking = Category(name: "料理", colorHex: "#F2994A", icon: "fork.knife")
        let todayChapter = try makeChapter(category: cooking, day: day, calendar: calendar, startHour: 18, durationMinutes: 45)
        let history = try (1...7).map { offset in
            let historyDay = try #require(calendar.date(byAdding: .day, value: -offset, to: day))
            return try makeChapter(category: study, day: historyDay, calendar: calendar, startHour: 9, durationMinutes: 60)
        }

        let persona = DailyPersona.make(
            summary: ScoreSummary(date: day, categoryScore: 0, timelineScore: 0, totalScore: 0, plannedDuration: 60 * 60, recordedDuration: 45 * 60, matchedDuration: 0),
            chapters: [todayChapter],
            historyChapters: history,
            categoryRows: [(cooking, 45 * 60)],
            recordedDuration: 45 * 60,
            dayBoundary: DayBoundary(date: day, calendar: calendar)
        )

        #expect(persona.title == "料理、はじめました")
        #expect(persona.facts.contains { $0.id == "signal-first" && $0.value == "料理" })
    }

    private func makePersona(
        day: Date,
        calendar: Calendar,
        chapters: [Chapter],
        category: Liminalog.Category
    ) throws -> DailyPersona {
        let recordedDuration = chapters.reduce(TimeInterval(0)) { partial, chapter in
            partial + max((chapter.endTime ?? chapter.startTime).timeIntervalSince(chapter.startTime), 0)
        }
        return DailyPersona.make(
            summary: ScoreSummary(date: day, categoryScore: 40, timelineScore: 40, totalScore: 40, plannedDuration: max(recordedDuration, 60 * 60), recordedDuration: recordedDuration, matchedDuration: 0),
            chapters: chapters,
            historyChapters: [],
            categoryRows: [(category, recordedDuration)],
            recordedDuration: recordedDuration,
            dayBoundary: DayBoundary(date: day, calendar: calendar)
        )
    }

    private func makeChapter(
        category: Liminalog.Category,
        day: Date,
        calendar: Calendar,
        startHour: Int,
        startMinute: Int = 0,
        durationMinutes: Int
    ) throws -> Chapter {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let start = try #require(calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: startHour,
            minute: startMinute
        )))
        let chapter = Chapter(category: category, startTime: start)
        chapter.endTime = calendar.date(byAdding: .minute, value: durationMinutes, to: start)
        return chapter
    }
}

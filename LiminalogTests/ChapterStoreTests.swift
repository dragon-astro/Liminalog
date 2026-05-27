import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("ChapterStore")
struct ChapterStoreTests {
    @Test("手動追加は既存実績と重なる時間を保存しない")
    func addChapterRejectsOverlaps() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)
        let store = ChapterStore(modelContext: context, clock: clock)

        #expect(store.addChapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))
        ))
        #expect(!store.addChapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9, minute: 30))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10, minute: 30)))
        ))
        #expect(store.addChapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 11)))
        ))

        let chapters = try context.fetch(FetchDescriptor<Chapter>())
        #expect(chapters.count == 2)
    }

    @Test("短時間のカテゴリ切替でも各カテゴリを別Chapterとして残す")
    func rapidCategorySwitchingKeepsSeparateChapters() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let categories = [
            Category(name: "勉強", colorHex: "#3B82F6"),
            Category(name: "仕事", colorHex: "#8B5CF6"),
            Category(name: "休憩", colorHex: "#22C55E")
        ]
        categories.forEach { context.insert($0) }
        let store = ChapterStore(modelContext: context, clock: clock)

        store.startChapter(category: categories[0])
        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9, second: 20)))
        store.startChapter(category: categories[1])
        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9, second: 40)))
        store.startChapter(category: categories[2])

        let chapters = try context.fetch(FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)]))
        #expect(chapters.count == 3)
        #expect(chapters[0].endTime != nil)
        #expect(chapters[1].endTime != nil)
        #expect(chapters[2].endTime == nil)
        #expect(chapters.map { $0.category?.name } == ["勉強", "仕事", "休憩"])
    }
}

private final class MutableTestClock: LiminalogClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

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

    @Test("同じカテゴリを再タップしても新規Chapterを作らず他のactiveだけ閉じる")
    func sameCategoryRetapKeepsMatchingActiveAndClosesOthers() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))
        let clock = MutableTestClock(now: now)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        context.insert(study)
        context.insert(work)
        let kept = Chapter(category: study, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 8))))
        let stray = Chapter(category: work, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        context.insert(kept)
        context.insert(stray)
        try context.save()

        let store = ChapterStore(modelContext: context, clock: clock)
        store.startChapter(category: study)

        let chapters = try context.fetch(FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)]))
        #expect(chapters.count == 2)
        #expect(chapters.first { $0.id == kept.id }?.endTime == nil)
        #expect(chapters.first { $0.id == stray.id }?.endTime == now)
        #expect(store.activeChapter?.category?.id == study.id)
    }

    @Test("別カテゴリへ切り替えると全activeを閉じて新しいactiveを1件だけ作る")
    func differentCategorySwitchConvergesToSingleActive() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))
        let clock = MutableTestClock(now: now)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        let rest = Category(name: "休憩", colorHex: "#22C55E")
        [study, work, rest].forEach { context.insert($0) }
        let activeA = Chapter(category: study, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 8))))
        let activeB = Chapter(category: work, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        context.insert(activeA)
        context.insert(activeB)
        try context.save()

        let store = ChapterStore(modelContext: context, clock: clock)
        store.startChapter(category: rest)

        let chapters = try context.fetch(FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)]))
        let activeChapters = chapters.filter { $0.endTime == nil }
        #expect(chapters.count == 3)
        #expect(activeChapters.count == 1)
        #expect(activeChapters.first?.category?.id == rest.id)
        #expect(chapters.first { $0.id == activeA.id }?.endTime == now)
        #expect(chapters.first { $0.id == activeB.id }?.endTime == now)
    }

    @Test("共有切替ロジックは同カテゴリ継続時に新規Chapterを作らない")
    func sharedRecordingSwitchLogicKeepsSameCategoryActive() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        let kept = Chapter(category: study, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 8))))
        let stray = Chapter(category: work, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        var inserted: [Chapter] = []

        let result = RecordingSwitchLogic.switchToCategory(
            study,
            at: now,
            activeChapters: [kept, stray]
        ) { chapter in
            inserted.append(chapter)
        }

        #expect(result.activeChapter?.id == kept.id)
        #expect(!result.didCreateChapter)
        #expect(result.closedChapterCount == 1)
        #expect(inserted.isEmpty)
        #expect(kept.endTime == nil)
        #expect(stray.endTime == now)
    }

    @Test("共有切替ロジックは別カテゴリ切替時にactiveを1件へ収束する")
    func sharedRecordingSwitchLogicCreatesNewActiveForDifferentCategory() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        let rest = Category(name: "休憩", colorHex: "#22C55E")
        let activeA = Chapter(category: study, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 8))))
        let activeB = Chapter(category: work, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        var inserted: [Chapter] = []

        let result = RecordingSwitchLogic.switchToCategory(
            rest,
            at: now,
            activeChapters: [activeA, activeB]
        ) { chapter in
            inserted.append(chapter)
        }

        #expect(result.activeChapter?.category?.id == rest.id)
        #expect(result.didCreateChapter)
        #expect(result.closedChapterCount == 2)
        #expect(inserted.count == 1)
        #expect(activeA.endTime == now)
        #expect(activeB.endTime == now)
        #expect(inserted.first?.endTime == nil)
    }

    @Test("CategorySetのスロット順と空きスロットを保ってカテゴリを解決する")
    func categorySetSlotsResolveInGridOrder() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        let rest = Category(name: "休憩", colorHex: "#22C55E")
        [study, work, rest].forEach { context.insert($0) }
        let set = CategorySet(
            name: "テスト",
            slots: [rest.id, nil, study.id, work.id]
        )
        context.insert(set)
        try context.save()

        let categorySetStore = CategorySetStore(
            modelContext: context,
            categoryStore: CategoryStore(modelContext: context)
        )
        let slotted = categorySetStore.slottedCategories(for: set)
        let assigned = categorySetStore.assignedCategories(for: set)

        #expect(slotted.count == CategorySet.slotCount)
        #expect(slotted[0]?.id == rest.id)
        #expect(slotted[1] == nil)
        #expect(slotted[2]?.id == study.id)
        #expect(slotted[3]?.id == work.id)
        #expect(assigned.map(\.id) == [rest.id, study.id, work.id])
    }
}

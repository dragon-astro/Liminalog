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

    @Test("カテゴリ切替はTodayタイムライン更新用のrevisionを進める")
    func categorySwitchAdvancesContentRevision() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let study = Category(name: "勉強", colorHex: "#3B82F6")
        let work = Category(name: "仕事", colorHex: "#8B5CF6")
        context.insert(study)
        context.insert(work)
        let store = ChapterStore(modelContext: context, clock: clock)

        let initialRevision = store.contentRevision
        store.startChapter(category: study)
        let startedRevision = store.contentRevision

        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9, minute: 30)))
        store.startChapter(category: work)

        #expect(startedRevision > initialRevision)
        #expect(store.contentRevision > startedRevision)
        #expect(store.activeChapter?.category?.id == work.id)
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

    @Test("PreviewSupportの実行時seedは明示フラグなしでは無効で、dev指定時だけ予定seedも連動する")
    func previewRuntimeSeedRequestRequiresExplicitFlags() throws {
        let suiteName = "LiminalogTests.previewSeed.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let off = PreviewSupport.runtimeSeedRequest(
            defaults: defaults,
            arguments: ["Liminalog"],
            environment: [:]
        )
        #expect(!off.shouldSeedPreviewPlans)
        #expect(!off.shouldSeedDevData)

        let previewOnly = PreviewSupport.runtimeSeedRequest(
            defaults: defaults,
            arguments: ["Liminalog", "-LiminalogSeedPreviewData", "YES"],
            environment: [:]
        )
        #expect(previewOnly.shouldSeedPreviewPlans)
        #expect(!previewOnly.shouldSeedDevData)

        let devData = PreviewSupport.runtimeSeedRequest(
            defaults: defaults,
            arguments: ["Liminalog", "-LiminalogSeedDevData"],
            environment: [:]
        )
        #expect(devData.shouldSeedPreviewPlans)
        #expect(devData.shouldSeedDevData)

        let environmentPreview = PreviewSupport.runtimeSeedRequest(
            defaults: defaults,
            arguments: ["Liminalog"],
            environment: ["LiminalogSeedPreviewData": "true"]
        )
        #expect(environmentPreview.shouldSeedPreviewPlans)
        #expect(!environmentPreview.shouldSeedDevData)
    }

    @Test("空のカテゴリ既定公開相手は明示的な空スナップショットとして保存しない")
    func emptyDefaultAudienceDoesNotBecomeExplicitEmptySnapshot() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)
        let store = ChapterStore(modelContext: context, clock: clock)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 9)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 10)))

        #expect(store.addPlanBlock(
            category: category,
            title: "公開予定",
            startTime: start,
            endTime: end,
            isPublic: true,
            audienceFriendIDs: nil
        ))

        let plan = try #require(try context.fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(plan.isPublic)
        #expect(plan.audienceFriendIDs.isEmpty)
        #expect(!plan.hasAudienceSnapshot)
    }

    @Test("公開相手を手動で空にした予定は明示的な空スナップショットとして保存する")
    func customEmptyAudienceRemainsExplicitEmptySnapshot() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)
        let store = ChapterStore(modelContext: context, clock: clock)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 9)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 10)))

        #expect(store.addPlanBlock(
            category: category,
            title: "誰にも見せない予定",
            startTime: start,
            endTime: end,
            isPublic: true,
            audienceFriendIDs: [],
            audienceSource: .custom,
            hasAudienceSnapshot: true
        ))

        let plan = try #require(try context.fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(plan.isPublic)
        #expect(plan.audienceSource == .custom)
        #expect(plan.audienceFriendIDs.isEmpty)
        #expect(plan.hasAudienceSnapshot)
    }

    @Test("空のカテゴリ既定公開相手は実績でも明示的な空スナップショットとして保存しない")
    func emptyDefaultAudienceDoesNotBecomeExplicitEmptyChapterSnapshot() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)
        let store = ChapterStore(modelContext: context, clock: clock)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))

        #expect(store.addChapter(
            category: category,
            startTime: start,
            endTime: end,
            isPublic: true,
            audienceFriendIDs: nil
        ))

        let chapter = try #require(try context.fetch(FetchDescriptor<Chapter>()).first)
        #expect(chapter.isPublic)
        #expect(chapter.audienceFriendIDs.isEmpty)
        #expect(!chapter.hasAudienceSnapshot)
    }

    @Test("公開相手を手動で空にした実績は明示的な空スナップショットとして保存する")
    func customEmptyAudienceRemainsExplicitEmptyChapterSnapshot() throws {
        let calendar = Calendar.liminalogTest
        let clock = MutableTestClock(now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#3B82F6")
        context.insert(category)
        let store = ChapterStore(modelContext: context, clock: clock)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 9)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 10)))

        #expect(store.addChapter(
            category: category,
            startTime: start,
            endTime: end,
            isPublic: true,
            audienceFriendIDs: [],
            audienceSource: .custom,
            hasAudienceSnapshot: true
        ))

        let chapter = try #require(try context.fetch(FetchDescriptor<Chapter>()).first)
        #expect(chapter.isPublic)
        #expect(chapter.audienceSource == .custom)
        #expect(chapter.audienceFriendIDs.isEmpty)
        #expect(chapter.hasAudienceSnapshot)
    }

    @Test("開発用Chapter seedはユーザー実績を残し、月跨ぎの昨日を含めたデモ実績を作る")
    func devSampleChapterSeedAvoidsFutureAndOverlaps() throws {
        let versionKey = "LiminalogDevSampleChapterSeedVersion"
        let anchorKey = "LiminalogDevSampleChapterSeedAnchorDay"
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: anchorKey)
        defer {
            UserDefaults.standard.removeObject(forKey: versionKey)
            UserDefaults.standard.removeObject(forKey: anchorKey)
        }

        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 15)))
        let clock = MutableTestClock(now: now)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let staleCategory = Category(name: "古いダミー", colorHex: "#999999")
        context.insert(staleCategory)
        let userChapter = Chapter(category: staleCategory, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 6))))
        userChapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7))
        context.insert(userChapter)
        try context.save()
        UserDefaults.standard.set(999, forKey: versionKey)
        UserDefaults.standard.set("20260531", forKey: anchorKey)

        let store = ChapterStore(modelContext: context, clock: clock)
        store.seedDevSampleChaptersIfNeeded()

        let chapters = try context.fetch(FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)]))
        let yesterdayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        let todayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let debugChapters = chapters.filter { $0.photoLocalIdentifier == "liminalog.debug.dev-chapter" }
        #expect(!chapters.isEmpty)
        #expect(chapters.contains { $0.id == userChapter.id })
        #expect(!debugChapters.isEmpty)
        #expect(debugChapters.filter { $0.endTime == nil }.count == 1)
        #expect(debugChapters.allSatisfy { $0.startTime <= now })
        #expect(debugChapters.allSatisfy { ($0.endTime ?? now) <= now })
        #expect(debugChapters.contains { $0.startTime < todayStart && ($0.endTime ?? now) > yesterdayStart })

        for index in debugChapters.indices {
            for laterIndex in debugChapters.indices.dropFirst(index + 1) {
                let first = debugChapters[index]
                let second = debugChapters[laterIndex]
                let firstEnd = first.endTime ?? now
                let secondEnd = second.endTime ?? now
                #expect(firstEnd <= second.startTime || secondEnd <= first.startTime)
            }
        }
    }

    @Test("開発用予定seedは今月と前後1日を24時間埋めて重要予定の見せ場も作る")
    func previewPlanSeedPopulatesFullMonthShowcaseData() throws {
        let versionKey = "LiminalogPreviewPlanSeedVersion"
        UserDefaults.standard.removeObject(forKey: versionKey)
        defer { UserDefaults.standard.removeObject(forKey: versionKey) }

        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 15)))
        let clock = MutableTestClock(now: now)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let userCategory = Category(name: "ユーザー予定", colorHex: "#111111")
        context.insert(userCategory)
        let userPlan = PlanBlock(
            category: userCategory,
            title: "消えない予定",
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9)))
        )
        context.insert(userPlan)
        try context.save()
        let store = ChapterStore(modelContext: context, clock: clock)

        store.seedPreviewPlansIfNeeded()

        let plans = try context.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.startTime)]))
        let debugPlans = plans.filter { $0.sourceEventID?.hasPrefix("debug.preview.") == true }
        let monthStart = try #require(calendar.date(from: calendar.dateComponents([.year, .month], from: now)))
        let monthEnd = try #require(calendar.date(byAdding: .month, value: 1, to: monthStart))
        let previousDayStart = try #require(calendar.date(byAdding: .day, value: -1, to: monthStart))
        let nextMonthFirstDayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: monthEnd))
        let timedPlans = debugPlans.filter { !$0.isAllDay }

        var dayCount = 0
        var cursor = previousDayStart
        while cursor < nextMonthFirstDayEnd {
            let dayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: cursor))
            let dayPlans = timedPlans.filter { $0.startTime < dayEnd && $0.endTime > cursor }
            #expect(plansCoverFullDayForTest(dayPlans, dayStart: cursor, dayEnd: dayEnd))
            dayCount += 1
            cursor = dayEnd
        }

        #expect(dayCount == 32)
        #expect(plans.contains { $0.id == userPlan.id })
        #expect(debugPlans.filter { $0.isImportant && !$0.isAllDay }.count >= 14)
        #expect(debugPlans.filter { $0.isImportant && $0.isAllDay }.count >= 12)
        #expect(debugPlans.contains { $0.isImportant && !$0.isAllDay && $0.title == "中間発表" })
        #expect(debugPlans.contains { $0.isImportant && !$0.isAllDay && $0.title == "デイリー共有" })
        #expect(debugPlans.contains { $0.isImportant && !$0.isAllDay && $0.title == "提出締切" })
        #expect(debugPlans.contains { $0.isImportant && $0.isAllDay && $0.title == "集中制作週間" })
        #expect(debugPlans.contains { $0.isImportant && $0.isAllDay && $0.title == "企画スプリント" })
        #expect(debugPlans.contains { $0.isImportant && $0.isAllDay && $0.title == "読書強化" })
        #expect(debugPlans.contains { $0.isImportant && $0.isAllDay && $0.startTime < monthStart && $0.endTime > monthStart })
        #expect(debugPlans.contains { $0.isImportant && $0.isAllDay && $0.startTime < monthEnd && $0.endTime > monthEnd })
        #expect(!hasTimedPlanOverlapForTest(debugPlans))
    }

    @Test("開発用Chapter seedは重なった既存ダミー実績を再生成する")
    func devSampleChapterSeedRegeneratesOverlappingDebugData() throws {
        let versionKey = "LiminalogDevSampleChapterSeedVersion"
        let anchorKey = "LiminalogDevSampleChapterSeedAnchorDay"
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: anchorKey)
        defer {
            UserDefaults.standard.removeObject(forKey: versionKey)
            UserDefaults.standard.removeObject(forKey: anchorKey)
        }

        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 15)))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "壊れたダミー", colorHex: "#999999")
        context.insert(category)
        let first = Chapter(category: category, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))))
        first.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))
        first.photoLocalIdentifier = "liminalog.debug.dev-chapter"
        let second = Chapter(category: category, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8, minute: 30))))
        second.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9, minute: 30))
        second.photoLocalIdentifier = "liminalog.debug.dev-chapter"
        context.insert(first)
        context.insert(second)
        try context.save()
        UserDefaults.standard.set(999, forKey: versionKey)
        UserDefaults.standard.set("20260601", forKey: anchorKey)

        let store = ChapterStore(modelContext: context, clock: MutableTestClock(now: now))
        store.seedDevSampleChaptersIfNeeded()

        let debugChapters = try context.fetch(FetchDescriptor<Chapter>())
            .filter { $0.photoLocalIdentifier == "liminalog.debug.dev-chapter" }
        #expect(debugChapters.count > 2)
        #expect(!debugChapters.contains { $0.id == first.id || $0.id == second.id })
        #expect(!hasChapterOverlapForTest(debugChapters, now: now))
    }

    @Test("設定のダミーデータOFFはデモ由来の予定と実績だけを削除する")
    func runtimeSeedRemovalKeepsUserData() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 15)))
        let clock = MutableTestClock(now: now)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let userCategory = Category(name: "ユーザー", colorHex: "#111111")
        context.insert(userCategory)
        let userChapter = Chapter(category: userCategory, startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 6))))
        userChapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7))
        context.insert(userChapter)
        let userPlan = PlanBlock(
            category: userCategory,
            title: "ユーザー予定",
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))),
            endTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9)))
        )
        context.insert(userPlan)
        try context.save()

        let store = ChapterStore(modelContext: context, clock: clock)
        store.seedPreviewPlansIfNeeded()
        store.seedDevSampleChaptersIfNeeded()
        #expect(PreviewSupport.removeRuntimeSeedData(in: context))

        let chapters = try context.fetch(FetchDescriptor<Chapter>())
        let plans = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(chapters.count == 1)
        #expect(chapters.contains { $0.id == userChapter.id })
        #expect(plans.count == 1)
        #expect(plans.contains { $0.id == userPlan.id })
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

    @Test("CategorySetの並び替えは範囲外indexを保存しない")
    func categorySetMoveIgnoresOutOfRangeIndex() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let weekday = CategorySet(name: "平日", sortOrder: 0)
        let holiday = CategorySet(name: "休日", sortOrder: 1)
        context.insert(weekday)
        context.insert(holiday)
        try context.save()

        let categorySetStore = CategorySetStore(
            modelContext: context,
            categoryStore: CategoryStore(modelContext: context)
        )

        let didMove = categorySetStore.moveCategorySets(from: IndexSet(integer: 8), to: 0)
        let sets = categorySetStore.categorySets()

        #expect(didMove == false)
        #expect(sets.map(\.id) == [weekday.id, holiday.id])
        #expect(sets.map(\.sortOrder) == [0, 1])

        let didMoveEmptySource = categorySetStore.moveCategorySets(from: IndexSet(), to: 1)
        #expect(didMoveEmptySource == false)
    }

    private func plansCoverFullDayForTest(_ plans: [PlanBlock], dayStart: Date, dayEnd: Date) -> Bool {
        let sorted = plans
            .map { (start: max($0.startTime, dayStart), end: min($0.endTime, dayEnd)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return false }

        var cursor = dayStart
        let tolerance: TimeInterval = 1
        for plan in sorted {
            if plan.start.timeIntervalSince(cursor) > tolerance {
                return false
            }
            cursor = max(cursor, plan.end)
            if cursor >= dayEnd {
                return true
            }
        }
        return dayEnd.timeIntervalSince(cursor) <= tolerance
    }

    private func hasTimedPlanOverlapForTest(_ plans: [PlanBlock]) -> Bool {
        let sorted = plans
            .filter { !$0.isAllDay && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }
        var previousEnd: Date?
        for plan in sorted {
            if let previousEnd, plan.startTime < previousEnd {
                return true
            }
            previousEnd = max(previousEnd ?? plan.endTime, plan.endTime)
        }
        return false
    }

    private func hasChapterOverlapForTest(_ chapters: [Chapter], now: Date) -> Bool {
        let sorted = chapters
            .compactMap { chapter -> (start: Date, end: Date)? in
                let end = chapter.endTime ?? now
                guard end > chapter.startTime else { return nil }
                return (chapter.startTime, end)
            }
            .sorted { $0.start < $1.start }
        var previousEnd: Date?
        for chapter in sorted {
            if let previousEnd, chapter.start < previousEnd {
                return true
            }
            previousEnd = max(previousEnd ?? chapter.end, chapter.end)
        }
        return false
    }
}

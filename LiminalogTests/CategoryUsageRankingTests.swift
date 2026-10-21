import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct CategoryUsageRankingTests {
    private let calendar = Calendar.liminalogTest
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func plan(category: Liminalog.Category?, createdAt: Date, scheduledAt: Date? = nil) -> PlanBlock {
        let start = scheduledAt ?? now
        let plan = PlanBlock(category: category, title: "予定", startTime: start, endTime: start.addingTimeInterval(3600))
        plan.createdAt = createdAt
        return plan
    }

    @Test func recentCreationCountsRegardlessOfScheduledDateAndExcludesExternalPlans() {
        let category = Category(name: "制作", colorHex: "#123456")
        let window = CategoryUsageRanking.window(now: now, calendar: calendar)
        let future = plan(category: category, createdAt: now, scheduledAt: now.addingTimeInterval(365 * 86400))
        let memo = plan(category: category, createdAt: window.start)
        memo.isMemo = true
        let old = plan(category: category, createdAt: window.start.addingTimeInterval(-1))
        let later = plan(category: category, createdAt: window.end)
        let external = plan(category: category, createdAt: now)
        external.sourceEventID = "eventkit.event"
        let noCategory = plan(category: nil, createdAt: now)
        let counts = CategoryUsageRanking.counts(plans: [future, memo, old, later, external, noCategory],
                                                manualRecurrencePlanIDs: [], window: window)
        #expect(counts == [category.id: 2])
    }

    @Test func lookbackUsesNinetyCalendarDaysAcrossDaylightSavingChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 12))!
        let window = CategoryUsageRanking.window(now: date, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: window.start, to: window.end).day == 90)
        #expect(window.end == calendar.date(from: DateComponents(year: 2026, month: 4, day: 2)))
        #expect(window.duration != 90 * 86400)
    }

    @Test func persistedCountsIncludeRecurrenceSourceButNotGeneratedOrCustomizedCopies() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "制作", colorHex: "#123456")
        let editedCategory = Category(name: "別のカテゴリ", colorHex: "#654321")
        context.insert(category)
        context.insert(editedCategory)
        let seriesID = UUID()
        let source = plan(category: category, createdAt: now)
        source.recurrenceSeriesID = seriesID
        context.insert(source)
        let sourceRecord = PlanRecurrenceOccurrence(seriesID: seriesID, itemID: seriesID, day: now)
        sourceRecord.planID = source.id
        context.insert(sourceRecord)
        for index in 0..<60 {
            let generated = plan(category: category, createdAt: now,
                                 scheduledAt: now.addingTimeInterval(Double(index + 1) * 86400))
            generated.recurrenceSeriesID = seriesID
            context.insert(generated)
            let record = PlanRecurrenceOccurrence(seriesID: seriesID, itemID: seriesID, day: generated.startTime)
            record.planID = generated.id
            record.baselineData = PlanRecurrenceBaseline(generated).data
            context.insert(record)
            if index == 0 { generated.category = editedCategory }
        }
        // Importing/recording actual activity must not change the plan editor's ranking.
        context.insert(Chapter(category: editedCategory, startTime: now))
        try context.save()
        let counts = try CategoryUsageRanking.load(modelContext: context,
                                                   window: CategoryUsageRanking.window(now: now, calendar: calendar))
        #expect(counts == [category.id: 1])
    }

    @Test func deletedCategoryAndUnlinkedRecurrenceDoNotProduceUsage() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "制作", colorHex: "#123456")
        context.insert(category)
        let orphan = plan(category: category, createdAt: now)
        orphan.recurrenceSeriesID = UUID()
        context.insert(orphan)
        context.insert(plan(category: nil, createdAt: now))
        try context.save()
        let window = CategoryUsageRanking.window(now: now, calendar: calendar)
        #expect(try CategoryUsageRanking.load(modelContext: context, window: window).isEmpty)
        context.delete(category)
        try context.save()
        #expect(try CategoryUsageRanking.load(modelContext: context, window: window).isEmpty)
    }

    @Test func orderingUsesFrequencyThenSettingsOrderAndStableTies() {
        let first = Category(name: "先", colorHex: "#123456", sortOrder: 0)
        let second = Category(name: "後", colorHex: "#123456", sortOrder: 1)
        let tied = Category(name: "同順", colorHex: "#123456", sortOrder: 1)
        second.createdAt = now
        tied.createdAt = now
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        tied.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let categories = [tied, second, first]
        #expect(CategoryUsageRanking.ordered(categories, counts: [second.id: 2, tied.id: 2]).map(\.id)
                == [second.id, tied.id, first.id])
        #expect(CategoryUsageRanking.ordered(categories, counts: [:]).map(\.id) == [first.id, second.id, tied.id])
        #expect(CategoryUsageRanking.ordered(Array(categories.reversed()), counts: [:]).map(\.id)
                == [first.id, second.id, tied.id])
    }

    @Test func cacheReusesRepeatedOpenAndReloadsOnRevisionDayOrExplicitInvalidation() {
        let cache = CategoryUsageCache()
        let id = UUID()
        let window = CategoryUsageRanking.window(now: now, calendar: calendar)
        var loads = 0
        func load() -> [UUID: Int] { loads += 1; return [id: loads] }
        for _ in 0..<20 {
            #expect(cache.counts(revision: 1, window: window, load: load) == [id: 1])
        }
        #expect(loads == 1)
        #expect(cache.counts(revision: 2, window: window, load: load) == [id: 2])
        let nextDay = CategoryUsageRanking.window(now: now.addingTimeInterval(86400), calendar: calendar)
        #expect(cache.counts(revision: 2, window: nextDay, load: load) == [id: 3])
        cache.invalidate()
        #expect(cache.counts(revision: 2, window: nextDay, load: load) == [id: 4])
    }

    @Test func failedFetchIsRetriedInsteadOfCachingAnEmptyResult() throws {
        enum Failure: Error { case unavailable }
        let cache = CategoryUsageCache()
        let window = CategoryUsageRanking.window(now: now, calendar: calendar)
        let id = UUID()
        #expect(throws: Failure.self) {
            try cache.counts(revision: 1, window: window) { throw Failure.unavailable }
        }
        #expect(cache.counts(revision: 1, window: window) { [id: 1] } == [id: 1])
    }

    @Test func savingPlanThroughStoreRefreshesCountsWithoutReopeningTheApp() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "制作", colorHex: "#123456")
        context.insert(category)
        try context.save()
        let clock = MutableTestClock(now: now)
        let planStore = PlanStore(modelContext: context, clock: clock, requestRefresh: { _, _, _ in })
        let store = ChapterStore(modelContext: context, clock: clock, planStore: planStore)
        #expect(store.categoryUsageCounts(calendar: calendar)?.isEmpty == true)
        let plan = try #require(store.createPlanBlock(category: category, title: "メモ",
            startTime: now, endTime: now.addingTimeInterval(3600), isMemo: true,
            beforeSave: { $0.createdAt = now; return true }))
        #expect(store.categoryUsageCounts(calendar: calendar) == [category.id: 1])
        #expect(store.savePlanBlock(plan, category: nil, title: plan.title, startTime: plan.startTime,
            endTime: plan.endTime, isAllDay: false, isMemo: true, isImportant: false, note: nil, isPublic: false))
        #expect(store.categoryUsageCounts(calendar: calendar)?.isEmpty == true)
    }

    @Test func storeCachesPerContextAndRefreshesAfterExternalInvalidation() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "制作", colorHex: "#123456")
        context.insert(category)
        context.insert(plan(category: category, createdAt: now))
        try context.save()
        let store = ChapterStore(modelContext: context, clock: MutableTestClock(now: now))
        #expect(store.categoryUsageCounts(calendar: calendar) == [category.id: 1])
        context.insert(plan(category: category, createdAt: now))
        try context.save()
        store.invalidateCategoryUsageRanking()
        #expect(store.categoryUsageRevision == 1)
        #expect(store.categoryUsageCounts(calendar: calendar) == [category.id: 2])
        let other = try TestModelContainer.make()
        let otherStore = ChapterStore(modelContext: other.mainContext, clock: MutableTestClock(now: now))
        #expect(otherStore.categoryUsageCounts(calendar: calendar)?.isEmpty == true)
    }
}

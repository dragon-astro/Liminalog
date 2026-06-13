import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("Category metadata")
struct CategoryMetadataTests {
    @Test("デフォルト睡眠カテゴリはデイリーカード睡眠タグを持つ")
    func seedDefaultCategoriesMarksSleepForDailyCard() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CategoryStore(modelContext: context)

        #expect(store.seedDefaultCategoriesIfNeeded())

        let categories = store.allCategories()
        let sleep = try #require(categories.first { $0.name == "睡眠" })
        #expect(categories.count == 8)
        #expect(Set(categories.map(\.name)) == ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味", "自由時間", "家事"])
        #expect(sleep.isDefault)
        #expect(sleep.isDailyCardSleepCategory)
        #expect(categories.filter { $0.name != "睡眠" }.allSatisfy { !$0.isDailyCardSleepCategory })
        #expect(!store.seedDefaultCategoriesIfNeeded())
    }

    @Test("既存の睡眠カテゴリをユーザーが睡眠扱いOFFにした状態はseedで上書きしない")
    func seedDoesNotReenableUserDisabledSleepTag() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let sleep = Category(
            name: "睡眠",
            colorHex: "#9B51E0",
            icon: "moon.fill",
            isDefault: true,
            isDailyCardSleepCategory: false
        )
        context.insert(sleep)
        try context.save()
        let store = CategoryStore(modelContext: context)

        #expect(store.seedDefaultCategoriesIfNeeded())

        #expect(!sleep.isDailyCardSleepCategory)
        #expect(store.allCategories().contains { $0.name == "勉強" })
    }

    @Test("カテゴリ追加と更新はデイリーカード用メタ情報を保存する")
    func addAndUpdateCategoryPersistsDailyCardMetadata() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CategoryStore(modelContext: context)

        #expect(store.addCategory(
            name: "SNS",
            colorHex: "#EB5757",
            icon: "iphone",
            dailyCardIntent: .decrease
        ))

        let category = try #require(store.allCategories().first { $0.name == "SNS" })
        #expect(category.dailyCardIntent == .decrease)
        #expect(category.dailyCardIntentRawValue == DailyCardCategoryIntent.decrease.rawValue)
        #expect(!category.isDailyCardSleepCategory)

        #expect(store.updateCategory(
            category,
            name: "仮眠",
            colorHex: "#6C5CE7",
            icon: "bed.double.fill",
            dailyCardIntent: .increase,
            isDailyCardSleepCategory: true
        ))

        #expect(category.name == "仮眠")
        #expect(category.dailyCardIntent == .increase)
        #expect(category.dailyCardIntentRawValue == DailyCardCategoryIntent.increase.rawValue)
        #expect(category.isDailyCardSleepCategory)
    }
}

@MainActor
@Suite("PlanStore")
struct PlanStoreTests {
    @Test("未来の予定は追加、更新、削除できる")
    func futurePlanCanBeCreatedUpdatedAndDeleted() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let start = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let end = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11)))
        let updatedStart = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12)))
        let updatedEnd = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 13)))
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))

        #expect(store.addPlanBlock(category: Optional<Liminalog.Category>.none, title: "作業", startTime: start, endTime: end))

        let plan = try #require(store.allPlannedBlocks().first)
        #expect(plan.title == "作業")
        #expect(plan.isPublic == true)

        #expect(store.savePlanBlock(
            plan,
            category: Optional<Liminalog.Category>.none,
            title: "集中作業",
            startTime: updatedStart,
            endTime: updatedEnd,
            isAllDay: false,
            isImportant: true,
            note: "準備",
            isPublic: false
        ))
        #expect(plan.title == "集中作業")
        #expect(plan.isImportant)
        #expect(plan.note == "準備")
        #expect(plan.isPublic == false)

        #expect(store.deletePlanBlock(plan))
        #expect(store.allPlannedBlocks().isEmpty)
    }

    @Test("時刻指定予定は既存予定と重なる時間を保存しない")
    func timedPlanRejectsOverlaps() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))
        let firstStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let firstEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11)))
        let overlapStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10, minute: 30)))
        let overlapEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11, minute: 30)))
        let touchingStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11)))
        let touchingEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12)))

        #expect(store.addPlanBlock(category: nil, title: "午前", startTime: firstStart, endTime: firstEnd))
        #expect(!store.addPlanBlock(category: nil, title: "重複", startTime: overlapStart, endTime: overlapEnd))
        #expect(store.addPlanBlock(category: nil, title: "隣接", startTime: touchingStart, endTime: touchingEnd))
        #expect(store.addPlanBlock(
            category: nil,
            title: "終日",
            startTime: firstStart,
            endTime: firstEnd,
            isAllDay: true
        ))
        #expect(store.allPlannedBlocks().map(\.title).sorted() == ["午前", "終日", "隣接"])
    }

    @Test("当日の時刻指定予定は削除できない")
    func timedPlanOnTodayCannotBeDeleted() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let now = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let start = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 10)))
        let end = try #require(Calendar.liminalogTest.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 11)))
        let plan = PlanBlock(category: nil, title: "今日の予定", startTime: start, endTime: end)
        context.insert(plan)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))

        #expect(!store.deletePlanBlock(plan))
        #expect(store.allPlannedBlocks().contains { $0.id == plan.id })
    }
}

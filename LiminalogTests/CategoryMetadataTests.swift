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

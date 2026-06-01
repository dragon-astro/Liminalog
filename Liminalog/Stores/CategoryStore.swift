import Foundation
import SwiftData

@MainActor
final class CategoryStore {
    private let modelContext: ModelContext

    private let defaultCategorySpecs: [(name: String, hex: String, icon: String, isSleep: Bool)] = [
        ("勉強", "#2F80ED", "book.closed.fill", false),
        ("仕事", "#6C5CE7", "briefcase.fill", false),
        ("趣味", "#EB5757", "sparkles", false),
        ("休憩", "#27AE60", "cup.and.saucer.fill", false),
        ("移動", "#F2994A", "tram.fill", false),
        ("睡眠", "#9B51E0", "moon.fill", true),
    ]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allCategories() -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addCategory(
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        isDailyCardSleepCategory: Bool = false
    ) -> Bool {
        let all = allCategories()
        let nextOrder = (all.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(
            name: name,
            colorHex: colorHex,
            icon: icon,
            sortOrder: nextOrder,
            dailyCardIntent: dailyCardIntent,
            isDailyCardSleepCategory: isDailyCardSleepCategory
        )
        modelContext.insert(category)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func updateCategory(
        _ category: Category,
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        isDailyCardSleepCategory: Bool = false
    ) -> Bool {
        category.name = name
        category.colorHex = colorHex
        category.icon = icon
        category.dailyCardIntent = dailyCardIntent
        category.isDailyCardSleepCategory = isDailyCardSleepCategory
        try? modelContext.save()
        return true
    }

    @discardableResult
    func deleteCategory(_ category: Category) -> Bool {
        let descriptor = FetchDescriptor<CategorySet>()
        let sets = (try? modelContext.fetch(descriptor)) ?? []
        for set in sets where set.slots.contains(category.id) {
            set.slots = set.slots.map { $0 == category.id ? nil : $0 }
        }
        modelContext.delete(category)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func seedDefaultCategoriesIfNeeded() -> Bool {
        let all = allCategories()
        let existingNames = Set(all.map(\.name))
        var didInsert = false

        for (index, spec) in defaultCategorySpecs.enumerated() where !existingNames.contains(spec.name) {
            let category = Category(
                name: spec.name,
                colorHex: spec.hex,
                icon: spec.icon,
                sortOrder: index,
                isDefault: true,
                isDailyCardSleepCategory: spec.isSleep
            )
            modelContext.insert(category)
            didInsert = true
        }

        guard didInsert else { return false }
        try? modelContext.save()
        return true
    }
}

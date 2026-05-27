import Foundation
import SwiftData

@MainActor
final class CategorySetStore {
    private let modelContext: ModelContext
    private let categoryStore: CategoryStore

    init(modelContext: ModelContext, categoryStore: CategoryStore) {
        self.modelContext = modelContext
        self.categoryStore = categoryStore
    }

    func categorySets() -> [CategorySet] {
        let descriptor = FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func slottedCategories(for set: CategorySet) -> [Category?] {
        let indexed = Dictionary(uniqueKeysWithValues: categoryStore.allCategories().map { ($0.id, $0) })
        return set.slots.map { id in id.flatMap { indexed[$0] } }
    }

    func assignedCategories(for set: CategorySet) -> [Category] {
        slottedCategories(for: set).compactMap { $0 }
    }

    @discardableResult
    func addCategorySet(name: String, slots: [UUID?]) -> Bool {
        let nextOrder = (categorySets().map(\.sortOrder).max() ?? -1) + 1
        let set = CategorySet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "セット \(nextOrder + 1)" : name,
            sortOrder: nextOrder,
            slots: slots
        )
        modelContext.insert(set)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func updateCategorySet(_ set: CategorySet, name: String, slots: [UUID?]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        set.name = trimmed.isEmpty ? set.name : trimmed
        set.slots = CategorySet.normalize(slots)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func deleteCategorySet(_ set: CategorySet) -> Bool {
        modelContext.delete(set)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func seedDefaultCategorySetsIfNeeded() -> Bool {
        var didChange = categoryStore.seedDefaultCategoriesIfNeeded()
        guard categorySets().isEmpty else { return didChange }

        let categories = categoryStore.allCategories()
        let byName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })
        let weekdayNames: [String?] = ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味", nil, nil]
        let weekdaySlots = weekdayNames.map { name in name.flatMap { byName[$0]?.id } }
        let holidayNames: [String?] = ["睡眠", "趣味", "休憩", "勉強", "移動", nil, nil, nil]
        let holidaySlots = holidayNames.map { name in name.flatMap { byName[$0]?.id } }

        modelContext.insert(CategorySet(name: "平日", sortOrder: 0, slots: weekdaySlots, isDefault: true))
        modelContext.insert(CategorySet(name: "休日", sortOrder: 1, slots: holidaySlots, isDefault: true))
        try? modelContext.save()
        didChange = true
        return didChange
    }
}

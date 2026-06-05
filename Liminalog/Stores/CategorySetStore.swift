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
        categorySetsIfAvailable() ?? []
    }

    func categorySetsIfAvailable() -> [CategorySet]? {
        let descriptor = FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch category sets: \(String(describing: error))")
            return nil
        }
    }

    func slottedCategories(for set: CategorySet) -> [Category?] {
        slottedCategoriesIfAvailable(for: set) ?? []
    }

    func slottedCategoriesIfAvailable(for set: CategorySet) -> [Category?]? {
        guard let categories = categoryStore.allCategoriesIfAvailable() else {
            NSLog("Liminalog: failed to resolve category set slots because categories could not be fetched")
            return nil
        }
        let indexed = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return set.slots.map { id in id.flatMap { indexed[$0] } }
    }

    func assignedCategories(for set: CategorySet) -> [Category] {
        assignedCategoriesIfAvailable(for: set) ?? []
    }

    func assignedCategoriesIfAvailable(for set: CategorySet) -> [Category]? {
        slottedCategoriesIfAvailable(for: set)?.compactMap { $0 }
    }

    @discardableResult
    func addCategorySet(name: String, slots: [UUID?]) -> Bool {
        guard let sets = categorySetsIfAvailable() else {
            NSLog("Liminalog: skipped category set add because category sets could not be fetched")
            return false
        }
        let nextOrder = (sets.map(\.sortOrder).max() ?? -1) + 1
        let set = CategorySet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "セット \(nextOrder + 1)" : name,
            sortOrder: nextOrder,
            slots: slots
        )
        modelContext.insert(set)
        return saveChanges("category set add")
    }

    @discardableResult
    func updateCategorySet(_ set: CategorySet, name: String, slots: [UUID?]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        set.name = trimmed.isEmpty ? set.name : trimmed
        set.slots = CategorySet.normalize(slots)
        return saveChanges("category set update")
    }

    @discardableResult
    func deleteCategorySet(_ set: CategorySet) -> Bool {
        modelContext.delete(set)
        return saveChanges("category set delete")
    }

    @discardableResult
    func moveCategorySets(from source: IndexSet, to destination: Int) -> Bool {
        guard var sets = categorySetsIfAvailable() else {
            NSLog("Liminalog: skipped category set move because category sets could not be fetched")
            return false
        }
        guard !source.isEmpty, source.allSatisfy({ sets.indices.contains($0) }) else {
            return false
        }
        let moving = source.map { sets[$0] }
        for index in source.sorted(by: >) {
            sets.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        sets.insert(contentsOf: moving, at: min(max(adjustedDestination, 0), sets.count))
        for (index, set) in sets.enumerated() {
            set.sortOrder = index
        }
        return saveChanges("category set move")
    }

    @discardableResult
    func seedDefaultCategorySetsIfNeeded() -> Bool {
        let didChange = categoryStore.seedDefaultCategoriesIfNeeded()
        guard let existingSets = categorySetsIfAvailable() else {
            NSLog("Liminalog: skipped default category set seed because category sets could not be fetched")
            return didChange
        }
        guard existingSets.isEmpty else { return didChange }

        guard let categories = categoryStore.allCategoriesIfAvailable() else {
            NSLog("Liminalog: skipped default category set seed because categories could not be fetched")
            return didChange
        }
        guard !categories.isEmpty else {
            NSLog("Liminalog: skipped default category set seed because no categories were available")
            return didChange
        }
        let byName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })
        let weekdayNames: [String?] = ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味", nil, nil]
        let weekdaySlots = weekdayNames.map { name in name.flatMap { byName[$0]?.id } }
        let holidayNames: [String?] = ["睡眠", "趣味", "休憩", "勉強", "移動", nil, nil, nil]
        let holidaySlots = holidayNames.map { name in name.flatMap { byName[$0]?.id } }

        modelContext.insert(CategorySet(name: "平日", sortOrder: 0, slots: weekdaySlots, isDefault: true))
        modelContext.insert(CategorySet(name: "休日", sortOrder: 1, slots: holidaySlots, isDefault: true))
        return saveChanges("default category set seed") || didChange
    }

    private func saveChanges(_ action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }
}

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
        guard let categories = categoryStore.allCategoriesIfAvailable() else {
            NSLog("Liminalog: skipped default category set seed because categories could not be fetched")
            return didChange
        }
        guard categories.count >= CategorySet.slotCount else {
            NSLog("Liminalog: skipped default category set seed because no categories were available")
            return didChange
        }
        let byName = categories.reduce(into: [String: Category]()) { result, category in
            result[category.name, default: category] = category
        }
        var sets = existingSets
        var didUpdateSets = false

        didUpdateSets = ensureDefaultCategorySet(
            named: "平日",
            sortOrder: 0,
            slotNames: ["勉強", "仕事", "移動", "休憩", "自由時間", "家事", "趣味", "睡眠"],
            categoriesByName: byName,
            sets: &sets
        ) || didUpdateSets
        didUpdateSets = ensureDefaultCategorySet(
            named: "休日",
            sortOrder: 1,
            slotNames: ["睡眠", "自由時間", "趣味", "休憩", "家事", "移動", "勉強", "仕事"],
            categoriesByName: byName,
            sets: &sets
        ) || didUpdateSets

        guard didUpdateSets else { return didChange }
        return saveChanges("default category set seed") || didChange
    }

    @discardableResult
    private func ensureDefaultCategorySet(
        named name: String,
        sortOrder: Int,
        slotNames: [String],
        categoriesByName: [String: Category],
        sets: inout [CategorySet]
    ) -> Bool {
        let slots = CategorySet.normalize(slotNames.map { categoriesByName[$0]?.id })
        guard slots.count == CategorySet.slotCount,
              slots.allSatisfy({ $0 != nil })
        else { return false }

        if let existing = sets.first(where: { $0.name == name }) {
            var didChange = false
            if existing.isDefault && CategorySet.normalize(existing.slots) != slots && existing.filledCount < CategorySet.slotCount {
                existing.slots = slots
                didChange = true
            }
            if existing.isDefault != true {
                existing.isDefault = true
                didChange = true
            }
            if existing.sortOrder != sortOrder {
                existing.sortOrder = sortOrder
                didChange = true
            }
            return didChange
        }

        let set = CategorySet(name: name, sortOrder: sortOrder, slots: slots, isDefault: true)
        modelContext.insert(set)
        sets.append(set)
        return true
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

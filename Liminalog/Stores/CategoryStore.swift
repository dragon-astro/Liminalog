import Foundation
import SwiftData

@MainActor
final class CategoryStore {
    private let modelContext: ModelContext

    private let defaultCategorySpecs: [(name: String, hex: String, icon: String, analysisKind: CategoryAnalysisKind)] = [
        ("勉強", "#2F80ED", "book.closed.fill", .study),
        ("仕事", "#6C5CE7", "briefcase.fill", .work),
        ("移動", "#F2994A", "tram.fill", .unspecified),
        ("休憩", "#27AE60", "cup.and.saucer.fill", .unspecified),
        ("睡眠", "#9B51E0", "moon.fill", .sleep),
        ("趣味", "#EB5757", "sparkles", .hobbyPlay),
        ("自由時間", "#F2C94C", "gamecontroller.fill", .hobbyPlay),
        ("家事", "#56CCF2", "house.fill", .household)
    ]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allCategories() -> [Category] {
        allCategoriesIfAvailable() ?? []
    }

    func allCategoriesIfAvailable() -> [Category]? {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch categories: \(String(describing: error))")
            return nil
        }
    }

    @discardableResult
    func addCategory(
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        analysisKind: CategoryAnalysisKind = .unspecified,
        isDailyCardSleepCategory: Bool = false,
        defaultAudienceFriendSetIDs: [UUID] = [],
        defaultAudienceIncludedFriendIDs: [UUID] = [],
        defaultAudienceExcludedFriendIDs: [UUID] = []
    ) -> Bool {
        guard let all = allCategoriesIfAvailable() else {
            NSLog("Liminalog: skipped category add because categories could not be fetched")
            return false
        }
        let nextOrder = (all.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(
            name: name,
            colorHex: colorHex,
            icon: icon,
            sortOrder: nextOrder,
            dailyCardIntent: dailyCardIntent,
            analysisKind: analysisKind,
            isDailyCardSleepCategory: isDailyCardSleepCategory
        )
        category.defaultAudienceFriendSetIDs = defaultAudienceFriendSetIDs
        category.defaultAudienceIncludedFriendIDs = defaultAudienceIncludedFriendIDs
        category.defaultAudienceExcludedFriendIDs = defaultAudienceExcludedFriendIDs
        modelContext.insert(category)
        return saveChanges("category add")
    }

    @discardableResult
    func updateCategory(
        _ category: Category,
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        analysisKind: CategoryAnalysisKind = .unspecified,
        isDailyCardSleepCategory: Bool = false,
        defaultAudienceFriendSetIDs: [UUID]? = nil,
        defaultAudienceIncludedFriendIDs: [UUID]? = nil,
        defaultAudienceExcludedFriendIDs: [UUID]? = nil
    ) -> Bool {
        category.name = name
        category.colorHex = colorHex
        category.icon = icon
        category.dailyCardIntent = dailyCardIntent
        category.analysisKind = analysisKind == .unspecified && isDailyCardSleepCategory ? .sleep : analysisKind
        if let defaultAudienceFriendSetIDs {
            category.defaultAudienceFriendSetIDs = defaultAudienceFriendSetIDs
        }
        if let defaultAudienceIncludedFriendIDs {
            category.defaultAudienceIncludedFriendIDs = defaultAudienceIncludedFriendIDs
        }
        if let defaultAudienceExcludedFriendIDs {
            category.defaultAudienceExcludedFriendIDs = defaultAudienceExcludedFriendIDs
        }
        return saveChanges("category update")
    }

    @discardableResult
    func deleteCategory(_ category: Category) -> Bool {
        let descriptor = FetchDescriptor<CategorySet>()
        let sets: [CategorySet]
        do {
            sets = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: skipped category delete because category sets could not be fetched: \(String(describing: error))")
            return false
        }
        for set in sets where set.slots.contains(category.id) {
            set.slots = set.slots.map { $0 == category.id ? nil : $0 }
        }
        modelContext.delete(category)
        return saveChanges("category delete")
    }

    @discardableResult
    func seedDefaultCategoriesIfNeeded() -> Bool {
        guard let all = allCategoriesIfAvailable() else {
            NSLog("Liminalog: skipped default category seed because categories could not be fetched")
            return false
        }
        var existingNames = Set(all.map(\.name))
        var didChange = false

        for spec in defaultCategorySpecs {
            for category in all where category.isDefault && category.name == spec.name && category.analysisKindRawValue == CategoryAnalysisKind.unspecified.rawValue {
                category.analysisKind = spec.analysisKind
                didChange = true
            }
        }

        for (index, spec) in defaultCategorySpecs.enumerated() where !existingNames.contains(spec.name) {
            let category = Category(
                name: spec.name,
                colorHex: spec.hex,
                icon: spec.icon,
                sortOrder: index,
                isDefault: true,
                analysisKind: spec.analysisKind
            )
            modelContext.insert(category)
            existingNames.insert(spec.name)
            didChange = true
        }

        guard didChange else { return false }
        return saveChanges("default category seed")
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

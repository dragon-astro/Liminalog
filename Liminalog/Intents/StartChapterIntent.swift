import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct StartChapterIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "記録開始"
    static let description = IntentDescription("選んだカテゴリで記録を開始します。")
    static let openAppWhenRun = false
    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let activeCategoryCacheKey = "recording.activeCategoryID"
    private static let pendingCategoryCacheKey = "recording.pendingCategoryID"
    private static let enabledCategorySetCacheKey = "recording.enabledCategorySetID"

    @Parameter(title: "カテゴリID")
    var categoryID: String

    init() {
        self.categoryID = ""
    }

    init(categoryID: String) {
        self.categoryID = categoryID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let categoryID = UUID(uuidString: categoryID) else {
            throw StartChapterIntentError.invalidCategoryID
        }

        let context = ModelContext(SharedModelContainer.shared)
        let categories = try context.fetch(FetchDescriptor<Category>())
        guard let category = categories.first(where: { $0.id == categoryID }) else {
            throw StartChapterIntentError.categoryNotFound
        }

        let activeChapters = try context.fetch(FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        ))
        let result = RecordingSwitchLogic.switchToCategory(
            category,
            at: Date(),
            activeChapters: activeChapters
        ) { chapter in
            context.insert(chapter)
        }

        try context.save()
        Self.cacheActiveCategoryID(result.activeChapter?.category?.id)
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")

        if #available(iOS 16.2, *) {
            await updateLiveActivity(activeChapter: result.activeChapter, context: context)
        }

        #if DEBUG
        print("App LiveActivityIntent switched category: \(categoryID.uuidString)")
        #endif

        return .result()
    }

    private static func cacheActiveCategoryID(_ id: UUID?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let id {
            defaults.set(id.uuidString, forKey: activeCategoryCacheKey)
            defaults.set(id.uuidString, forKey: pendingCategoryCacheKey)
        } else {
            defaults.removeObject(forKey: activeCategoryCacheKey)
            defaults.removeObject(forKey: pendingCategoryCacheKey)
        }
        defaults.synchronize()
    }

    @available(iOS 16.2, *)
    @MainActor
    private func updateLiveActivity(activeChapter: Chapter?, context: ModelContext) async {
        let selectedSet = currentCategorySet(context: context)
        let categories = assignedCategories(for: selectedSet, context: context)
        await LiveActivityManager.shared.update(
            activeChapter: activeChapter,
            categorySetName: selectedSet?.name ?? "カテゴリ",
            categories: categories
        )
    }

    @MainActor
    private func currentCategorySet(context: ModelContext) -> CategorySet? {
        let sets = (try? context.fetch(FetchDescriptor<CategorySet>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        ))) ?? []
        let settings = try? context.fetch(FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.settingsKey == "default" },
            sortBy: [SortDescriptor(\.createdAt)]
        )).first
        let cachedID = Self.cachedEnabledCategorySetID(validatingWith: sets)
        return (cachedID ?? settings?.enabledCategorySetID).flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first
    }

    private static func cachedEnabledCategorySetID(validatingWith sets: [CategorySet]) -> UUID? {
        guard let value = UserDefaults(suiteName: appGroupID)?.string(forKey: enabledCategorySetCacheKey),
              let id = UUID(uuidString: value),
              sets.contains(where: { $0.id == id })
        else {
            return nil
        }
        return id
    }

    @MainActor
    private func assignedCategories(for set: CategorySet?, context: ModelContext) -> [Category] {
        guard let set else { return [] }
        let categories = (try? context.fetch(FetchDescriptor<Category>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        ))) ?? []
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return set.slots.compactMap { id in id.flatMap { categoryByID[$0] } }
    }
}

enum StartChapterIntentError: Error {
    case invalidCategoryID
    case categoryNotFound
}

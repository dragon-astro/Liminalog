import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct StartChapterIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "記録開始"
    static let description = IntentDescription("選んだカテゴリで記録を開始します。")
    static let openAppWhenRun = false

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

        let now = Date()
        let activeChapters = try context.fetch(FetchDescriptor<Chapter>())
            .filter { $0.endTime == nil }
            .sorted { $0.startTime < $1.startTime }
        let sameCategoryActive = activeChapters.first { $0.category?.id == categoryID }
        var activeAfterChange = sameCategoryActive

        for chapter in activeChapters where chapter.id != sameCategoryActive?.id {
            chapter.endTime = now
            chapter.updatedAt = now
        }

        if sameCategoryActive == nil {
            let chapter = Chapter(category: category, startTime: now)
            context.insert(chapter)
            activeAfterChange = chapter
        }

        if #available(iOS 16.2, *) {
            await updateLiveActivity(activeChapter: activeAfterChange, context: context)
        }

        try context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")

        #if DEBUG
        print("App LiveActivityIntent switched category: \(categoryID.uuidString)")
        #endif

        return .result()
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
        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        return settings?.enabledCategorySetID.flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first
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

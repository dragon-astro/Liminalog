import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct EndChapterIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "記録終了"
    static let description = IntentDescription("現在進行中の記録を終了します。")
    static let openAppWhenRun = false

    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let activeCategoryCacheKey = "recording.activeCategoryID"
    private static let pendingCategoryCacheKey = "recording.pendingCategoryID"

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(SharedModelContainer.shared)
        let activeChapters = try context.fetch(FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        ))

        guard !activeChapters.isEmpty else {
            Self.cacheActiveCategoryID(nil)
            WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")
            if #available(iOS 16.2, *) {
                await updateLiveActivity(context: context)
            }
            return .result()
        }

        let now = Date()
        for chapter in activeChapters {
            chapter.endTime = now
            chapter.updatedAt = now
        }
        try context.save()

        Self.cacheActiveCategoryID(nil)
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")

        if #available(iOS 16.2, *) {
            await updateLiveActivity(context: context)
        }

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
    private func updateLiveActivity(context: ModelContext) async {
        let selectedSet = currentCategorySet(context: context)
        let categories = assignedCategories(for: selectedSet, context: context)
        await LiveActivityManager.shared.update(
            activeChapter: nil,
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

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
    private static let enabledCategorySetCacheKey = "recording.enabledCategorySetID"

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(SharedModelContainer.shared)
        let activeChapters: [Chapter]
        do {
            activeChapters = try context.fetch(FetchDescriptor<Chapter>(
                predicate: #Predicate { $0.endTime == nil },
                sortBy: [SortDescriptor(\.startTime)]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch active chapters in EndChapterIntent: \(String(describing: error))")
            throw EndChapterIntentError.storeUnavailable
        }

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
        do {
            try context.save()
        } catch {
            NSLog("Liminalog: failed to save EndChapterIntent: \(String(describing: error))")
            context.rollback()
            throw EndChapterIntentError.saveFailed
        }

        Self.cacheActiveCategoryID(nil)
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")

        if #available(iOS 16.2, *) {
            await updateLiveActivity(context: context)
        }

        return .result()
    }

    private static func cacheActiveCategoryID(_ id: UUID?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            NSLog("Liminalog: skipped EndChapterIntent category cache because app group UserDefaults was unavailable")
            return
        }
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
        guard let surface = recordingSurfaceIfAvailable(context: context) else {
            NSLog("Liminalog: skipped EndChapterIntent Live Activity update because recording surface could not be loaded")
            return
        }
        await LiveActivityManager.shared.update(
            activeChapter: nil,
            categorySetName: surface.categorySetName,
            categories: surface.categories
        )
    }

    @MainActor
    private func recordingSurfaceIfAvailable(context: ModelContext) -> (categorySetName: String, categories: [Category])? {
        let sets: [CategorySet]
        do {
            sets = try context.fetch(FetchDescriptor<CategorySet>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch category sets in EndChapterIntent Live Activity update: \(String(describing: error))")
            return nil
        }

        let settings: UserSettings?
        do {
            settings = try context.fetch(FetchDescriptor<UserSettings>(
                predicate: #Predicate { $0.settingsKey == "default" },
                sortBy: [SortDescriptor(\.createdAt)]
            )).first
        } catch {
            NSLog("Liminalog: failed to fetch settings in EndChapterIntent Live Activity update: \(String(describing: error))")
            return nil
        }

        let cachedID = Self.cachedEnabledCategorySetID(validatingWith: sets)
        let selectedSet = (cachedID ?? settings?.enabledCategorySetID).flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first

        guard let selectedSet else {
            return ("カテゴリ", [])
        }

        let categories: [Category]
        do {
            categories = try context.fetch(FetchDescriptor<Category>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch categories in EndChapterIntent Live Activity update: \(String(describing: error))")
            return nil
        }
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return (
            selectedSet.name,
            selectedSet.slots.compactMap { id in id.flatMap { categoryByID[$0] } }
        )
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
}

enum EndChapterIntentError: LocalizedError {
    case storeUnavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "進行中の記録を読み込めませんでした。時間をおいてもう一度試してください。"
        case .saveFailed:
            return "記録を終了できませんでした。時間をおいてもう一度試してください。"
        }
    }
}

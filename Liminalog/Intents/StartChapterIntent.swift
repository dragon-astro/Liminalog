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
        let categories: [Category]
        do {
            categories = try context.fetch(FetchDescriptor<Category>())
        } catch {
            NSLog("Liminalog: failed to fetch categories in StartChapterIntent: \(String(describing: error))")
            throw StartChapterIntentError.storeUnavailable
        }
        guard let category = categories.first(where: { $0.id == categoryID }) else {
            throw StartChapterIntentError.categoryNotFound
        }

        let activeChapters: [Chapter]
        do {
            activeChapters = try context.fetch(FetchDescriptor<Chapter>(
                predicate: #Predicate { $0.endTime == nil },
                sortBy: [SortDescriptor(\.startTime)]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch active chapters in StartChapterIntent: \(String(describing: error))")
            throw StartChapterIntentError.storeUnavailable
        }
        let result = RecordingSwitchLogic.switchToCategory(
            category,
            at: Date(),
            activeChapters: activeChapters
        ) { chapter in
            context.insert(chapter)
        }

        do {
            try context.save()
        } catch {
            NSLog("Liminalog: failed to save StartChapterIntent: \(String(describing: error))")
            context.rollback()
            throw StartChapterIntentError.saveFailed
        }
        Self.cacheActiveCategoryID(result.activeChapter?.category?.id)
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")

        if #available(iOS 16.2, *) {
            await updateLiveActivity(activeChapter: result.activeChapter, context: context)
        }

        return .result()
    }

    private static func cacheActiveCategoryID(_ id: UUID?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            NSLog("Liminalog: skipped StartChapterIntent category cache because app group UserDefaults was unavailable")
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
    private func updateLiveActivity(activeChapter: Chapter?, context: ModelContext) async {
        guard let surface = recordingSurfaceIfAvailable(context: context) else {
            NSLog("Liminalog: skipped StartChapterIntent Live Activity update because recording surface could not be loaded")
            return
        }
        await LiveActivityManager.shared.update(
            activeChapter: activeChapter,
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
            NSLog("Liminalog: failed to fetch category sets in StartChapterIntent Live Activity update: \(String(describing: error))")
            return nil
        }

        let settings: UserSettings?
        do {
            settings = try context.fetch(FetchDescriptor<UserSettings>(
                predicate: #Predicate { $0.settingsKey == "default" },
                sortBy: [SortDescriptor(\.createdAt)]
            )).first
        } catch {
            NSLog("Liminalog: failed to fetch settings in StartChapterIntent Live Activity update: \(String(describing: error))")
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
            NSLog("Liminalog: failed to fetch categories in StartChapterIntent Live Activity update: \(String(describing: error))")
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

enum StartChapterIntentError: LocalizedError {
    case invalidCategoryID
    case categoryNotFound
    case storeUnavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidCategoryID:
            return "カテゴリを特定できませんでした。アプリでカテゴリを選び直してください。"
        case .categoryNotFound:
            return "このカテゴリは見つかりませんでした。アプリでカテゴリを確認してください。"
        case .storeUnavailable:
            return "記録データを読み込めませんでした。時間をおいてもう一度試してください。"
        case .saveFailed:
            return "記録を開始できませんでした。時間をおいてもう一度試してください。"
        }
    }
}

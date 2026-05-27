import SwiftData

@Observable
@MainActor
final class AppStores {
    private let modelContext: ModelContext

    let categoryStore: CategoryStore
    let categorySetStore: CategorySetStore
    let planStore: PlanStore
    let scoreStore: ScoreStore
    let liveActivityCoordinator: LiveActivityCoordinator
    let chapterStore: ChapterStore

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        self.modelContext = modelContext
        let categoryStore = CategoryStore(modelContext: modelContext)
        let categorySetStore = CategorySetStore(modelContext: modelContext, categoryStore: categoryStore)

        self.categoryStore = categoryStore
        self.categorySetStore = categorySetStore
        self.planStore = PlanStore(modelContext: modelContext, clock: clock)
        self.scoreStore = ScoreStore(modelContext: modelContext, clock: clock)
        self.liveActivityCoordinator = LiveActivityCoordinator(categorySetStore: categorySetStore)
        self.chapterStore = ChapterStore(modelContext: modelContext, clock: clock)
    }

    @discardableResult
    func bootstrap() -> ChapterStore {
        SeedCoordinator.ensureUserSettings(in: modelContext)
        SeedCoordinator.consolidateBuiltInVisibilityPresets(in: modelContext)
        chapterStore.pruneShortChapters()
        chapterStore.seedDefaultCategorySetsIfNeeded()
        return chapterStore
    }
}

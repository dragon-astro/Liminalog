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
        let planStore = PlanStore(modelContext: modelContext, clock: clock)
        let scoreStore = ScoreStore(modelContext: modelContext, clock: clock)
        let liveActivityCoordinator = LiveActivityCoordinator(categorySetStore: categorySetStore)

        self.categoryStore = categoryStore
        self.categorySetStore = categorySetStore
        self.planStore = planStore
        self.scoreStore = scoreStore
        self.liveActivityCoordinator = liveActivityCoordinator
        self.chapterStore = ChapterStore(
            modelContext: modelContext,
            clock: clock,
            categoryStore: categoryStore,
            categorySetStore: categorySetStore,
            planStore: planStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
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

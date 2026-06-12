import Foundation
import SwiftData

@Observable
@MainActor
final class AppStores {
    let categoryStore: CategoryStore
    let categorySetStore: CategorySetStore
    let planStore: PlanStore
    let scoreStore: ScoreStore
    let unlockStore: UnlockStore
    let streakNotificationStore: StreakNotificationStore
    let liveActivityCoordinator: LiveActivityCoordinator
    let chapterStore: ChapterStore
    let bootstrapStore: BootstrapStore

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        let categoryStore = CategoryStore(modelContext: modelContext)
        let categorySetStore = CategorySetStore(modelContext: modelContext, categoryStore: categoryStore)
        let planStore = PlanStore(modelContext: modelContext, clock: clock)
        let scoreStore = ScoreStore(modelContext: modelContext, clock: clock)
        let unlockStore = UnlockStore(modelContext: modelContext)
        let streakNotificationStore = StreakNotificationStore(modelContext: modelContext)
        let liveActivityCoordinator = LiveActivityCoordinator(categorySetStore: categorySetStore)
        let chapterStore = ChapterStore(
            modelContext: modelContext,
            clock: clock,
            categoryStore: categoryStore,
            categorySetStore: categorySetStore,
            planStore: planStore,
            liveActivityCoordinator: liveActivityCoordinator
        )
        let bootstrapStore = BootstrapStore(
            modelContext: modelContext,
            categorySetStore: categorySetStore,
            unlockStore: unlockStore,
            chapterStore: chapterStore
        )

        self.categoryStore = categoryStore
        self.categorySetStore = categorySetStore
        self.planStore = planStore
        self.scoreStore = scoreStore
        self.unlockStore = unlockStore
        self.streakNotificationStore = streakNotificationStore
        self.liveActivityCoordinator = liveActivityCoordinator
        self.chapterStore = chapterStore
        self.bootstrapStore = bootstrapStore
    }

    @discardableResult
    func bootstrap() -> ChapterStore {
        bootstrapStore.bootstrap()
    }

    @discardableResult
    func bootstrapWithStoreReadinessRetry() async -> ChapterStore {
        await bootstrapStore.bootstrapWithStoreReadinessRetry()
    }
}

import Foundation
import SwiftData

@MainActor
final class BootstrapStore {
    private let modelContext: ModelContext
    private let categorySetStore: CategorySetStore
    private let unlockStore: UnlockStore
    private let chapterStore: ChapterStore

    init(
        modelContext: ModelContext,
        categorySetStore: CategorySetStore,
        unlockStore: UnlockStore,
        chapterStore: ChapterStore
    ) {
        self.modelContext = modelContext
        self.categorySetStore = categorySetStore
        self.unlockStore = unlockStore
        self.chapterStore = chapterStore
    }

    @discardableResult
    func bootstrap(now: Date = Date()) -> ChapterStore {
        let result = bootstrapAttempt(now: now)
        if !result.didRunUserScopedSeeds {
            NSLog("Liminalog: skipped bootstrap user-scoped seeds because UserSettings could not be fetched")
        }
        return chapterStore
    }

    @discardableResult
    func bootstrapWithStoreReadinessRetry(
        now: Date = Date(),
        retryDelaysNanoseconds: [UInt64] = [
            150_000_000,
            350_000_000,
            750_000_000
        ]
    ) async -> ChapterStore {
        var result = bootstrapAttempt(now: now)
        for delay in retryDelaysNanoseconds where !result.didRunUserScopedSeeds {
            NSLog("Liminalog: retrying bootstrap after store readiness fetch failure")
            try? await Task.sleep(nanoseconds: delay)
            result = bootstrapAttempt(now: now)
        }

        if !result.didRunUserScopedSeeds {
            NSLog("Liminalog: skipped bootstrap user-scoped seeds because UserSettings could not be fetched")
        }
        return chapterStore
    }

    private func bootstrapAttempt(now: Date) -> BootstrapAttemptResult {
        // CloudKitインポートで合流した重複（各端末のシード等）を、シードより先に統合する。
        CloudDuplicateMergeStore(modelContext: modelContext).mergeAll()
        let didRunUserScopedSeeds: Bool
        if SeedCoordinator.ensureUserSettingsIfAvailable(in: modelContext, now: now) != nil {
            SeedCoordinator.consolidateBuiltInVisibilityPresets(in: modelContext, now: now)
            SeedCoordinator.seedInitialFriendSetsIfNeeded(in: modelContext, now: now)
            didRunUserScopedSeeds = true
        } else {
            didRunUserScopedSeeds = false
        }
        unlockStore.seedMasterItems(now: now)

        #if DEBUG
        if shouldSeedDebugFriends {
            SeedCoordinator.seedDebugFriendsIfNeeded(in: modelContext, now: now)
        }
        #endif

        chapterStore.pruneShortChapters()
        categorySetStore.seedDefaultCategorySetsIfNeeded()
        chapterStore.restoreRecordingStateAfterLaunch()
        return BootstrapAttemptResult(didRunUserScopedSeeds: didRunUserScopedSeeds)
    }

    private struct BootstrapAttemptResult {
        var didRunUserScopedSeeds: Bool
    }

    #if DEBUG
    private var shouldSeedDebugFriends: Bool {
        UserDefaults.standard.bool(forKey: "LiminalogSeedDevFriends")
            || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedDevFriends")
    }
    #endif
}

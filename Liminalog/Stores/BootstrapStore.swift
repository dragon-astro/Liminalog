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
        // CloudKitインポートで合流した重複（各端末のシード等）を、シードより先に統合する。
        CloudDuplicateMergeStore(modelContext: modelContext).mergeAll()
        if SeedCoordinator.ensureUserSettingsIfAvailable(in: modelContext, now: now) != nil {
            SeedCoordinator.consolidateBuiltInVisibilityPresets(in: modelContext, now: now)
            SeedCoordinator.seedInitialFriendSetsIfNeeded(in: modelContext, now: now)
        } else {
            NSLog("Liminalog: skipped bootstrap user-scoped seeds because UserSettings could not be fetched")
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
        return chapterStore
    }

    #if DEBUG
    private var shouldSeedDebugFriends: Bool {
        UserDefaults.standard.bool(forKey: "LiminalogSeedDevFriends")
            || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedDevFriends")
    }
    #endif
}

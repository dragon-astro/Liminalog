import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("BootstrapStore")
struct BootstrapStoreTests {
    @Test("起動時にsingletonとmaster seedを作成し二重実行しても増殖しない")
    func bootstrapSeedsRequiredDataIdempotently() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9)))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let stores = AppStores(modelContext: context, clock: MutableTestClock(now: now))

        stores.bootstrapStore.bootstrap(now: now)
        stores.bootstrapStore.bootstrap(now: now)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let builtInPresets = try context.fetch(FetchDescriptor<VisibilityPreset>()).filter { $0.builtInKey != nil }
        let unlockItems = try context.fetch(FetchDescriptor<UnlockItem>())
        let categories = try context.fetch(FetchDescriptor<Liminalog.Category>())
        let categorySets = try context.fetch(FetchDescriptor<CategorySet>())
        let friendSets = try context.fetch(FetchDescriptor<FriendSet>())

        #expect(settings.count == 1)
        #expect(settings.first?.didSeedInitialFriendSets == true)
        #expect(Set(builtInPresets.compactMap(\.builtInKey)) == ["close_friends", "acquaintances", "off"])
        #expect(builtInPresets.count == 3)
        #expect(Set(builtInPresets.map(\.name)) == ["詳細", "控えめ", "オフ"])
        #expect(unlockItems.count == UnlockCatalog.items.count)
        #expect(categories.count == 6)
        #expect(categorySets.count == 2)
        #expect(friendSets.count == 1)
        #expect(friendSets.first?.name == "仲良し")
        #expect(friendSets.first?.memberFriendIDs.isEmpty == true)
    }

    @Test("アプリ起動用のreadiness retry付きbootstrapでもseedは増殖しない")
    func bootstrapWithStoreReadinessRetrySeedsRequiredDataIdempotently() async throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 9)))
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let stores = AppStores(modelContext: context, clock: MutableTestClock(now: now))

        await stores.bootstrapStore.bootstrapWithStoreReadinessRetry(now: now, retryDelaysNanoseconds: [])
        await stores.bootstrapStore.bootstrapWithStoreReadinessRetry(now: now, retryDelaysNanoseconds: [])

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let builtInPresets = try context.fetch(FetchDescriptor<VisibilityPreset>()).filter { $0.builtInKey != nil }
        let unlockItems = try context.fetch(FetchDescriptor<UnlockItem>())
        let categorySets = try context.fetch(FetchDescriptor<CategorySet>())
        let friendSets = try context.fetch(FetchDescriptor<FriendSet>())

        #expect(settings.count == 1)
        #expect(settings.first?.didSeedInitialFriendSets == true)
        #expect(builtInPresets.count == 3)
        #expect(unlockItems.count == UnlockCatalog.items.count)
        #expect(categorySets.count == 2)
        #expect(friendSets.count == 1)
    }

    @Test("初期FriendSetは削除後に復活しない")
    func initialFriendSetDoesNotReseedAfterDeletion() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let stores = AppStores(modelContext: context, clock: MutableTestClock(now: Date()))

        stores.bootstrapStore.bootstrap()
        let initialSet = try #require(try context.fetch(FetchDescriptor<FriendSet>()).first)
        context.delete(initialSet)
        try context.save()

        stores.bootstrapStore.bootstrap()

        #expect(try context.fetch(FetchDescriptor<FriendSet>()).isEmpty)
    }
}

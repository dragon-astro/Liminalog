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
        #expect(categories.count == 8)
        #expect(Set(categories.map(\.name)) == ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味", "自由時間", "家事"])
        #expect(categorySets.count == 2)
        #expect(Set(categorySets.map(\.name)) == ["平日", "休日"])
        #expect(categorySets.allSatisfy { $0.filledCount == CategorySet.slotCount })
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
        #expect(categorySets.allSatisfy { $0.filledCount == CategorySet.slotCount })
        #expect(friendSets.count == 1)
    }

    @Test("旧初期カテゴリセットは8カテゴリ8スロットへ補修される")
    func bootstrapRepairsLegacyDefaultCategoryTables() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let stores = AppStores(modelContext: context, clock: MutableTestClock(now: Date()))

        let categories = [
            Category(name: "勉強", colorHex: "#2F80ED", icon: "book.closed.fill", sortOrder: 0, isDefault: true),
            Category(name: "仕事", colorHex: "#6C5CE7", icon: "briefcase.fill", sortOrder: 1, isDefault: true),
            Category(name: "移動", colorHex: "#F2994A", icon: "tram.fill", sortOrder: 2, isDefault: true),
            Category(name: "休憩", colorHex: "#27AE60", icon: "cup.and.saucer.fill", sortOrder: 3, isDefault: true),
            Category(name: "睡眠", colorHex: "#9B51E0", icon: "moon.fill", sortOrder: 4, isDefault: true),
            Category(name: "趣味", colorHex: "#EB5757", icon: "sparkles", sortOrder: 5, isDefault: true)
        ]
        categories.forEach(context.insert)
        context.insert(CategorySet(
            name: "平日",
            sortOrder: 0,
            slots: categories.map { Optional($0.id) } + [nil, nil],
            isDefault: true
        ))
        context.insert(CategorySet(
            name: "休日",
            sortOrder: 1,
            slots: [categories[4].id, categories[5].id, categories[3].id, categories[0].id, categories[2].id, nil, nil, nil],
            isDefault: true
        ))
        try context.save()

        stores.bootstrapStore.bootstrap()

        let seededCategories = try context.fetch(FetchDescriptor<Liminalog.Category>())
        let categorySets = try context.fetch(FetchDescriptor<CategorySet>())
        #expect(seededCategories.count == 8)
        #expect(Set(seededCategories.map(\.name)).isSuperset(of: ["自由時間", "家事"]))
        #expect(categorySets.count == 2)
        #expect(categorySets.allSatisfy { $0.filledCount == CategorySet.slotCount })
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

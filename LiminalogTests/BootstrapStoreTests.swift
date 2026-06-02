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

        #expect(settings.count == 1)
        #expect(Set(builtInPresets.compactMap(\.builtInKey)) == ["close_friends", "acquaintances", "off"])
        #expect(builtInPresets.count == 3)
        #expect(unlockItems.count == UnlockCatalog.items.count)
        #expect(categories.count == 6)
        #expect(categorySets.count == 2)
    }
}

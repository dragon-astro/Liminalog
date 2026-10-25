#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("Editing samples")
struct PreviewEditingSamplesTests {
    @Test("Sample libraries cover multiple boards, placement modes and valid day schedules without duplicates")
    func samplesCoverEditingWorkflows() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let categories = CategoryStore(modelContext: context)
        _ = CategorySetStore(modelContext: context, categoryStore: categories).seedDefaultCategorySetsIfNeeded()
        #expect(PreviewSupport.seedEditingSamplesIfNeeded(in: context, defaults: nil))
        let store = PlanPresetStore(modelContext: context)
        let plans = try #require(store.planPresetsIfAvailable())
        let days = try #require(store.dayPresetsIfAvailable())
        #expect(categories.allCategories().count == 16)
        #expect(try context.fetchCount(FetchDescriptor<CategorySet>()) == 4)
        #expect(plans.count == 16 && days.count == 5)
        #expect(plans.allSatisfy { !$0.snapshot.isMemo } && plans.contains { $0.isAllDay })
        #expect(plans.contains { $0.placementMode == .fixedTime } && plans.contains { $0.placementMode == .duration })
        let ids = Set(categories.allCategories().map(\.id))
        for plan in plans {
            #expect(plan.snapshot.hasValidTime)
            #expect(plan.categoryID.map(ids.contains) == true)
            #expect(plan.recurrenceData == nil && plan.reminderMinutesBefore == nil && !plan.isPublic)
        }
        for day in days {
            let items = try DayPresetItemsCodec.decode(day.itemsData)
            #expect(items.count == day.itemCount && items.allSatisfy(\.hasValidTime))
            #expect(items.allSatisfy { $0.categoryID.map(ids.contains) == true && !$0.isPublic })
            let main = items.filter { !$0.isMemo && !$0.isAllDay }.sorted { $0.startMinute < $1.startMinute }
            #expect(zip(main, main.dropFirst()).allSatisfy { $0.endMinute <= $1.startMinute })
        }
        _ = PreviewSupport.seedEditingSamplesIfNeeded(in: context, defaults: nil)
        #expect(store.planPresetsIfAvailable()?.count == plans.count)
        #expect(store.dayPresetsIfAvailable()?.count == days.count)
        #expect(categories.allCategories().count == 16)
    }

    @Test("Development import preserves existing data and does not restore samples the user removed")
    func sampleImportPreservesUserEdits() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let suite = "EditingSamplesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = Category(name: "読書", colorHex: "#123456", icon: "bookmark")
        context.insert(custom)
        let preset = PlanPreset(name: "読書", title: "自分の読書", categoryID: custom.id, startMinute: 660, endMinute: 705)
        context.insert(preset)
        try context.save()
        #expect(PreviewSupport.seedEditingSamplesIfNeeded(in: context, defaults: defaults))
        #expect(custom.colorHex == "#123456" && preset.title == "自分の読書" && preset.startMinute == 660)
        let removed = try #require(context.fetch(FetchDescriptor<DayPreset>()).first)
        context.delete(removed)
        preset.name = "書き換えたプリセット"
        try context.save()
        #expect(!PreviewSupport.seedEditingSamplesIfNeeded(in: context, defaults: defaults))
        #expect(try context.fetchCount(FetchDescriptor<DayPreset>()) == 4)
        #expect(preset.name == "書き換えたプリセット")
        #expect(try context.fetchCount(FetchDescriptor<PlanPreset>()) == 16)
    }
}
#endif

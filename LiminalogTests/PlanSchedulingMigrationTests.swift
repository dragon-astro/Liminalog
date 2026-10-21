import Foundation
import SwiftData
import Testing
@testable import Liminalog

private enum BeforeScheduling {
    // The persisted preset layout before recurrence/reminder fields were added.
    @Model final class PlanPreset {
        var id: UUID = UUID()
        var name: String = ""
        var title: String = ""
        var categoryID: UUID?
        var startMinute: Int = 540
        var endMinute: Int = 600
        var isAllDay: Bool = false
        var isImportant: Bool = false
        var note: String?
        var isPublic: Bool = true
        var placementModeRawValue: String = "duration"
        var sortOrder: Int = 0
        var lastUsedAt: Date?
        var useCount: Int = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        init() {}
    }
}

@MainActor
struct PlanSchedulingMigrationTests {
    @Test func existingDiskPresetMigratesWithoutLosingValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("schedule.store")
        let id = UUID()
        func writeOldStore() throws {
            let schema = Schema([BeforeScheduling.PlanPreset.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let old = BeforeScheduling.PlanPreset()
            old.id = id; old.name = "移行前"; old.title = "元の予定"; old.note = "保持するメモ"
            old.sortOrder = 7; old.useCount = 4
            container.mainContext.insert(old)
            try container.mainContext.save()
        }
        try writeOldStore()
        let schema = Schema([Liminalog.PlanPreset.self, DayPreset.self, PlanRecurrenceOccurrence.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let migrated = try #require(container.mainContext.fetch(FetchDescriptor<Liminalog.PlanPreset>()).first)
        #expect(migrated.id == id)
        #expect(!migrated.isMemo)
        #expect(migrated.name == "移行前")
        #expect(migrated.title == "元の予定")
        #expect(migrated.note == "保持するメモ")
        #expect(migrated.sortOrder == 7)
        #expect(migrated.useCount == 4)
        #expect(migrated.recurrenceData == nil && migrated.reminderMinutesBefore == nil)
        let occurrence = PlanRecurrenceOccurrence(seriesID: id, itemID: id, day: Date())
        container.mainContext.insert(occurrence)
        try container.mainContext.save()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PlanRecurrenceOccurrence>()) == 1)
    }
}

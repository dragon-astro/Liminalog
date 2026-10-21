import Foundation
import SwiftData
import Testing
@testable import Liminalog

private enum BeforeMemo {
    @Model final class PlanBlock {
        var id: UUID = UUID()
        var title: String = ""
        var startTime: Date = Date()
        var endTime: Date = Date()
        var isAllDay: Bool = false
        var isImportant: Bool = false
        var note: String?
        var isPublic: Bool = true
        var visibilityScope: VisibilityScope = VisibilityScope.all
        var audienceFriendIDs: [UUID] = []
        var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
        var hasAudienceSnapshot: Bool = false
        var reminderMinutesBefore: Int?
        var recurrenceSeriesID: UUID?
        var sourceEventID: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        init() {}
    }
}

@MainActor
struct PlanMemoMigrationTests {
    @Test func oldDiskPlanDefaultsToMainAndRetainsTimesAndMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old-plan.store")
        let id = UUID(), series = UUID(), start = Date(timeIntervalSince1970: 1_790_000_000)
        func writeOld() throws {
            let schema = Schema([BeforeMemo.PlanBlock.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let old = BeforeMemo.PlanBlock()
            old.id = id; old.title = "既存の仕事"; old.startTime = start; old.endTime = start.addingTimeInterval(7200)
            old.note = "保存済み"; old.reminderMinutesBefore = 10; old.recurrenceSeriesID = series
            container.mainContext.insert(old)
            try container.mainContext.save()
        }
        try writeOld()
        let schema = Schema([Liminalog.PlanBlock.self, Category.self, Chapter.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let plan = try #require(container.mainContext.fetch(FetchDescriptor<Liminalog.PlanBlock>()).first)
        #expect(plan.id == id && !plan.isMemo)
        #expect(plan.startTime == start && plan.endTime == start.addingTimeInterval(7200))
        #expect(plan.title == "既存の仕事" && plan.note == "保存済み")
        #expect(plan.reminderMinutesBefore == 10 && plan.recurrenceSeriesID == series)
        #expect(plan.reminderDate == nil)
        plan.isMemo = true
        plan.reminderDate = start.addingTimeInterval(-7200)
        try container.mainContext.save()
        let reopened = ModelContext(container)
        let restored = try #require(reopened.fetch(FetchDescriptor<Liminalog.PlanBlock>()).first)
        #expect(restored.isMemo)
        #expect(restored.reminderDate == start.addingTimeInterval(-7200))
    }
}

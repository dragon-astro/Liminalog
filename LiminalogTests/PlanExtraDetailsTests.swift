import Foundation
import SwiftData
import CloudKit
import Testing
@testable import Liminalog

@MainActor
struct PlanExtraDetailsTests {
    private var calendar: Calendar { .liminalogTest }
    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value))!
    }
    private func item() -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(title: "集合", categoryID: nil, startMinute: 540, endMinute: 600,
            isAllDay: false, isImportant: true, locationName: "  中央図書館 \n", urlString: " example.com/event ", isPublic: true)
    }

    @Test func normalizationLimitsAndWebSchemes() {
        #expect(PlanExtraDetails.normalized(" \n ") == nil)
        #expect(PlanExtraDetails.isValid(location: String(repeating: "あ", count: 100), url: String(repeating: "a", count: 2000)))
        #expect(!PlanExtraDetails.isValid(location: String(repeating: "あ", count: 101), url: nil))
        #expect(!PlanExtraDetails.isValid(location: nil, url: String(repeating: "a", count: 2001)))
        #expect(PlanExtraDetails.webURL(" example.com/path?q=1 ")?.absoluteString == "https://example.com/path?q=1")
        #expect(PlanExtraDetails.webURL("http://example.com")?.scheme == "http")
        for invalid in ["javascript:alert(1)", "file:///etc/passwd", "tel:123", "mailto:a@example.com", "https://", "https://example.com\n/path", ""] {
            #expect(PlanExtraDetails.webURL(invalid) == nil)
        }
    }

    @Test func oldCodablePayloadsDecodeWithoutNewFields() throws {
        let encoder = JSONEncoder()
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(item())) as? [String: Any])
        object.removeValue(forKey: "locationName"); object.removeValue(forKey: "urlString")
        let oldItem = try JSONDecoder().decode(PlanTemplateSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(oldItem.locationName == nil && oldItem.urlString == nil)
        let envelope = try DayPresetItemsCodec.encode([oldItem])
        #expect(try DayPresetItemsCodec.decode(envelope) == [oldItem])
        let plan = PlanBlock(category: nil, title: "旧予定", startTime: day(2), endTime: day(3))
        let baseline = try #require(PlanRecurrenceBaseline(plan).data)
        var baselineObject = try #require(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
        baselineObject.removeValue(forKey: "locationName"); baselineObject.removeValue(forKey: "urlString")
        #expect(PlanRecurrenceBaseline(plan).matches(try JSONSerialization.data(withJSONObject: baselineObject)))
    }

    @Test func presetDayPresetApplicationAndMovesKeepDetails() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let preset = try #require(presets.createPlanPreset(name: "集合", snapshot: item()))
        #expect(preset.locationName == "中央図書館")
        let dayPreset = try #require(presets.createDayPreset(name: "休日", items: [preset.snapshot]))
        let savedItems = try presets.items(for: dayPreset).get()
        let store = PlanStore(modelContext: context, clock: clock, requestRefresh: { _, _, _ in })
        #expect(store.applyTemplates(savedItems.map { .init(snapshot: $0, resolvedCategory: nil) }, to: day(2), calendar: calendar))
        let plan = try #require(context.fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(plan.locationName == "中央図書館" && plan.urlString == "example.com/event")
        #expect(store.savePlanBlock(plan, category: nil, title: plan.title, startTime: day(2).addingTimeInterval(3600),
            endTime: day(2).addingTimeInterval(7200), isAllDay: false, isImportant: true, note: nil, isPublic: true))
        let reopened = try #require(ModelContext(container).fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(reopened.locationName == "中央図書館" && reopened.urlString == "example.com/event")
        #expect(PlanPresetStore.snapshot(from: reopened)?.urlString == "example.com/event")
        #expect(store.savePlanBlock(plan, category: nil, title: plan.title, startTime: plan.startTime, endTime: plan.endTime,
            isAllDay: false, isImportant: true, note: nil, locationName: " \n", urlString: "", isPublic: true))
        #expect(plan.locationName == nil && plan.urlString == nil)
    }

    @Test func recurrenceCopiesDetailsAndKeepsPersonalEdits() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let clock = MutableTestClock(now: day(1))
        let presets = PlanPresetStore(modelContext: context, clock: clock)
        let master = try #require(presets.createPlanPreset(name: "集合", snapshot: item(), recurrence: .some(
            PlanRecurrenceRule(frequency: .daily, startDate: day(2), occurrenceLimit: 2))))
        let recurring = PlanRecurrenceStore(modelContext: context, clock: clock, calendar: calendar)
        _ = try recurring.materialize(to: day(4))
        let plans = try context.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.startTime)]))
        #expect(plans.count == 2)
        #expect(plans.allSatisfy { $0.locationName == "中央図書館" && $0.urlString == "example.com/event" })
        plans[0].locationName = "別の場所"
        try context.save()
        master.locationName = "新しい場所"; master.urlString = "example.com/new"
        try context.save()
        _ = try recurring.materialize(to: day(4))
        #expect(plans[0].locationName == "別の場所" && plans[0].urlString == "example.com/event")
        #expect(plans[1].locationName == "新しい場所" && plans[1].urlString == "example.com/new")
    }

    @Test func sharedDetailsRespectPrivacyAndCloudKitRoundTrip() throws {
        let plan = PlanBlock(category: nil, title: "集合", startTime: day(2), endTime: day(3),
            locationName: "図書館", urlString: "https://example.com", isPublic: true)
        let snapshot = try #require(FriendSharedPlanSnapshot.snapshots(from: [plan]).first)
        #expect(snapshot.locationName == "図書館" && snapshot.urlString == "https://example.com")
        let record = CKRecord(recordType: FriendSharedItemRecordPolicy.planRecordType)
        let parent = CKRecord.ID(recordName: "test-parent")
        FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: parent)
        #expect(FriendSharedItemRecordPolicy.planSnapshot(from: record) == snapshot)
        let cache = FriendSharedPlanRecord(friendID: UUID(), snapshot: snapshot)
        #expect(cache.snapshot == snapshot)
        let restricted = VisibilityPreset(name: "控えめ", hideMoodAndNote: true, hideLocation: true)
        let restrictedSnapshot = try #require(FriendSharedPlanSnapshot.snapshots(from: [plan], visibilityPreset: restricted).first)
        #expect(restrictedSnapshot.locationName == nil && restrictedSnapshot.urlString == nil)
        let free = try #require(FriendSharedPlanSnapshot.snapshots(from: [plan], visibilityPreset: VisibilityPreset(name: "空き", freeTimeOnly: true)).first)
        #expect(free.locationName == nil && free.urlString == nil)
        #expect(FriendSharePublishDiffPolicy.fingerprint(snapshot) != FriendSharePublishDiffPolicy.fingerprint(free))
        FriendSharedItemRecordPolicy.apply(free, to: record, parentRecordID: parent)
        #expect(record["locationName"] == nil && record["urlString"] == nil)
        plan.isPublic = false
        #expect(FriendSharedPlanSnapshot.snapshots(from: [plan]).isEmpty)
    }

    @Test func overlongDetailsAreRejectedBeforeMutation() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: day(1)), requestRefresh: { _, _, _ in })
        let long = String(repeating: "a", count: 101)
        #expect(store.createPlanBlock(category: nil, title: "集合", startTime: day(2), endTime: day(3), locationName: long) == nil)
        var invalid = item(); invalid.locationName = long
        #expect(!store.applyTemplates([.init(snapshot: invalid, resolvedCategory: nil)], to: day(2), calendar: calendar))
        #expect(PlanPresetStore(modelContext: context).createPlanPreset(name: "集合", snapshot: invalid) == nil)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
    }
    @Test func openingURLInvokesBrowserOnlyForWebURLs() {
        var opened: [URL] = []
        #expect(PlanExtraDetails.openWebURL("example.com/meet") { opened.append($0) })
        #expect(!PlanExtraDetails.openWebURL("javascript:alert(1)") { opened.append($0) })
        #expect(opened.map(\.absoluteString) == ["https://example.com/meet"])
    }

    @Test func existingOnDiskPresetMigratesWithoutNewFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        try autoreleasepool {
            let schema = Schema([LegacyPlanDetailsModels.PlanPreset.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let preset = LegacyPlanDetailsModels.PlanPreset(name: "旧プリセット", title: "以前の予定")
            container.mainContext.insert(preset)
            try container.mainContext.save()
        }
        try autoreleasepool {
            let schema = Schema([PlanPreset.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let saved = try #require(container.mainContext.fetch(FetchDescriptor<PlanPreset>()).first)
            #expect(saved.title == "以前の予定")
            #expect(saved.locationName == nil && saved.urlString == nil)
            saved.locationName = "図書館"; saved.urlString = "example.com"
            try container.mainContext.save()
        }
        let schema = Schema([PlanPreset.self])
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<PlanPreset>()).first)
        #expect(saved.locationName == "図書館" && saved.urlString == "example.com")
    }

    @Test func replacementSplitsRetainOriginalDetails() throws {
        let container = try TestModelContainer.make(); let context = container.mainContext
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: day(1)), requestRefresh: { _, _, _ in })
        _ = try #require(store.createPlanBlock(category: nil, title: "元の予定", startTime: day(2).addingTimeInterval(8 * 3600),
            endTime: day(2).addingTimeInterval(11 * 3600), locationName: "元の場所", urlString: "example.com/original"))
        let applications = [PlanStore.TemplateApplication(snapshot: item(), resolvedCategory: nil)]
        let replacement = try #require(store.templateReplacementPreview(applications, to: day(2), mode: .keepRemainders, calendar: calendar))
        #expect(store.applyTemplates(applications, to: day(2), calendar: calendar, approvedReplacement: replacement))
        let remaining = try context.fetch(FetchDescriptor<PlanBlock>()).filter { $0.title == "元の予定" }
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { $0.locationName == "元の場所" && $0.urlString == "example.com/original" })
    }

}

// Exact pre-change persistent model, scoped for a real on-disk migration test.
private enum LegacyPlanDetailsModels {
@Model
final class PlanPreset {
    var id: UUID = UUID()
    var name: String = ""
    var title: String = ""
    var categoryID: UUID?
    var startMinute: Int = 9 * 60
    var endMinute: Int = 10 * 60
    var isMemo: Bool = false
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var reminderMinutesBefore: Int?
    var placementModeRawValue: String = PlanPresetPlacementMode.duration.rawValue
    var sortOrder: Int = 0
    var recurrenceData: Data?
    var lastUsedAt: Date?
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        name: String,
        title: String,
        categoryID: UUID? = nil,
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        placementMode: PlanPresetPlacementMode = .duration,
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.title = title
        self.categoryID = categoryID
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.isAllDay = isAllDay
        self.isImportant = isImportant
        self.note = note
        self.isPublic = isPublic
        self.placementModeRawValue = placementMode.rawValue
        self.sortOrder = sortOrder
        self.lastUsedAt = nil
        self.useCount = 0
        self.createdAt = now
        self.updatedAt = now
    }

    var snapshot: PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title,
            categoryID: categoryID,
            startMinute: startMinute,
            endMinute: endMinute,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note,
            isPublic: isPublic,
            reminderMinutesBefore: reminderMinutesBefore,
            isMemo: false
        )
    }

    var placementMode: PlanPresetPlacementMode {
        get { PlanPresetPlacementMode(rawValue: placementModeRawValue) ?? .duration }
        set { placementModeRawValue = newValue.rawValue }
    }

    /// 予定プリセットは予定名そのものを識別名として扱う。
    /// 旧データで予定名が空の場合だけ、従来のプリセット名へフォールバックする。
    var displayName: String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? name : normalizedTitle
    }
}

}

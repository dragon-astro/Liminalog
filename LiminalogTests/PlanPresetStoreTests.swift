import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("PlanPresetStore")
struct PlanPresetStoreTests {
    private let calendar = Calendar.liminalogTest

    @Test("予定プリセットを作成更新し使用回数を記録する")
    func planPresetCRUDAndUsage() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let firstNow = try date(2026, 9, 2, 12, 0)
        let clock = MutableTestClock(now: firstNow)
        let store = PlanPresetStore(modelContext: context, clock: clock)
        let categoryID = UUID()
        let original = snapshot(title: "ジム", categoryID: categoryID)

        let preset = try #require(store.createPlanPreset(
            name: "",
            snapshot: original,
            placementMode: .fixedTime
        ))
        #expect(preset.name == "ジム")
        #expect(preset.categoryID == categoryID)
        #expect(preset.snapshot == original)
        #expect(preset.placementMode == .fixedTime)

        let secondNow = try date(2026, 9, 2, 13, 0)
        clock.now = secondNow
        var updated = original
        updated.title = "筋トレ"
        updated.note = "脚の日"
        #expect(store.updatePlanPreset(
            preset,
            name: "運動",
            snapshot: updated,
            placementMode: .duration
        ))
        #expect(preset.name == "運動")
        #expect(preset.title == "筋トレ")
        #expect(preset.updatedAt == secondNow)
        #expect(preset.placementMode == .duration)

        #expect(store.markUsed(preset))
        #expect(preset.useCount == 1)
        #expect(preset.lastUsedAt == secondNow)
    }

    @Test("一日プリセットはcodec済みitemsと件数を同期する")
    func dayPresetCRUD() throws {
        let container = try TestModelContainer.make()
        let store = PlanPresetStore(modelContext: container.mainContext)
        let items = [
            snapshot(title: "仕事", start: 9 * 60, end: 17 * 60),
            snapshot(title: "運動", start: 19 * 60, end: 20 * 60)
        ]

        let preset = try #require(store.createDayPreset(name: "平日", items: items, colorHex: "#27AE60", icon: "leaf.fill"))

        #expect(preset.itemCount == 2)
        #expect(preset.colorHex == "#27AE60" && preset.icon == "leaf.fill")
        #expect(try store.items(for: preset).get() == items)

        let updated = [snapshot(title: "休み", start: 10 * 60, end: 11 * 60)]
        #expect(store.updateDayPreset(preset, name: "休日", items: updated))
        #expect(preset.name == "休日")
        #expect(preset.itemCount == 1)
        #expect(preset.colorHex == "#27AE60" && preset.icon == "leaf.fill")
        #expect(store.updateDayPreset(preset, name: "休日", items: updated, colorHex: "#7C5CFF", icon: "moon.fill"))
        let loaded = try #require(ModelContext(container).fetch(FetchDescriptor<DayPreset>()).first)
        #expect(loaded.colorHex == "#7C5CFF" && loaded.icon == "moon.fill")
        #expect(try store.items(for: preset).get() == updated)
    }

    @Test("破損したitemsDataを削除せず読取エラーとして返す")
    func corruptDayPresetIsPreserved() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let preset = DayPreset(name: "別端末", itemsData: Data("bad".utf8), itemCount: 3)
        context.insert(preset)
        try context.save()
        let store = PlanPresetStore(modelContext: context)

        #expect(store.items(for: preset) == .failure(.invalidPayload))
        #expect(store.dayPresetsIfAvailable()?.map(\.id) == [preset.id])
    }

    @Test("件数上限と内部重複と終日上限を拒否する")
    func dayPresetValidation() throws {
        let container = try TestModelContainer.make()
        let store = PlanPresetStore(modelContext: container.mainContext)
        let overlapping = [
            snapshot(title: "A", start: 9 * 60, end: 10 * 60),
            snapshot(title: "B", start: 9 * 60 + 30, end: 11 * 60)
        ]
        let tooManyAllDay = (0..<4).map {
            snapshot(title: "終日\($0)", start: 0, end: 24 * 60, isAllDay: true)
        }
        let tooMany = (0..<25).map {
            snapshot(title: "\($0)", start: $0 * 30, end: $0 * 30 + 15)
        }
        let malformedAllDay = [
            snapshot(title: "複数日終日", start: 0, end: 2 * 24 * 60, isAllDay: true)
        ]

        #expect(store.createDayPreset(name: "重複", items: overlapping) == nil)
        #expect(store.createDayPreset(name: "終日", items: tooManyAllDay) == nil)
        #expect(store.createDayPreset(name: "多すぎ", items: tooMany) == nil)
        #expect(store.createDayPreset(name: "複数日", items: malformedAllDay) == nil)
    }

    @Test("既存日からの作成では対象日前開始と24時間超と複数日終日を除外する")
    func dayPresetDraftExclusions() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let target = try date(2026, 9, 3, 12, 0)
        let valid = PlanBlock(
            category: nil,
            title: "有効",
            startTime: try date(2026, 9, 3, 9, 0),
            endTime: try date(2026, 9, 3, 10, 0)
        )
        let previousStart = PlanBlock(
            category: nil,
            title: "前日開始",
            startTime: try date(2026, 9, 2, 23, 0),
            endTime: try date(2026, 9, 3, 1, 0)
        )
        let tooLong = PlanBlock(
            category: nil,
            title: "長すぎ",
            startTime: try date(2026, 9, 3, 1, 0),
            endTime: try date(2026, 9, 4, 2, 0)
        )
        let multiDayAllDay = PlanBlock(
            category: nil,
            title: "複数日終日",
            startTime: try date(2026, 9, 3, 0, 0),
            endTime: try date(2026, 9, 5, 0, 0),
            isAllDay: true
        )
        [valid, previousStart, tooLong, multiDayAllDay].forEach(context.insert)
        let store = PlanPresetStore(modelContext: context)

        let draft = store.makeDayPresetDraft(
            from: target,
            plans: [valid, previousStart, tooLong, multiDayAllDay],
            calendar: calendar
        )

        #expect(draft.items.map(\.title) == ["有効"])
        #expect(draft.excludedItemCount == 3)
    }

    @Test("日跨ぎ予定を翌日分の分数へ変換する")
    func draftConvertsOvernightMinutes() throws {
        let container = try TestModelContainer.make()
        let target = try date(2026, 9, 3, 12, 0)
        let overnight = PlanBlock(
            category: nil,
            title: "睡眠",
            startTime: try date(2026, 9, 3, 23, 0),
            endTime: try date(2026, 9, 4, 7, 0)
        )
        let store = PlanPresetStore(modelContext: container.mainContext)

        let draft = store.makeDayPresetDraft(
            from: target,
            plans: [overnight],
            calendar: calendar
        )

        #expect(draft.items.first?.startMinute == 23 * 60)
        #expect(draft.items.first?.endMinute == 31 * 60)
        #expect(draft.excludedItemCount == 0)
    }

    private func snapshot(
        title: String,
        categoryID: UUID? = nil,
        start: Int = 9 * 60,
        end: Int = 10 * 60,
        isAllDay: Bool = false
    ) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title,
            categoryID: categoryID,
            startMinute: start,
            endMinute: end,
            isAllDay: isAllDay,
            isImportant: false,
            note: nil,
            isPublic: true
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}

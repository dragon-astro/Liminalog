import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("CalendarEventSyncStore")
struct CalendarEventSyncStoreTests {
    @Test("終日イベントは非公開の時間未指定重要予定として取り込む")
    func allDayEventBecomesPrivateImportantAllDayPlan() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CalendarEventSyncStore(modelContext: context)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        let interval = DateInterval(start: start, end: end)

        let result = store.sync(
            snapshots: [
                CalendarEventSnapshot(
                    eventIdentifier: "event-1",
                    calendarIdentifier: "cal-main",
                    title: "病院",
                    startTime: start,
                    endTime: end,
                    isAllDay: true,
                    colorHex: "#2F80ED"
                )
            ],
            visibleInterval: interval,
            now: start
        )

        let plans = try context.fetch(FetchDescriptor<PlanBlock>())
        let caches = try context.fetch(FetchDescriptor<CalendarEventCache>())
        let plan = try #require(plans.first)

        #expect(result.insertedCaches == 1)
        #expect(result.insertedPlans == 1)
        #expect(caches.count == 1)
        #expect(plans.count == 1)
        #expect(plan.title == "病院")
        #expect(plan.isAllDay)
        #expect(plan.isImportant)
        #expect(!plan.isPublic)
        #expect(plan.sourceEventID == CalendarEventSnapshot.sourceEventID(eventIdentifier: "event-1", calendarIdentifier: "cal-main"))
    }

    @Test("時間指定イベントは非公開の時間つき予定として取り込む")
    func timedEventBecomesPrivateTimedPlan() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CalendarEventSyncStore(modelContext: context)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 13)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let interval = try #require(calendar.dateInterval(of: .day, for: start))

        store.sync(
            snapshots: [
                CalendarEventSnapshot(
                    eventIdentifier: "event-2",
                    calendarIdentifier: "cal-main",
                    title: "打ち合わせ",
                    startTime: start,
                    endTime: end,
                    isAllDay: false,
                    colorHex: nil
                )
            ],
            visibleInterval: interval,
            now: start
        )

        let plan = try #require(try context.fetch(FetchDescriptor<PlanBlock>()).first)
        #expect(plan.title == "打ち合わせ")
        #expect(!plan.isAllDay)
        #expect(!plan.isImportant)
        #expect(!plan.isPublic)
        #expect(plan.startTime == start)
        #expect(plan.endTime == end)
    }

    @Test("再同期は同じsourceEventIDを更新し消えたイベントを削除する")
    func syncUpdatesAndDeletesBySourceEventID() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CalendarEventSyncStore(modelContext: context)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13)))
        let firstStart = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
        let firstEnd = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let updatedStart = try #require(calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day))
        let updatedEnd = try #require(calendar.date(bySettingHour: 12, minute: 30, second: 0, of: day))
        let interval = try #require(calendar.dateInterval(of: .day, for: day))

        store.sync(
            snapshots: [
                CalendarEventSnapshot(
                    eventIdentifier: "event-3",
                    calendarIdentifier: "cal-main",
                    title: "古いタイトル",
                    startTime: firstStart,
                    endTime: firstEnd,
                    isAllDay: false,
                    colorHex: "#AAAAAA"
                )
            ],
            visibleInterval: interval,
            now: firstStart
        )

        let updateResult = store.sync(
            snapshots: [
                CalendarEventSnapshot(
                    eventIdentifier: "event-3",
                    calendarIdentifier: "cal-main",
                    title: "新しいタイトル",
                    startTime: updatedStart,
                    endTime: updatedEnd,
                    isAllDay: false,
                    colorHex: "#BBBBBB"
                )
            ],
            visibleInterval: interval,
            now: updatedStart
        )

        var plans = try context.fetch(FetchDescriptor<PlanBlock>())
        var caches = try context.fetch(FetchDescriptor<CalendarEventCache>())
        #expect(updateResult.updatedCaches == 1)
        #expect(updateResult.updatedPlans == 1)
        #expect(plans.count == 1)
        #expect(caches.count == 1)
        #expect(plans[0].title == "新しいタイトル")
        #expect(plans[0].startTime == updatedStart)
        #expect(caches[0].colorHex == "#BBBBBB")

        let deleteResult = store.sync(snapshots: [], visibleInterval: interval, now: updatedEnd)
        plans = try context.fetch(FetchDescriptor<PlanBlock>())
        caches = try context.fetch(FetchDescriptor<CalendarEventCache>())

        #expect(deleteResult.deletedCaches == 1)
        #expect(deleteResult.deletedPlans == 1)
        #expect(plans.isEmpty)
        #expect(caches.isEmpty)
    }
}

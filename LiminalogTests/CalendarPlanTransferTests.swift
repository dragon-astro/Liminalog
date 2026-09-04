import Foundation
import CoreGraphics
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("CalendarPlanTransfer")
struct CalendarPlanTransferTests {
    private var calendar: Calendar { Calendar.liminalogTest }
    private func day(_ number: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: number, hour: hour))!
    }
    private func plan(_ day: Int, endDay: Int? = nil, allDay: Bool = false) -> PlanBlock {
        PlanBlock(category: nil, title: "転記テスト", startTime: self.day(day, hour: allDay ? 0 : 9),
                  endTime: self.day(endDay ?? day, hour: allDay ? 0 : 10), isAllDay: allDay,
                  isImportant: true, note: "メモ", isPublic: false)
    }
    private func store(_ context: ModelContext) -> PlanStore {
        PlanStore(modelContext: context, clock: MutableTestClock(now: day(4)), requestRefresh: { _, _, _ in })
    }

    @Test("複数日へ複製しIDと公開設定を引き継ぐ")
    func copyMany() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        source.audienceFriendIDs = [UUID()]
        source.hasAudienceSnapshot = true
        source.sourceEventID = "external"
        context.insert(source)
        try context.save()
        let count = try store(context).transferPlan(id: source.id, to: [day(12), day(13)], mode: .copy, calendar: calendar).get()
        let plans = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(count == 2 && plans.count == 3)
        #expect(source.startTime == day(10) && source.sourceEventID == "external")
        let copies = plans.filter { $0.id != source.id }
        #expect(Set(copies.map(\.id)).count == 2)
        #expect(copies.allSatisfy { $0.note == source.note && $0.isImportant && !$0.isPublic
            && $0.audienceFriendIDs == source.audienceFriendIDs && $0.hasAudienceSnapshot && $0.sourceEventID == nil })
    }

    @Test("後ろの日付で重複しても一件も作らない")
    func atomicConflict() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        context.insert(source)
        context.insert(plan(13))
        try context.save()
        let result = store(context).transferPlan(id: source.id, to: [day(12), day(13)], mode: .copy, calendar: calendar)
        guard case .failure(.overlap) = result else { Issue.record("Expected conflict"); return }
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(!context.hasChanges)
    }

    @Test("移動は同じIDのまま、翌日終了を維持する")
    func moveOvernight() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10, endDay: 11)
        context.insert(source)
        try context.save()
        #expect(try store(context).transferPlan(id: source.id, to: [day(20)], mode: .move, calendar: calendar).get() == 1)
        #expect(source.startTime == day(20) && source.endTime == day(21, hour: 10))
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 1)
    }

    @Test("今日以前は移動不可だが複製元にはできる")
    func lockedSource() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(3)
        context.insert(source)
        try context.save()
        let store = store(context)
        guard case .failure(.locked) = store.transferPlan(id: source.id, to: [day(20)], mode: .move, calendar: calendar) else {
            Issue.record("Expected lock"); return
        }
        #expect(try store.transferPlan(id: source.id, to: [day(20)], mode: .copy, calendar: calendar).get() == 1)
        #expect(source.startTime == day(3))
    }

    @Test("移動先が今日以前・重複の場合は元予定を維持")
    func invalidDestination() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        context.insert(source)
        context.insert(plan(11))
        try context.save()
        let store = store(context)
        guard case .failure(.unavailableDay) = store.transferPlan(id: source.id, to: [day(4)], mode: .move, calendar: calendar),
              case .failure(.overlap) = store.transferPlan(id: source.id, to: [day(11)], mode: .move, calendar: calendar) else {
            Issue.record("Expected rejection"); return
        }
        #expect(source.startTime == day(10) && !context.hasChanges)
    }

    @Test("終日複数日の排他的終了日と重複許可を維持")
    func allDaySpan() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10, endDay: 13, allDay: true)
        context.insert(source)
        try context.save()
        #expect(try store(context).transferPlan(id: source.id, to: [day(1), day(2)], mode: .copy, calendar: calendar).get() == 2)
        let copied = try #require(context.fetch(FetchDescriptor<PlanBlock>()).first { $0.startTime == day(1, hour: 0) })
        #expect(copied.endTime == day(4, hour: 0))
    }

    @Test("選択日重複は一件に正規化、同日移動は保存しない")
    func normalizedDaysAndNoOp() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        context.insert(source)
        try context.save()
        let store = store(context)
        #expect(try store.transferPlan(id: source.id, to: [day(12), day(12, hour: 18)], mode: .copy, calendar: calendar).get() == 1)
        #expect(try store.transferPlan(id: source.id, to: [day(10)], mode: .move, calendar: calendar).get() == 0)
        #expect(!context.hasChanges)
    }

    @Test("複製先同士が重なる複数日予定も全件拒否")
    func copiesConflictWithEachOther() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10, endDay: 12)
        context.insert(source)
        try context.save()
        guard case .failure(.incomingOverlap) = store(context).transferPlan(id: source.id, to: [day(20), day(21)], mode: .copy, calendar: calendar) else {
            Issue.record("Expected overlap between copies"); return
        }
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 1)
    }

    @Test("外部連携元の移動と存在しない予定を拒否")
    func missingAndExternal() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        source.sourceEventID = "external"
        context.insert(source)
        try context.save()
        let store = store(context)
        guard case .failure(.externalPlan) = store.transferPlan(id: source.id, to: [day(20)], mode: .move),
              case .failure(.missingPlan) = store.transferPlan(id: UUID(), to: [day(20)], mode: .copy) else {
            Issue.record("Expected rejection"); return
        }
    }

    @Test("日付選択は複製で複数・移動で一つ、キャンセルでクリア")
    func selection() {
        let interaction = CalendarMonthTransferInteraction()
        let source = plan(10)
        interaction.begin(source, mode: .copy)
        interaction.select(day(12)); interaction.select(day(13))
        #expect(interaction.selectedDates.count == 2)
        interaction.select(day(12))
        #expect(interaction.selectedDates.count == 1)
        interaction.begin(source, mode: .move)
        interaction.select(day(12)); interaction.select(day(13))
        #expect(interaction.selectedDates.count == 1)
        interaction.cancel()
        #expect(interaction.request == nil && interaction.selectedDates.isEmpty)
    }

    @Test("ドロップ先は左右の列で判定し、枠外は受け取らない")
    func dropColumns() {
        let dates = (10...16).map { day($0) }
        let viewport = CGRect(x: 100, y: 200, width: 350, height: 200)
        let frames = dates.enumerated().map { ($0.element, CGRect(x: 100 + $0.offset * 50, y: 200, width: 50, height: 100)) }
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 101, y: 250), viewport: viewport, frames: frames) == dates[0])
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 275, y: 250), viewport: viewport, frames: frames) == dates[3])
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 449, y: 250), viewport: viewport, frames: frames) == dates[6])
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 99, y: 250), viewport: viewport, frames: frames) == nil)
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 275, y: 150), viewport: viewport, frames: frames) == nil)
        #expect(CalendarMonthTransferInteraction.dropDate(at: CGPoint(x: 275, y: 350), viewport: viewport, frames: frames) == nil)
    }
}

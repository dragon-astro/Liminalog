import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("CalendarPlanTransferReplacement")
struct CalendarPlanTransferReplacementTests {
    private let calendar = Calendar.current
    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    private func plan(_ day: Int, _ start: Int = 10, _ end: Int = 11) -> PlanBlock {
        PlanBlock(category: nil, title: "予定\(day)", startTime: date(day, start), endTime: date(day, end), note: "メモ")
    }
    private func store(_ context: ModelContext) -> PlanStore {
        PlanStore(modelContext: context, clock: MutableTestClock(now: date(4)), requestRefresh: { _, _, _ in })
    }

    @Test("未承認では変更しない・承認後に前後を残して複製")
    func partialReplacement() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        let existing = plan(20, 9, 12)
        existing.audienceFriendIDs = [UUID()]
        existing.hasAudienceSnapshot = true
        existing.isPublic = false
        context.insert(source); context.insert(existing); try context.save()
        let store = store(context)
        let preview = try store.transferPreview(id: source.id, to: [date(20)], mode: .copy).get()
        #expect(preview.replacement.changes.count == 1)
        #expect(!context.hasChanges)
        guard case .failure(.overlap) = store.transferPlan(id: source.id, to: [date(20)], mode: .copy) else {
            Issue.record("Approval must be required"); return
        }
        #expect(existing.endTime == date(20, 12))
        #expect(try store.transferPlan(id: source.id, to: [date(20)], mode: .copy, approvedReplacement: preview).get() == 1)
        let plans = try ModelContext(container).fetch(FetchDescriptor<PlanBlock>())
        #expect(plans.count == 4)
        #expect(existing.startTime == date(20, 9) && existing.endTime == date(20, 10))
        let remainder = try #require(plans.first { $0.startTime == date(20, 11) })
        #expect(remainder.endTime == date(20, 12) && remainder.note == existing.note)
        #expect(remainder.audienceFriendIDs == existing.audienceFriendIDs && remainder.hasAudienceSnapshot && !remainder.isPublic)
        #expect(source.startTime == date(10, 10))
    }

    @Test("完全に覆う予定を置換して移動・元IDを維持")
    func wholeCoverageMove() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10, 9, 12)
        let existing = plan(20)
        let sourceID = source.id
        context.insert(source); context.insert(existing); try context.save()
        let store = store(context)
        let preview = try store.transferPreview(id: sourceID, to: [date(20)], mode: .move).get()
        #expect(preview.replacement.changes[0].remaining.isEmpty)
        #expect(try store.transferPlan(id: sourceID, to: [date(20)], mode: .move, approvedReplacement: preview).get() == 1)
        let plans = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(plans.count == 1 && plans[0].id == sourceID && plans[0].startTime == date(20, 9))
    }

    @Test("複数日への部分置換を一度に保存")
    func batchReplacement() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        context.insert(source); context.insert(plan(20, 9, 12)); context.insert(plan(21, 9, 12))
        try context.save()
        let store = store(context)
        let preview = try store.transferPreview(id: source.id, to: [date(20), date(21)], mode: .copy).get()
        #expect(preview.replacement.changes.count == 2)
        #expect(try store.transferPlan(id: source.id, to: preview.dates, mode: .copy, approvedReplacement: preview).get() == 2)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 7)
    }

    @Test("承認後の対象・元予定・日付の変化は再承認が必要")
    func staleApproval() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        let existing = plan(20, 9, 12)
        context.insert(source); context.insert(existing); try context.save()
        let store = store(context)
        let preview = try store.transferPreview(id: source.id, to: [date(20)], mode: .copy).get()
        existing.title = "変更後"
        existing.updatedAt = existing.updatedAt.addingTimeInterval(1)
        try context.save()
        guard case .failure(.changed) = store.transferPlan(id: source.id, to: [date(20)], mode: .copy, approvedReplacement: preview) else {
            Issue.record("Stale target approved"); return
        }
        let second = try store.transferPreview(id: source.id, to: [date(20)], mode: .copy).get()
        source.updatedAt = source.updatedAt.addingTimeInterval(1)
        try context.save()
        guard case .failure(.changed) = store.transferPlan(id: source.id, to: [date(20)], mode: .copy, approvedReplacement: second),
              case .failure(.changed) = store.transferPlan(id: source.id, to: [date(21)], mode: .copy, approvedReplacement: second) else {
            Issue.record("Stale source or changed dates approved"); return
        }
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(existing.endTime == date(20, 12) && !context.hasChanges)
    }

    @Test("承認後に新しい重複が追加されても勝手に置換しない")
    func newConflictAfterApproval() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        context.insert(source); context.insert(plan(20)); try context.save()
        let store = store(context)
        let preview = try store.transferPreview(id: source.id, to: [date(20), date(21)], mode: .copy).get()
        context.insert(plan(21)); try context.save()
        guard case .failure(.changed) = store.transferPlan(id: source.id, to: preview.dates, mode: .copy, approvedReplacement: preview) else {
            Issue.record("New conflict was implicitly approved"); return
        }
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 3)
    }

    @Test("表示用警告は置換可能・空き・過去・連携・複製元を区別")
    func warningsAndProtection() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let source = plan(10)
        let external = plan(22)
        external.sourceEventID = "external"
        context.insert(source); context.insert(plan(20)); context.insert(external); try context.save()
        let statuses = store(context).transferDayStatuses(id: source.id, dates: [date(4), date(10), date(20), date(21), date(22)], mode: .copy)
        #expect(statuses[date(20, 0)] == .replacement(1))
        #expect(statuses[date(21, 0)] == .available)
        for day in [4, 10, 22] {
            guard case .blocked = statuses[date(day, 0)] else { Issue.record("Expected blocked day \(day)"); continue }
        }
        guard case .failure(.protectedOverlap) = store(context).transferPreview(id: source.id, to: [date(22)], mode: .move) else {
            Issue.record("External event was not protected"); return
        }
        #expect(!context.hasChanges)
    }

    @Test("ドラッグ取消は確定を発火せず状態を片付ける")
    func dragCancellation() {
        let interaction = CalendarMonthTransferInteraction()
        interaction.begin(plan(10), mode: .move, dragging: true)
        #expect(interaction.isDragging && interaction.request != nil)
        interaction.finishDrag(at: nil)
        #expect(!interaction.isDragging && interaction.action == .cancel && interaction.selectedDates.isEmpty)
        interaction.cancel()
        #expect(interaction.request == nil && interaction.action == nil && interaction.dragLocation == nil)
    }
}

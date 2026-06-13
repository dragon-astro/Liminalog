import Foundation
import SwiftData

@MainActor
final class PlanStore {
    private let modelContext: ModelContext
    private let clock: any LiminalogClock

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        self.modelContext = modelContext
        self.clock = clock
    }

    func isScheduleLocked(_ plan: PlanBlock, now: Date? = nil) -> Bool {
        let reference = now ?? clock.now
        return !plan.isAllDay && DayBoundary.dayStart(for: plan.startTime) <= DayBoundary.dayStart(for: reference)
    }

    func canCreate(startTime: Date, isAllDay: Bool = false, now: Date? = nil) -> Bool {
        if isAllDay {
            return true
        }
        let reference = now ?? clock.now
        return DayBoundary.dayStart(for: startTime) > DayBoundary.dayStart(for: reference)
    }

    func canCreate(
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        excluding planID: UUID? = nil,
        now: Date? = nil
    ) -> Bool {
        guard canCreate(startTime: startTime, isAllDay: isAllDay, now: now) else { return false }
        guard !isAllDay else { return true }
        guard endTime > startTime else { return false }
        return !hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: planID)
    }

    func hasTimedPlanOverlap(startTime: Date, endTime: Date, excluding planID: UUID? = nil) -> Bool {
        timedPlanOverlapIfAvailable(startTime: startTime, endTime: endTime, excluding: planID) ?? true
    }

    private func timedPlanOverlapIfAvailable(startTime: Date, endTime: Date, excluding planID: UUID? = nil) -> Bool? {
        guard startTime < endTime else { return false }
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { !$0.isAllDay && $0.startTime < endTime },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let candidates: [PlanBlock]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch plans for overlap validation: \(String(describing: error))")
            return nil
        }
        return candidates.contains { plan in
            guard plan.id != planID else { return false }
            return plan.endTime > startTime
        }
    }

    func plannedBlocks(on date: Date) -> [PlanBlock] {
        plannedBlocksIfAvailable(on: date) ?? []
    }

    func plannedBlocksIfAvailable(on date: Date) -> [PlanBlock]? {
        let boundary = DayBoundary(date: date)
        return plannedBlocksIfAvailable(from: boundary.dayStart, to: boundary.dayEnd)
    }

    func plannedBlocks(from start: Date, to end: Date) -> [PlanBlock] {
        plannedBlocksIfAvailable(from: start, to: end) ?? []
    }

    func plannedBlocksIfAvailable(from start: Date, to end: Date) -> [PlanBlock]? {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch planned blocks: \(String(describing: error))")
            return nil
        }
    }

    func allPlannedBlocks() -> [PlanBlock] {
        allPlannedBlocksIfAvailable() ?? []
    }

    func allPlannedBlocksIfAvailable() -> [PlanBlock]? {
        let descriptor = FetchDescriptor<PlanBlock>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch all planned blocks: \(String(describing: error))")
            return nil
        }
    }

    @discardableResult
    func addPlanBlock(
        category: Category?,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        audienceFriendIDs: [UUID] = [],
        audienceSource: AudienceSource = .categoryDefaultSnapshot,
        hasAudienceSnapshot: Bool = false
    ) -> Bool {
        guard canCreate(startTime: startTime, endTime: endTime, isAllDay: isAllDay) else { return false }
        let plan = PlanBlock(
            category: category,
            title: normalizedTitle(title, category: category),
            startTime: startTime,
            endTime: max(endTime, startTime.addingTimeInterval(60)),
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            isPublic: isPublic
        )
        plan.audienceFriendIDs = audienceFriendIDs
        plan.audienceSource = audienceSource
        plan.hasAudienceSnapshot = hasAudienceSnapshot
        plan.updatedAt = clock.now
        modelContext.insert(plan)
        return saveChanges(
            "plan add",
            changedPlanSourceID: plan.id,
            changedScoreDayStarts: affectedScoreDayStarts(start: plan.startTime, end: plan.endTime)
        )
    }

    @discardableResult
    func savePlanBlock(
        _ plan: PlanBlock,
        category: Category?,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        isImportant: Bool,
        note: String?,
        isPublic: Bool,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource? = nil,
        hasAudienceSnapshot: Bool? = nil
    ) -> Bool {
        var changedScoreDayStarts = affectedScoreDayStarts(start: plan.startTime, end: plan.endTime)
        if isScheduleLocked(plan) {
            plan.isImportant = isImportant
        } else {
            guard canCreate(startTime: startTime, endTime: endTime, isAllDay: isAllDay, excluding: plan.id) else { return false }
            plan.category = category
            plan.title = normalizedTitle(title, category: category)
            plan.startTime = startTime
            plan.endTime = max(endTime, startTime.addingTimeInterval(60))
            plan.isAllDay = isAllDay
            plan.isImportant = isImportant
            changedScoreDayStarts.formUnion(affectedScoreDayStarts(start: startTime, end: max(endTime, startTime.addingTimeInterval(60))))
        }
        plan.note = note.flatMap { $0.isEmpty ? nil : $0 }
        plan.isPublic = isPublic
        if let audienceFriendIDs {
            plan.audienceFriendIDs = audienceFriendIDs
        }
        if let audienceSource {
            plan.audienceSource = audienceSource
        }
        if let hasAudienceSnapshot {
            plan.hasAudienceSnapshot = hasAudienceSnapshot
        }
        plan.updatedAt = clock.now
        return saveChanges(
            "plan update",
            changedPlanSourceID: plan.id,
            changedScoreDayStarts: changedScoreDayStarts
        )
    }

    @discardableResult
    func deletePlanBlock(_ plan: PlanBlock) -> Bool {
        guard !isScheduleLocked(plan) else { return false }
        let sourceID = plan.id
        let changedScoreDayStarts = affectedScoreDayStarts(start: plan.startTime, end: plan.endTime)
        modelContext.delete(plan)
        return saveChanges(
            "plan delete",
            changedPlanSourceID: sourceID,
            changedScoreDayStarts: changedScoreDayStarts
        )
    }

    private func normalizedTitle(_ title: String, category: Category?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (category?.name ?? "予定") : trimmed
    }

    private func saveChanges(
        _ action: String,
        changedPlanSourceID: UUID,
        changedScoreDayStarts: Set<Date>
    ) -> Bool {
        do {
            try modelContext.save()
            CloudFriendShareRefreshCoordinator.requestRefresh(
                reason: action,
                changedPlanSourceIDs: [changedPlanSourceID],
                changedScoreDayStarts: changedScoreDayStarts,
                requiresFullPublish: false
            )
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }

    private func affectedScoreDayStarts(start: Date, end: Date) -> Set<Date> {
        var result: Set<Date> = []
        let calendar = Calendar.japanese
        var cursor = calendar.startOfDay(for: start)
        let endReference = end > start ? end.addingTimeInterval(-0.001) : start
        let last = calendar.startOfDay(for: endReference)
        while cursor <= last {
            result.insert(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

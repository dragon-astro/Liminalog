import Foundation
import SwiftData

@MainActor
final class PlanStore {
    struct TemplateApplication {
        let snapshot: PlanTemplateSnapshot
        let resolvedCategory: Category?
    }

    struct ScheduleChange {
        let plan: PlanBlock
        let startTime: Date
        let endTime: Date
    }

    private let modelContext: ModelContext
    private let clock: any LiminalogClock
    private let requestRefresh: @MainActor (
        _ reason: String,
        _ changedPlanSourceIDs: Set<UUID>,
        _ changedScoreDayStarts: Set<Date>
    ) -> Void

    init(
        modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock(),
        requestRefresh: @escaping @MainActor (
            _ reason: String,
            _ changedPlanSourceIDs: Set<UUID>,
            _ changedScoreDayStarts: Set<Date>
        ) -> Void = { reason, changedPlanSourceIDs, changedScoreDayStarts in
            CloudFriendShareRefreshCoordinator.requestRefresh(
                reason: reason,
                changedPlanSourceIDs: changedPlanSourceIDs,
                changedScoreDayStarts: changedScoreDayStarts,
                requiresFullPublish: false
            )
        }
    ) {
        self.modelContext = modelContext
        self.clock = clock
        self.requestRefresh = requestRefresh
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
    func applyTemplates(
        _ applications: [TemplateApplication],
        to targetDate: Date,
        calendar: Calendar = .current,
        approvedReplacement: PlanTemplateReplacement? = nil
    ) -> Bool {
        guard !applications.isEmpty else { return false }
        let snapshots = applications.map(\.snapshot)
        let targetBoundary = DayBoundary(date: targetDate, calendar: calendar)
        guard let fetchEnd = calendar.date(
            byAdding: .day,
            value: 2,
            to: targetBoundary.dayStart
        ),
        let existingPlans = plannedBlocksIfAvailable(
            from: targetBoundary.dayStart,
            to: fetchEnd
        ) else { return false }

        let existing = existingPlans.map {
            DayPresetApplyPlanner.ExistingInterval(
                id: $0.id,
                start: $0.startTime,
                end: $0.endTime,
                isAllDay: $0.isAllDay
            )
        }
        let verdicts = DayPresetApplyPlanner.plan(
            items: snapshots,
            targetDate: targetDate,
            existing: existing,
            now: clock.now,
            calendar: calendar
        )
        guard verdicts.allSatisfy({ verdict in
            if verdict == .insertable { return true }
            if case .conflictsWithExisting = verdict { return approvedReplacement != nil }
            return false
        }) else { return false }

        var replacement: PlanTemplateReplacement?
        if let approvedReplacement {
            guard let current = replacementPreview(applications, to: targetDate, calendar: calendar,
                                                   mode: approvedReplacement.mode, existingPlans: existingPlans),
                  current == approvedReplacement else { return false }
            replacement = current
        }

        let audienceContext = fetchAudienceContext()
        guard audienceContext.didFetch else { return false }

        var insertedPlans: [PlanBlock] = []
        var changedScoreDayStarts: Set<Date> = []
        var replacedIDs: Set<UUID> = []
        for change in replacement?.changes ?? [] {
            guard let original = existingPlans.first(where: { $0.id == change.id }) else { return false }
            replacedIDs.insert(original.id)
            changedScoreDayStarts.formUnion(affectedScoreDayStarts(start: original.startTime, end: original.endTime))
            // Keep the first remainder's identity. Extra pieces retain all user metadata.
            for part in change.remaining.dropFirst() {
                let copy = PlanBlock(category: original.category, title: original.title,
                                     startTime: part.start, endTime: part.end,
                                     isAllDay: original.isAllDay, isImportant: original.isImportant,
                                     note: original.note, isPublic: original.isPublic)
                copy.visibilityScope = original.visibilityScope
                copy.audienceFriendIDs = original.audienceFriendIDs
                copy.audienceSourceRawValue = original.audienceSourceRawValue
                copy.hasAudienceSnapshot = original.hasAudienceSnapshot
                copy.sourceEventID = original.sourceEventID
                copy.createdAt = original.createdAt
                copy.updatedAt = clock.now
                modelContext.insert(copy)
                replacedIDs.insert(copy.id)
            }
            if let first = change.remaining.first {
                original.startTime = first.start
                original.endTime = first.end
                original.updatedAt = clock.now
            } else {
                modelContext.delete(original)
            }
        }
        for application in applications {
            guard let interval = application.snapshot.interval(
                on: targetDate,
                calendar: calendar
            ) else {
                modelContext.rollback()
                return false
            }
            let snapshot = application.snapshot
            let audienceFriendIDs = AudienceResolver.categoryDefaultAudience(
                for: application.resolvedCategory,
                friendSets: audienceContext.friendSets,
                friends: audienceContext.friends
            )
            let audienceSource = AudienceSource.categoryDefaultSnapshot
            let plan = PlanBlock(
                category: application.resolvedCategory,
                title: normalizedTitle(snapshot.title, category: application.resolvedCategory),
                startTime: interval.start,
                endTime: interval.end,
                isAllDay: snapshot.isAllDay,
                isImportant: snapshot.isImportant,
                note: snapshot.note.flatMap { $0.isEmpty ? nil : $0 },
                isPublic: snapshot.isPublic
            )
            plan.audienceFriendIDs = audienceFriendIDs
            plan.audienceSource = audienceSource
            plan.hasAudienceSnapshot = AudienceSnapshotPolicy.shouldSaveSnapshot(
                isPublic: snapshot.isPublic,
                audienceSource: audienceSource,
                audienceFriendIDs: audienceFriendIDs
            )
            plan.updatedAt = clock.now
            modelContext.insert(plan)
            insertedPlans.append(plan)
            changedScoreDayStarts.formUnion(
                affectedScoreDayStarts(start: interval.start, end: interval.end)
            )
        }

        return saveChanges(
            "plan template batch add",
            changedPlanSourceIDs: Set(insertedPlans.map(\.id)).union(replacedIDs),
            changedScoreDayStarts: changedScoreDayStarts
        )
    }

    func templateReplacementPreview(
        _ applications: [TemplateApplication], to targetDate: Date,
        mode: PlanTemplateReplacementMode, calendar: Calendar = .current
    ) -> PlanTemplateReplacement? {
        let start = DayBoundary.dayStart(for: targetDate, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 2, to: start),
              let plans = plannedBlocksIfAvailable(from: start, to: end) else { return nil }
        return replacementPreview(applications, to: targetDate, calendar: calendar, mode: mode, existingPlans: plans)
    }

    private func replacementPreview(
        _ applications: [TemplateApplication], to targetDate: Date, calendar: Calendar,
        mode: PlanTemplateReplacementMode, existingPlans: [PlanBlock]
    ) -> PlanTemplateReplacement? {
        guard !applications.isEmpty else { return nil }
        let snapshots = applications.map(\.snapshot)
        let verdicts = DayPresetApplyPlanner.plan(items: snapshots, targetDate: targetDate,
            existing: existingPlans.map { .init(id: $0.id, start: $0.startTime, end: $0.endTime, isAllDay: $0.isAllDay) },
            now: clock.now, calendar: calendar)
        guard verdicts.allSatisfy({ verdict in
            if verdict == .insertable { return true }
            if case .conflictsWithExisting = verdict { return true }
            return false
        }) else { return nil }
        let incoming = snapshots.filter { !$0.isAllDay }.compactMap { $0.interval(on: targetDate, calendar: calendar) }
        var changes: [PlanTemplateReplacement.Change] = []
        for plan in existingPlans where !plan.isAllDay {
            let original = DateInterval(start: plan.startTime, end: max(plan.startTime, plan.endTime))
            let parts = PlanTemplateReplacement.remainingParts(of: original, excluding: incoming)
            guard parts != [original] else { continue }
            // Do not mutate historical plans or externally owned calendar events.
            guard DayBoundary.dayStart(for: plan.startTime, calendar: calendar)
                    > DayBoundary.dayStart(for: clock.now, calendar: calendar),
                  plan.sourceEventID == nil else { return nil }
            changes.append(.init(id: plan.id, title: plan.title, updatedAt: plan.updatedAt, original: original,
                                 remaining: mode == .keepRemainders ? parts : []))
        }
        return PlanTemplateReplacement(mode: mode, changes: changes.sorted {
            if $0.original.start != $1.original.start { return $0.original.start < $1.original.start }
            return $0.id.uuidString < $1.id.uuidString
        })
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
        createPlanBlock(
            category: category,
            title: title,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note,
            isPublic: isPublic,
            audienceFriendIDs: audienceFriendIDs,
            audienceSource: audienceSource,
            hasAudienceSnapshot: hasAudienceSnapshot
        ) != nil
    }

    @discardableResult
    func createPlanBlock(
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
    ) -> PlanBlock? {
        guard canCreate(startTime: startTime, endTime: endTime, isAllDay: isAllDay) else { return nil }
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
        ) ? plan : nil
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
    func savePlanScheduleChanges(_ changes: [ScheduleChange]) -> Bool {
        let meaningfulChanges = changes.filter {
            $0.plan.startTime != $0.startTime || $0.plan.endTime != $0.endTime
        }
        guard !meaningfulChanges.isEmpty else { return true }

        var changedPlanSourceIDs: Set<UUID> = []
        var changedScoreDayStarts: Set<Date> = []
        for change in meaningfulChanges {
            guard !change.plan.isAllDay,
                  !isScheduleLocked(change.plan),
                  canCreate(startTime: change.startTime, isAllDay: false),
                  change.startTime < change.endTime
            else {
                return false
            }
            changedPlanSourceIDs.insert(change.plan.id)
            changedScoreDayStarts.formUnion(affectedScoreDayStarts(start: change.plan.startTime, end: change.plan.endTime))
            changedScoreDayStarts.formUnion(affectedScoreDayStarts(start: change.startTime, end: change.endTime))
        }

        guard canApplyScheduleChanges(meaningfulChanges) else { return false }

        for change in meaningfulChanges {
            change.plan.startTime = change.startTime
            change.plan.endTime = max(change.endTime, change.startTime.addingTimeInterval(60))
            change.plan.updatedAt = clock.now
        }

        return saveChanges(
            "plan schedule batch update",
            changedPlanSourceIDs: changedPlanSourceIDs,
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
        saveChanges(
            action,
            changedPlanSourceIDs: [changedPlanSourceID],
            changedScoreDayStarts: changedScoreDayStarts
        )
    }

    private func saveChanges(
        _ action: String,
        changedPlanSourceIDs: Set<UUID>,
        changedScoreDayStarts: Set<Date>
    ) -> Bool {
        do {
            try modelContext.save()
            requestRefresh(action, changedPlanSourceIDs, changedScoreDayStarts)
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }

    private func fetchAudienceContext() -> (
        friendSets: [FriendSet],
        friends: [Friend],
        didFetch: Bool
    ) {
        do {
            let friendSets = try modelContext.fetch(FetchDescriptor<FriendSet>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            let friends = try modelContext.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            return (friendSets, friends, true)
        } catch {
            NSLog("Liminalog: failed to resolve template audiences: \(String(describing: error))")
            return ([], [], false)
        }
    }

    private func canApplyScheduleChanges(_ changes: [ScheduleChange]) -> Bool {
        let changesByID = Dictionary(uniqueKeysWithValues: changes.map { ($0.plan.id, $0) })
        let fetchStart = changes.map(\.startTime).min() ?? clock.now
        let fetchEnd = changes.map(\.endTime).max() ?? clock.now
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { !$0.isAllDay && $0.startTime < fetchEnd && $0.endTime > fetchStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let candidates: [PlanBlock]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch plans for batch schedule validation: \(String(describing: error))")
            return false
        }

        let intervals = candidates.map { plan in
            if let change = changesByID[plan.id] {
                return (id: plan.id, start: change.startTime, end: change.endTime)
            }
            return (id: plan.id, start: plan.startTime, end: plan.endTime)
        }
        .map { (interval: $0, idSortKey: $0.id.uuidString) }
        .sorted { lhs, rhs in
            if lhs.interval.start == rhs.interval.start {
                return lhs.idSortKey < rhs.idSortKey
            }
            return lhs.interval.start < rhs.interval.start
        }
        .map(\.interval)

        guard intervals.allSatisfy({ $0.start < $0.end }) else { return false }
        for pair in zip(intervals, intervals.dropFirst()) {
            if pair.0.end > pair.1.start {
                return false
            }
        }
        return true
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

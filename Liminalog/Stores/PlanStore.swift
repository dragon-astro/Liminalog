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
        return !plan.isAllDay && !plan.isMemo && DayBoundary.dayStart(for: plan.startTime) <= DayBoundary.dayStart(for: reference)
    }

    func canCreate(startTime: Date, isAllDay: Bool = false, isMemo: Bool = false, now: Date? = nil) -> Bool {
        if isAllDay || isMemo {
            return true
        }
        let reference = now ?? clock.now
        return DayBoundary.dayStart(for: startTime) > DayBoundary.dayStart(for: reference)
    }

    func canCreate(
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isMemo: Bool = false,
        excluding planID: UUID? = nil,
        now: Date? = nil
    ) -> Bool {
        guard canCreate(startTime: startTime, isAllDay: isAllDay, isMemo: isMemo, now: now) else { return false }
        guard !isAllDay else { return true }
        guard endTime > startTime else { return false }
        return isMemo || !hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: planID)
    }

    func hasTimedPlanOverlap(startTime: Date, endTime: Date, excluding planID: UUID? = nil) -> Bool {
        timedPlanOverlapIfAvailable(startTime: startTime, endTime: endTime, excluding: planID) ?? true
    }

    private func timedPlanOverlapIfAvailable(startTime: Date, endTime: Date, excluding planID: UUID? = nil) -> Bool? {
        guard startTime < endTime else { return false }
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate {
                !$0.isAllDay && !$0.isMemo && $0.startTime < endTime && $0.endTime > startTime
            },
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

    /// Preserve the existing 09:00-first, 15-minute search with one bounded fetch.
    func firstAvailableHourStart(on date: Date, calendar: Calendar = .japanese) -> Date? {
        let boundary = DayBoundary(date: date, calendar: calendar)
        let preferred = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? boundary.dayStart
        let latestStart = calendar.date(byAdding: .hour, value: -1, to: boundary.dayEnd) ?? preferred
        guard let plans = plannedBlocksIfAvailable(from: preferred, to: boundary.dayEnd) else { return nil }
        let timedPlans = plans.filter { !$0.isAllDay && !$0.isMemo }
        var candidate = preferred
        while candidate <= latestStart {
            let end = calendar.date(byAdding: .hour, value: 1, to: candidate) ?? candidate
            if !timedPlans.contains(where: { $0.startTime < end && $0.endTime > candidate }) {
                return candidate
            }
            guard let next = calendar.date(byAdding: .minute, value: 15, to: candidate), next > candidate else { break }
            candidate = next
        }
        return nil
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
                isAllDay: $0.isAllDay, isMemo: $0.isMemo
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
        guard let replaced = applyReplacement(replacement, existingPlans: existingPlans) else { return false }
        var changedScoreDayStarts = replaced.days
        let replacedIDs = replaced.ids
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
                isAllDay: snapshot.isAllDay, isMemo: snapshot.isMemo,
                isImportant: snapshot.isImportant,
                note: snapshot.note.flatMap { $0.isEmpty ? nil : $0 },
                isPublic: snapshot.isPublic
            )
            plan.reminderMinutesBefore = snapshot.reminderMinutesBefore
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
            existing: existingPlans.map { .init(id: $0.id, start: $0.startTime, end: $0.endTime, isAllDay: $0.isAllDay, isMemo: $0.isMemo) },
            now: clock.now, calendar: calendar)
        guard verdicts.allSatisfy({ verdict in
            if verdict == .insertable { return true }
            if case .conflictsWithExisting = verdict { return true }
            return false
        }) else { return nil }
        let incoming = snapshots.filter { !$0.isAllDay && !$0.isMemo }.compactMap { $0.interval(on: targetDate, calendar: calendar) }
        var changes: [PlanTemplateReplacement.Change] = []
        for plan in existingPlans where !plan.isAllDay && !plan.isMemo {
            let original = DateInterval(start: plan.startTime, end: max(plan.startTime, plan.endTime))
            let parts = PlanTemplateReplacement.remainingParts(of: original, excluding: incoming)
            guard parts != [original] else { continue }
            // Do not mutate historical plans or externally owned calendar events.
            guard DayBoundary.dayStart(for: plan.startTime, calendar: calendar)
                    > DayBoundary.dayStart(for: clock.now, calendar: calendar),
                  !plan.hasExternalCalendarSource else { return nil }
            changes.append(.init(id: plan.id, title: plan.title, updatedAt: plan.updatedAt, original: original,
                                 remaining: mode == .keepRemainders ? parts : [],
                                 categoryName: plan.category?.name, colorHex: plan.category?.colorHex,
                                 icon: plan.category?.icon))
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
        isMemo: Bool = false,
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
            isMemo: isMemo,
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
        isMemo: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        audienceFriendIDs: [UUID] = [],
        audienceSource: AudienceSource = .categoryDefaultSnapshot,
        hasAudienceSnapshot: Bool = false,
        beforeSave: ((PlanBlock) -> Bool)? = nil
    ) -> PlanBlock? {
        guard canCreate(startTime: startTime, endTime: endTime, isAllDay: isAllDay, isMemo: isMemo) else { return nil }
        let plan = PlanBlock(
            category: category,
            title: normalizedTitle(title, category: category),
            startTime: startTime,
            endTime: max(endTime, startTime.addingTimeInterval(60)),
            isAllDay: isAllDay,
            isMemo: isMemo,
            isImportant: isImportant,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            isPublic: isPublic
        )
        plan.audienceFriendIDs = audienceFriendIDs
        plan.audienceSource = audienceSource
        plan.hasAudienceSnapshot = hasAudienceSnapshot
        plan.updatedAt = clock.now
        modelContext.insert(plan)
        guard beforeSave?(plan) ?? true else { modelContext.rollback(); return nil }
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
        isMemo: Bool? = nil,
        isImportant: Bool,
        note: String?,
        isPublic: Bool,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource? = nil,
        hasAudienceSnapshot: Bool? = nil,
        approvedPromotion: [PlanMemoPromotionChange]? = nil,
        promotionMode: PlanMemoPromotionMode = .keepRemainders,
        beforeSave: ((PlanBlock) -> Bool)? = nil
    ) -> Bool {
        let resolvedMemo = isMemo ?? plan.isMemo
        var changedIDs: Set<UUID> = [plan.id]
        var promotions: [PlanBlock] = []
        if plan.isMemo && !resolvedMemo && !isAllDay {
            guard let current = memoPromotionPreview(start: startTime, end: endTime, excluding: plan.id),
                  approvedPromotion.map({ $0 == current }) ?? current.isEmpty else { return false }
            guard let all = plannedBlocksIfAvailable(from: startTime, to: endTime) else { return false }
            promotions = all.filter { current.map(\.id).contains($0.id) }
        }
        var changedScoreDayStarts = affectedScoreDayStarts(start: plan.startTime, end: plan.endTime)
        if isScheduleLocked(plan) {
            guard resolvedMemo == plan.isMemo else { return false }
            plan.isImportant = isImportant
        } else {
            guard canCreate(startTime: startTime, isAllDay: isAllDay, isMemo: resolvedMemo),
                  endTime > startTime,
                  resolvedMemo || isAllDay || !promotions.isEmpty
                    || !hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: plan.id)
            else { return false }
            let replacement = promotionMode.replacement(changes: promotions.map(PlanMemoPromotionChange.init),
                start: startTime, end: endTime)
            guard let result = applyReplacement(replacement, existingPlans: promotions) else { return false }
            changedIDs.formUnion(result.ids)
            changedScoreDayStarts.formUnion(result.days)
            plan.isMemo = resolvedMemo
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
        guard beforeSave?(plan) ?? true else { modelContext.rollback(); return false }
        return saveChanges(
            "plan update",
            changedPlanSourceIDs: changedIDs,
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
                  canCreate(startTime: change.startTime, isAllDay: false, isMemo: change.plan.isMemo),
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

    /// Shared by preset application and calendar transfers. Validate every target before touching any model.
    private func applyReplacement(_ replacement: PlanTemplateReplacement?, existingPlans: [PlanBlock]) -> (ids: Set<UUID>, days: Set<Date>)? {
        let changes = replacement?.changes ?? []
        let originals = changes.compactMap { change in existingPlans.first { $0.id == change.id } }
        guard originals.count == changes.count else { return nil }
        var ids: Set<UUID> = []
        var days: Set<Date> = []
        for (change, original) in zip(changes, originals) {
            ids.insert(original.id)
            days.formUnion(affectedScoreDayStarts(start: original.startTime, end: original.endTime))
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
                ids.insert(copy.id)
            }
            if let first = change.remaining.first {
                original.startTime = first.start
                original.endTime = first.end
                original.updatedAt = clock.now
            } else { modelContext.delete(original) }
        }
        return (ids, days)
    }

    private func transferSource(id: UUID) -> Result<PlanBlock, CalendarPlanTransferError> {
        do {
            let descriptor = FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.id == id })
            guard let plan = try modelContext.fetch(descriptor).first else { return .failure(.missingPlan) }
            return .success(plan)
        } catch { return .failure(.persistence) }
    }

    private func transferExistingPlans(source: PlanBlock, dates: Set<Date>, calendar: Calendar) -> [PlanBlock]? {
        let intervals = dates.compactMap { CalendarPlanTransfer.interval(start: source.startTime, end: source.endTime, to: $0, calendar: calendar) }
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max() else { return [] }
        return plannedBlocksIfAvailable(from: start, to: end)
    }

    func transferPreview(id: UUID, to dates: Set<Date>, mode: CalendarPlanTransferMode,
                         calendar: Calendar = .current) -> Result<CalendarPlanTransferPreview, CalendarPlanTransferError> {
        transferSource(id: id).flatMap { source in
            guard let existing = transferExistingPlans(source: source, dates: dates, calendar: calendar) else { return .failure(.persistence) }
            return makeTransferPreview(source: source, dates: dates, mode: mode, existing: existing, calendar: calendar)
        }
    }

    /// One source fetch and one bounded range fetch for all visible dates, never a query on every drag frame.
    func transferDayStatuses(id: UUID, dates: Set<Date>, mode: CalendarPlanTransferMode,
                             calendar: Calendar = .current) -> [Date: CalendarPlanTransferDayStatus] {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let source: PlanBlock
        switch transferSource(id: id) {
        case .success(let plan): source = plan
        case .failure(let error): return Dictionary(uniqueKeysWithValues: days.map { ($0, .blocked(error.localizedDescription)) })
        }
        guard let existing = transferExistingPlans(source: source, dates: days, calendar: calendar) else {
            return Dictionary(uniqueKeysWithValues: days.map { ($0, .blocked(CalendarPlanTransferError.persistence.localizedDescription)) })
        }
        return Dictionary(uniqueKeysWithValues: days.map { day in
            let status: CalendarPlanTransferDayStatus
            switch makeTransferPreview(source: source, dates: [day], mode: mode, existing: existing, calendar: calendar) {
            case .success(let preview): status = preview.replacement.changes.isEmpty ? .available : .replacement(preview.replacement.changes.count)
            case .failure(let error): status = .blocked(error.localizedDescription)
            }
            return (day, status)
        })
    }

    private func makeTransferPreview(source: PlanBlock, dates: Set<Date>, mode: CalendarPlanTransferMode,
                                     existing: [PlanBlock], calendar: Calendar) -> Result<CalendarPlanTransferPreview, CalendarPlanTransferError> {
        if mode == .move {
            guard !isScheduleLocked(source) else { return .failure(.locked) }
            guard !source.hasExternalCalendarSource else { return .failure(.externalPlan) }
        }
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty, mode == .copy || days.count == 1 else { return .failure(.noDates) }
        var intervals: [DateInterval] = []
        for day in days {
            guard let interval = CalendarPlanTransfer.interval(start: source.startTime, end: source.endTime,
                                                               to: day, calendar: calendar) else {
                return .failure(.invalidTime)
            }
            guard canCreate(startTime: interval.start, isAllDay: source.isAllDay, isMemo: source.isMemo) else {
                return .failure(.unavailableDay)
            }
            if !source.isAllDay && !source.isMemo {
                guard !intervals.contains(where: { $0.start < interval.end && $0.end > interval.start }) else {
                    return .failure(.incomingOverlap)
                }
            }
            intervals.append(interval)
        }
        var changes: [PlanTemplateReplacement.Change] = []
        for plan in existing where !source.isAllDay && !source.isMemo && !plan.isAllDay && !plan.isMemo {
            if mode == .move && plan.id == source.id { continue }
            let original = DateInterval(start: plan.startTime, end: max(plan.startTime, plan.endTime))
            let remaining = PlanTemplateReplacement.remainingParts(of: original, excluding: intervals)
            guard remaining != [original] else { continue }
            guard plan.id != source.id else { return .failure(.sourceOverlap) }
            guard !isScheduleLocked(plan), !plan.hasExternalCalendarSource else { return .failure(.protectedOverlap) }
            changes.append(.init(id: plan.id, title: plan.title, updatedAt: plan.updatedAt, original: original, remaining: remaining))
        }
        changes.sort { $0.id.uuidString < $1.id.uuidString }
        return .success(CalendarPlanTransferPreview(sourceID: source.id, sourceUpdatedAt: source.updatedAt,
            sourceTitle: source.title, sourceStart: source.startTime, sourceEnd: source.endTime,
            isAllDay: source.isAllDay, dates: Set(days), mode: mode, intervals: intervals,
            replacement: .init(mode: .keepRemainders, changes: changes)))
    }

    /// Approval covers both the source/ranges and all affected revisions. Save the whole batch once.
    func transferPlan(id: UUID, to dates: Set<Date>, mode: CalendarPlanTransferMode,
                      calendar: Calendar = .current,
                      approvedReplacement: CalendarPlanTransferPreview? = nil) -> Result<Int, CalendarPlanTransferError> {
        let preview: CalendarPlanTransferPreview
        switch transferPreview(id: id, to: dates, mode: mode, calendar: calendar) {
        case .success(let value): preview = value
        case .failure(let error): return .failure(error)
        }
        if let approvedReplacement {
            guard preview == approvedReplacement else { return .failure(.changed) }
        } else if !preview.replacement.changes.isEmpty { return .failure(.overlap) }
        guard case .success(let source) = transferSource(id: id),
              let existing = transferExistingPlans(source: source, dates: dates, calendar: calendar) else { return .failure(.persistence) }
        let intervals = preview.intervals
        if mode == .move, let interval = intervals.first,
           interval.start == source.startTime, interval.end == source.endTime { return .success(0) }
        guard let replaced = applyReplacement(preview.replacement, existingPlans: existing) else { return .failure(.changed) }
        var changedIDs = replaced.ids
        var changedDays = replaced.days
        for interval in intervals {
            let target: PlanBlock
            if mode == .move {
                target = source
                changedDays.formUnion(affectedScoreDayStarts(start: source.startTime, end: source.endTime))
            } else {
                target = PlanBlock(category: source.category, title: source.title,
                                   startTime: interval.start, endTime: interval.end,
                                   isAllDay: source.isAllDay, isMemo: source.isMemo, isImportant: source.isImportant,
                                   note: source.note, isPublic: source.isPublic)
                target.reminderMinutesBefore = source.reminderMinutesBefore
                target.reminderDate = source.reminderDate
                target.visibilityScope = source.visibilityScope
                target.audienceFriendIDs = source.audienceFriendIDs
                target.audienceSourceRawValue = source.audienceSourceRawValue
                target.hasAudienceSnapshot = source.hasAudienceSnapshot
                target.createdAt = clock.now
                // A copy is a new local event, not a second reference to an external event.
                modelContext.insert(target)
            }
            target.startTime = interval.start
            target.endTime = interval.end
            target.updatedAt = clock.now
            changedIDs.insert(target.id)
            changedDays.formUnion(affectedScoreDayStarts(start: interval.start, end: interval.end))
        }
        guard saveChanges("plan \(mode.rawValue)", changedPlanSourceIDs: changedIDs,
                          changedScoreDayStarts: changedDays) else { return .failure(.persistence) }
        return .success(intervals.count)
    }

    func memoPromotionPreview(start: Date, end: Date, excluding id: UUID) -> [PlanMemoPromotionChange]? {
        guard end > start, canCreate(startTime: start),
              let plans = plannedBlocksIfAvailable(from: start, to: end) else { return nil }
        let conflicts = plans.filter { $0.id != id && !$0.isAllDay && !$0.isMemo }
        guard conflicts.allSatisfy({ !isScheduleLocked($0) && !$0.hasExternalCalendarSource }) else { return nil }
        return conflicts.map(PlanMemoPromotionChange.init).sorted { $0.id.uuidString < $1.id.uuidString }
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
            NotificationCenter.default.post(name: .planSchedulingChanged, object: nil)
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
            predicate: #Predicate { !$0.isAllDay && !$0.isMemo && $0.startTime < fetchEnd && $0.endTime > fetchStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let candidates: [PlanBlock]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch plans for batch schedule validation: \(String(describing: error))")
            return false
        }

        let candidateIDs = Set(candidates.map(\.id))
        let mainCandidates = candidates + changes.filter { !$0.plan.isMemo && !candidateIDs.contains($0.plan.id) }.map(\.plan)
        let intervals = mainCandidates.map { plan in
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

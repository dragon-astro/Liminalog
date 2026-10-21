import CryptoKit
import Foundation
import SwiftData

@MainActor
final class PlanRecurrenceStore {
    private let context: ModelContext
    private let clock: any LiminalogClock
    private let calendar: Calendar
    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock(), calendar: Calendar = .current) {
        context = modelContext; self.clock = clock; self.calendar = calendar
    }

    /// Joins the caller's plan-save transaction; never saves independently.
    func register(_ plan: PlanBlock, rule: PlanRecurrenceRule) -> Bool {
        guard plan.recurrenceSeriesID == nil else { return true }
        guard rule.isValid, let snapshot = PlanPresetStore.snapshot(from: plan, calendar: calendar), snapshot.hasValidTime,
              let data = rule.data else { return false }
        let nextOrder = ((try? context.fetch(FetchDescriptor<PlanPreset>())) ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let preset = PlanPreset(name: plan.title, title: plan.title, categoryID: plan.category?.id,
            startMinute: snapshot.startMinute, endMinute: snapshot.endMinute, isAllDay: plan.isAllDay,
            isImportant: plan.isImportant, note: plan.note, isPublic: plan.isPublic, placementMode: .fixedTime)
        preset.sortOrder = nextOrder
        preset.recurrenceData = data
        preset.isMemo = plan.isMemo
        preset.reminderMinutesBefore = snapshot.reminderMinutesBefore
        context.insert(preset)
        plan.recurrenceSeriesID = preset.id
        let occurrence = PlanRecurrenceOccurrence(seriesID: preset.id, itemID: preset.id,
            day: calendar.startOfDay(for: plan.startTime))
        occurrence.planID = plan.id
        // The explicitly saved source remains a personal occurrence, including exact seconds.
        occurrence.baselineData = nil
        context.insert(occurrence)
        return true
    }

    private struct Series {
        let id: UUID
        let rule: PlanRecurrenceRule?
        let items: [PlanTemplateSnapshot]
    }

    /// Returns changed plan IDs. Deleted/customized occurrences are never rebuilt.
    /// A bounded date window is filled on launch and when a calendar range is opened.
    func materialize(from requestedStart: Date? = nil, to requestedEnd: Date? = nil) throws -> Set<UUID> {
        guard !context.hasChanges else { return [] }
        let today = calendar.startOfDay(for: clock.now)
        let start = max(today, calendar.startOfDay(for: requestedStart ?? today))
        let defaultEnd = calendar.date(byAdding: .day, value: 60, to: start)!
        let end = min(requestedEnd ?? defaultEnd, calendar.date(byAdding: .day, value: 100, to: start)!)
        guard start < end else { return [] }
        let planPresets = try context.fetch(FetchDescriptor<PlanPreset>())
        let dayPresets = try context.fetch(FetchDescriptor<DayPreset>())
        let occurrenceCount = try context.fetchCount(FetchDescriptor<PlanRecurrenceOccurrence>())
        guard planPresets.contains(where: { $0.recurrenceData != nil })
                || dayPresets.contains(where: { $0.recurrenceData != nil })
                || occurrenceCount > 0 else { return [] }
        var series: [Series] = []
        for preset in planPresets {
            guard preset.recurrenceData == nil || PlanRecurrenceRule.decode(preset.recurrenceData) != nil else { continue }
            var snapshot = preset.snapshot
            snapshot.templateItemID = preset.id
            series.append(Series(id: preset.id, rule: PlanRecurrenceRule.decode(preset.recurrenceData), items: [snapshot]))
        }
        for preset in dayPresets {
            guard let decoded = try? DayPresetItemsCodec.decode(preset.itemsData),
                  preset.recurrenceData == nil || PlanRecurrenceRule.decode(preset.recurrenceData) != nil else { continue }
            let items = decoded.enumerated().map { index, item in
                var copy = item
                copy.templateItemID = copy.templateItemID ?? Self.stableID("\(preset.id)/item/\(index)")
                return copy
            }
            if preset.recurrenceData != nil && items != decoded { preset.itemsData = try DayPresetItemsCodec.encode(items) }
            series.append(Series(id: preset.id, rule: PlanRecurrenceRule.decode(preset.recurrenceData), items: items))
        }
        let records = try context.fetch(FetchDescriptor<PlanRecurrenceOccurrence>(predicate: #Predicate {
            $0.day >= today
        }))
        let fetchEnd = calendar.date(byAdding: .day, value: 2, to: max(end, records.map(\.day).max() ?? end))!
        var plans = try context.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate {
            $0.startTime < fetchEnd && $0.endTime > today
        }))
        let found = Set(plans.map(\.id))
        let missing = records.compactMap(\.planID).filter { !found.contains($0) }
        if !missing.isEmpty {
            plans += try context.fetch(FetchDescriptor<PlanBlock>(predicate: #Predicate { missing.contains($0.id) }))
        }
        // Freeze interval values once. Re-reading SwiftData properties for every
        // candidate/day turns a two-month fill into quadratic model access.
        var occupied = Dictionary(plans.filter { !$0.isAllDay && !$0.isMemo && $0.endTime > $0.startTime }.map { ($0.id, DateInterval(start: $0.startTime, end: $0.endTime)) },
            uniquingKeysWith: { first, _ in first })
        var planByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var recordByKey = Dictionary(records.map { (key($0.seriesID, $0.itemID, $0.day), $0) }, uniquingKeysWith: { first, second in
            // A synchronized completed occurrence takes precedence over a pending attempt.
            first.planID == nil && second.planID != nil ? second : first
        })
        let categories = try context.fetch(FetchDescriptor<Category>())
        let friends = try context.fetch(FetchDescriptor<Friend>())
        let friendSets = try context.fetch(FetchDescriptor<FriendSet>())
        var changed: Set<UUID> = []
        var changedDays: Set<Date> = []
        // Retired dates/items are removed only if still exactly the generated default.
        // A deleted preset leaves its dated plans in place; disabling its rule is explicit.
        for record in records {
            let seriesID = record.seriesID, itemID = record.itemID
            let occurrenceDay = record.day
            guard let source = series.first(where: { $0.id == seriesID }),
                  !source.items.contains(where: { item in
                      guard item.templateItemID == itemID, let interval = item.interval(on: occurrenceDay, calendar: calendar) else { return false }
                      return source.rule?.allows(startingAt: interval.start, on: occurrenceDay, calendar: calendar) ?? false
                  }),
                  let id = record.planID, let plan = planByID[id],
                  plan.startTime >= today, (plan.isAllDay || plan.isMemo || plan.startTime >= calendar.date(byAdding: .day, value: 1, to: today)!),
                  PlanRecurrenceBaseline(plan).matches(record.baselineData) else { continue }
            context.delete(plan)
            planByID[id] = nil
            occupied[id] = nil
            changed.insert(id)
            changedDays.insert(calendar.startOfDay(for: plan.startTime))
            changedDays.insert(calendar.startOfDay(for: plan.endTime.addingTimeInterval(-1)))
            record.planID = nil; record.baselineData = nil; record.isBlocked = true
        }
        var days = Set(records.map(\.day))
        var nextDay = start
        while nextDay < end {
            days.insert(nextDay)
            nextDay = calendar.date(byAdding: .day, value: 1, to: nextDay)!
        }
        struct Candidate {
            let item: PlanTemplateSnapshot
            let interval: DateInterval
            let recordKey: String
            let record: PlanRecurrenceOccurrence?
            let existing: PlanBlock?
        }
        for source in series.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let rule = source.rule else { continue }
            for day in days.sorted() where rule.contains(day, calendar: calendar) {
                var candidates: [Candidate] = []
                for item in source.items {
                    guard let itemID = item.templateItemID, item.hasValidTime,
                          let interval = item.interval(on: day, calendar: calendar),
                          rule.allows(startingAt: interval.start, on: day, calendar: calendar),
                          item.isAllDay || item.isMemo || day > today else { continue }
                    let recordKey = key(source.id, itemID, day)
                    let record = recordByKey[recordKey]
                    let existing = record?.planID.flatMap { planByID[$0] }
                    if let record, !record.isBlocked {
                        guard let existing, PlanRecurrenceBaseline(existing).matches(record.baselineData) else { continue }
                    }
                    candidates.append(Candidate(item: item, interval: interval, recordKey: recordKey, record: record, existing: existing))
                }
                // Reconcile the complete day's untouched defaults together: shifting adjacent
                // blocks must not collide with their own previous positions.
                let replacingIDs = Set(candidates.compactMap { $0.existing?.id })
                let protectedPlans = occupied.filter { !replacingIDs.contains($0.key) }.map(\.value)
                let hasConflict = candidates.enumerated().contains { index, candidate in
                    guard !candidate.item.isAllDay && !candidate.item.isMemo else { return false }
                    return protectedPlans.contains { $0.start < candidate.interval.end && $0.end > candidate.interval.start }
                        || candidates.prefix(index).contains { !$0.item.isAllDay && !$0.item.isMemo && $0.interval.start < candidate.interval.end && $0.interval.end > candidate.interval.start }
                }
                for candidate in candidates {
                    let item = candidate.item
                    let interval = candidate.interval
                    let existing = candidate.existing
                    let record = candidate.record ?? PlanRecurrenceOccurrence(seriesID: source.id, itemID: item.templateItemID!, day: day)
                    if candidate.record == nil {
                        record.id = Self.stableID(candidate.recordKey + "/record")
                        context.insert(record); recordByKey[candidate.recordKey] = record
                    }
                    if hasConflict {
                        if existing == nil && !record.isBlocked { record.isBlocked = true }
                        continue
                    }
                    let category = categories.first { $0.id == item.categoryID }
                    let title = item.title.isEmpty ? (category?.name ?? "予定") : item.title
                    // Avoid SwiftData writes and saves when repeated foreground refreshes find
                    // the same defaults. The baseline represents exactly the last generated value.
                    if let existing, existing.title == title, existing.category?.id == category?.id,
                       existing.startTime == interval.start, existing.endTime == interval.end,
                       existing.isAllDay == item.isAllDay, existing.isMemo == item.isMemo, existing.isImportant == item.isImportant,
                       existing.note == item.note, existing.isPublic == item.isPublic,
                       existing.reminderMinutesBefore == item.reminderMinutesBefore, existing.reminderDate == nil { continue }
                    let plan = existing ?? PlanBlock(category: category, title: title,
                        startTime: interval.start, endTime: interval.end)
                    if existing != nil { changedDays.insert(calendar.startOfDay(for: plan.startTime)) }
                    plan.title = title; plan.category = category
                    plan.startTime = interval.start; plan.endTime = interval.end
                    plan.isMemo = item.isMemo
                    plan.isAllDay = item.isAllDay; plan.isImportant = item.isImportant
                    plan.note = item.note; plan.isPublic = item.isPublic
                    plan.reminderMinutesBefore = item.reminderMinutesBefore
                    plan.reminderDate = nil
                    plan.recurrenceSeriesID = source.id
                    if existing == nil {
                        plan.id = Self.stableID(candidate.recordKey + "/plan")
                        plan.audienceFriendIDs = AudienceResolver.categoryDefaultAudience(for: category, friendSets: friendSets, friends: friends)
                        plan.audienceSource = .categoryDefaultSnapshot
                        plan.hasAudienceSnapshot = AudienceSnapshotPolicy.shouldSaveSnapshot(isPublic: plan.isPublic,
                            audienceSource: plan.audienceSource, audienceFriendIDs: plan.audienceFriendIDs)
                        context.insert(plan); planByID[plan.id] = plan
                    }
                    occupied[plan.id] = (plan.isAllDay || plan.isMemo) ? nil : interval
                    plan.updatedAt = clock.now; changed.insert(plan.id)
                    changedDays.insert(calendar.startOfDay(for: plan.startTime))
                    changedDays.insert(calendar.startOfDay(for: plan.endTime.addingTimeInterval(-1)))
                    record.planID = plan.id; record.baselineData = PlanRecurrenceBaseline(plan).data; record.isBlocked = false
                }
            }
        }
        if context.hasChanges {
            do { try context.save() } catch { context.rollback(); throw error }
        }
        if !changed.isEmpty {
            CloudFriendShareRefreshCoordinator.requestRefresh(reason: "recurring plans", changedPlanSourceIDs: changed,
                changedScoreDayStarts: changedDays, requiresFullPublish: false)
        }
        return changed
    }

    private func key(_ series: UUID, _ item: UUID, _ day: Date) -> String {
        "\(series)/\(item)/\(DailyCardSnapshot.dayIdentifier(for: day, calendar: calendar))"
    }
    static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

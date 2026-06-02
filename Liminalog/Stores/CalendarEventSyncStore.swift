import Foundation
import SwiftData

struct CalendarEventSnapshot: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let colorHex: String?

    var sourceEventID: String {
        Self.sourceEventID(eventIdentifier: eventIdentifier, calendarIdentifier: calendarIdentifier)
    }

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "予定" : trimmed
    }

    var normalizedEndTime: Date {
        if endTime > startTime {
            return endTime
        }
        let fallbackDuration: TimeInterval = isAllDay ? 24 * 60 * 60 : 60
        return startTime.addingTimeInterval(fallbackDuration)
    }

    var isValid: Bool {
        !eventIdentifier.isEmpty && !calendarIdentifier.isEmpty
    }

    static func sourceEventID(eventIdentifier: String, calendarIdentifier: String) -> String {
        "eventkit:\(calendarIdentifier.count):\(calendarIdentifier)\(eventIdentifier)"
    }

    func overlaps(_ interval: DateInterval) -> Bool {
        startTime < interval.end && normalizedEndTime > interval.start
    }
}

struct CalendarEventSyncResult: Equatable {
    var insertedCaches = 0
    var updatedCaches = 0
    var deletedCaches = 0
    var insertedPlans = 0
    var updatedPlans = 0
    var deletedPlans = 0

    var didChange: Bool {
        insertedCaches > 0 ||
            updatedCaches > 0 ||
            deletedCaches > 0 ||
            insertedPlans > 0 ||
            updatedPlans > 0 ||
            deletedPlans > 0
    }
}

@MainActor
final class CalendarEventSyncStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func sync(
        snapshots: [CalendarEventSnapshot],
        visibleInterval: DateInterval,
        now: Date = Date()
    ) -> CalendarEventSyncResult {
        let incomingSnapshots = snapshots
            .filter { $0.isValid && $0.overlaps(visibleInterval) }
            .reduce(into: [String: CalendarEventSnapshot]()) { partial, snapshot in
                partial[snapshot.sourceEventID] = snapshot
            }

        var result = CalendarEventSyncResult()
        var cacheBySourceID = consolidatedCaches(result: &result)
        var planBySourceID = consolidatedImportedPlans(result: &result)

        for (sourceID, snapshot) in incomingSnapshots {
            if let cache = cacheBySourceID[sourceID] {
                if apply(snapshot, to: cache, now: now) {
                    result.updatedCaches += 1
                }
            } else {
                let cache = makeCache(from: snapshot, now: now)
                modelContext.insert(cache)
                cacheBySourceID[sourceID] = cache
                result.insertedCaches += 1
            }

            if let plan = planBySourceID[sourceID] {
                if apply(snapshot, to: plan, now: now) {
                    result.updatedPlans += 1
                }
            } else {
                let plan = makePlan(from: snapshot, now: now)
                modelContext.insert(plan)
                planBySourceID[sourceID] = plan
                result.insertedPlans += 1
            }
        }

        let incomingSourceIDs = Set(incomingSnapshots.keys)
        for (sourceID, cache) in cacheBySourceID where !incomingSourceIDs.contains(sourceID) && cache.overlaps(visibleInterval) {
            modelContext.delete(cache)
            result.deletedCaches += 1

            if let plan = planBySourceID[sourceID] {
                modelContext.delete(plan)
                result.deletedPlans += 1
            }
        }

        if result.didChange {
            try? modelContext.save()
        }
        return result
    }

    private func consolidatedCaches(result: inout CalendarEventSyncResult) -> [String: CalendarEventCache] {
        let descriptor = FetchDescriptor<CalendarEventCache>(
            sortBy: [SortDescriptor(\.lastSyncedAt)]
        )
        let caches = (try? modelContext.fetch(descriptor)) ?? []
        let groups = Dictionary(grouping: caches) { cache in
            CalendarEventSnapshot.sourceEventID(
                eventIdentifier: cache.eventIdentifier,
                calendarIdentifier: cache.calendarIdentifier
            )
        }

        var cacheBySourceID: [String: CalendarEventCache] = [:]
        for (sourceID, group) in groups {
            guard let primary = group.first else { continue }
            cacheBySourceID[sourceID] = primary
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
                result.deletedCaches += 1
            }
        }
        return cacheBySourceID
    }

    private func consolidatedImportedPlans(result: inout CalendarEventSyncResult) -> [String: PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let plans = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.sourceEventID != nil }
        let groups = Dictionary(grouping: plans) { $0.sourceEventID ?? "" }

        var planBySourceID: [String: PlanBlock] = [:]
        for (sourceID, group) in groups where !sourceID.isEmpty {
            guard let primary = group.first else { continue }
            planBySourceID[sourceID] = primary
            for duplicate in group.dropFirst() {
                modelContext.delete(duplicate)
                result.deletedPlans += 1
            }
        }
        return planBySourceID
    }

    private func makeCache(from snapshot: CalendarEventSnapshot, now: Date) -> CalendarEventCache {
        CalendarEventCache(
            eventIdentifier: snapshot.eventIdentifier,
            calendarIdentifier: snapshot.calendarIdentifier,
            title: snapshot.normalizedTitle,
            startTime: snapshot.startTime,
            endTime: snapshot.normalizedEndTime,
            isAllDay: snapshot.isAllDay,
            colorHex: snapshot.colorHex,
            lastSyncedAt: now
        )
    }

    @discardableResult
    private func apply(_ snapshot: CalendarEventSnapshot, to cache: CalendarEventCache, now: Date) -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<CalendarEventCache, Value>, to value: Value) {
            if cache[keyPath: keyPath] != value {
                cache[keyPath: keyPath] = value
                didChange = true
            }
        }

        update(\.title, to: snapshot.normalizedTitle)
        update(\.startTime, to: snapshot.startTime)
        update(\.endTime, to: snapshot.normalizedEndTime)
        update(\.isAllDay, to: snapshot.isAllDay)
        update(\.colorHex, to: snapshot.colorHex)

        if cache.lastSyncedAt != now {
            cache.lastSyncedAt = now
            didChange = true
        }
        return didChange
    }

    private func makePlan(from snapshot: CalendarEventSnapshot, now: Date) -> PlanBlock {
        let plan = PlanBlock(
            category: nil,
            title: snapshot.normalizedTitle,
            startTime: snapshot.startTime,
            endTime: snapshot.normalizedEndTime,
            isAllDay: snapshot.isAllDay,
            isImportant: snapshot.isAllDay,
            note: nil,
            isPublic: false
        )
        plan.sourceEventID = snapshot.sourceEventID
        plan.createdAt = now
        plan.updatedAt = now
        return plan
    }

    @discardableResult
    private func apply(_ snapshot: CalendarEventSnapshot, to plan: PlanBlock, now: Date) -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PlanBlock, Value>, to value: Value) {
            if plan[keyPath: keyPath] != value {
                plan[keyPath: keyPath] = value
                didChange = true
            }
        }

        if plan.category != nil {
            plan.category = nil
            didChange = true
        }
        update(\.title, to: snapshot.normalizedTitle)
        update(\.startTime, to: snapshot.startTime)
        update(\.endTime, to: snapshot.normalizedEndTime)
        update(\.isAllDay, to: snapshot.isAllDay)
        update(\.isImportant, to: snapshot.isAllDay)
        update(\.note, to: nil)
        update(\.isPublic, to: false)
        update(\.sourceEventID, to: snapshot.sourceEventID)

        if didChange {
            plan.updatedAt = now
        }
        return didChange
    }
}

private extension CalendarEventCache {
    convenience init(
        eventIdentifier: String,
        calendarIdentifier: String,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        colorHex: String?,
        lastSyncedAt: Date
    ) {
        self.init()
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.lastSyncedAt = lastSyncedAt
    }

    func overlaps(_ interval: DateInterval) -> Bool {
        startTime < interval.end && endTime > interval.start
    }
}

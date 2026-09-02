import Foundation

enum DayPresetApplyPlanner {
    struct ExistingInterval: Equatable, Sendable {
        let id: UUID
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    enum ItemVerdict: Equatable, Sendable {
        case insertable
        case conflictsWithExisting([UUID])
        case conflictsWithinPreset([Int])
        case lockedDay
        case invalidTime
    }

    static func plan(
        items: [PlanTemplateSnapshot],
        targetDate: Date,
        existing: [ExistingInterval],
        now: Date,
        calendar: Calendar = .current
    ) -> [ItemVerdict] {
        let targetDayStart = DayBoundary.dayStart(for: targetDate, calendar: calendar)
        let todayStart = DayBoundary.dayStart(for: now, calendar: calendar)
        let intervals = items.map { $0.interval(on: targetDate, calendar: calendar) }

        return items.indices.map { index in
            let item = items[index]
            guard let interval = intervals[index] else {
                return .invalidTime
            }
            if !item.isAllDay, targetDayStart <= todayStart {
                return .lockedDay
            }
            guard !item.isAllDay else {
                return .insertable
            }

            let conflictingItemIndices = items.indices.filter { otherIndex in
                guard otherIndex != index,
                      !items[otherIndex].isAllDay,
                      intervals[otherIndex] != nil
                else { return false }
                return overlapsWithinTemplateDay(item, items[otherIndex])
            }
            if !conflictingItemIndices.isEmpty {
                return .conflictsWithinPreset(conflictingItemIndices)
            }

            let conflictingExistingIDs = existing.compactMap { candidate -> UUID? in
                guard !candidate.isAllDay,
                      candidate.start < candidate.end,
                      candidate.start < interval.end,
                      candidate.end > interval.start
                else { return nil }
                return candidate.id
            }
            .sorted { $0.uuidString < $1.uuidString }
            if !conflictingExistingIDs.isEmpty {
                return .conflictsWithExisting(conflictingExistingIDs)
            }
            return .insertable
        }
    }

    static func hasConflictsWithinPreset(
        _ items: [PlanTemplateSnapshot]
    ) -> Bool {
        items.indices.contains { index in
            let item = items[index]
            guard item.hasValidTime, !item.isAllDay else { return false }
            return items.indices.contains { otherIndex in
                guard otherIndex != index else { return false }
                return overlapsWithinTemplateDay(item, items[otherIndex])
            }
        }
    }

    private static func overlapsWithinTemplateDay(
        _ lhs: PlanTemplateSnapshot,
        _ rhs: PlanTemplateSnapshot
    ) -> Bool {
        minuteSegments(for: lhs).contains { left in
            minuteSegments(for: rhs).contains { right in
                left.lowerBound < right.upperBound && left.upperBound > right.lowerBound
            }
        }
    }

    private static func minuteSegments(
        for item: PlanTemplateSnapshot
    ) -> [Range<Int>] {
        guard item.hasValidTime, !item.isAllDay else { return [] }
        let dayEnd = 24 * 60
        if item.endMinute <= dayEnd {
            return [item.startMinute..<item.endMinute]
        }
        return [
            item.startMinute..<dayEnd,
            0..<(item.endMinute - dayEnd)
        ]
    }
}

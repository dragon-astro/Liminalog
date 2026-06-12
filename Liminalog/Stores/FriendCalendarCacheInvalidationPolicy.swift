import Foundation

struct FriendCalendarCacheInvalidationPlan: Equatable {
    var shouldClearAll = false
    var monthsToRemove: Set<Date> = []
    var shouldEnsureVisibleData = false

    static let noOp = FriendCalendarCacheInvalidationPlan()
}

struct FriendCalendarCacheInvalidationPolicy {
    static func plan(
        for change: SharedRecordChangeNotification,
        anchorMonth: Date,
        currentOffset: Int,
        calendar: Calendar = .japanese
    ) -> FriendCalendarCacheInvalidationPlan {
        guard let affectedMonths = change.affectedCalendarPageMonths(calendar: calendar) else {
            return FriendCalendarCacheInvalidationPlan(
                shouldClearAll: true,
                shouldEnsureVisibleData: true
            )
        }
        guard !affectedMonths.isEmpty else { return .noOp }

        let normalizedAffectedMonths = Set(affectedMonths.map { monthStart(for: $0, calendar: calendar) })
        let visibleMonths = Set(((currentOffset - 1)...(currentOffset + 1)).map { offset in
            let month = calendar.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
            return monthStart(for: month, calendar: calendar)
        })
        return FriendCalendarCacheInvalidationPlan(
            monthsToRemove: normalizedAffectedMonths,
            shouldEnsureVisibleData: !normalizedAffectedMonths.isDisjoint(with: visibleMonths)
        )
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

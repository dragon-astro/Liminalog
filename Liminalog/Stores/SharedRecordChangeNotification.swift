import Foundation

struct SharedRecordChangeNotification {
    let friendID: UUID?
    let requiresFullReload: Bool
    let affectedIntervals: [DateInterval]

    init(_ notification: Notification) {
        if let rawFriendID = notification.userInfo?[CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeFriendIDKey] as? String {
            friendID = UUID(uuidString: rawFriendID)
        } else {
            friendID = nil
        }
        requiresFullReload = notification.userInfo?[CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey] as? Bool ?? true
        let starts = notification.userInfo?[CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedStartDatesKey] as? [Date] ?? []
        let ends = notification.userInfo?[CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedEndDatesKey] as? [Date] ?? []
        affectedIntervals = zip(starts, ends).compactMap { start, end in
            FriendSharedRecordChangeImpact.interval(start: start, end: end)
        }
    }

    var hasKnownAffectedIntervals: Bool {
        !affectedIntervals.isEmpty
    }

    func affects(friendID targetFriendID: UUID) -> Bool {
        friendID.map { $0 == targetFriendID } ?? true
    }

    func affects(day: Date, calendar: Calendar = .japanese) -> Bool {
        guard !requiresFullReload else { return true }
        guard hasKnownAffectedIntervals else { return false }
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return affectedIntervals.contains { $0.start < dayEnd && $0.end > dayStart }
    }

    /// Calendar pages show leading/trailing days, so invalidate neighboring month pages too.
    func affectedCalendarPageMonths(calendar: Calendar = .japanese) -> Set<Date>? {
        guard !requiresFullReload else { return nil }
        guard hasKnownAffectedIntervals else { return [] }
        var months: Set<Date> = []
        for interval in affectedIntervals {
            let lastVisibleInstant = interval.end.addingTimeInterval(-0.001)
            let startMonth = monthStart(for: interval.start, calendar: calendar)
            let endMonth = monthStart(for: max(lastVisibleInstant, interval.start), calendar: calendar)
            var cursor = startMonth
            while cursor <= endMonth {
                for delta in -1...1 {
                    if let month = calendar.date(byAdding: .month, value: delta, to: cursor) {
                        months.insert(monthStart(for: month, calendar: calendar))
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
                cursor = next
            }
        }
        return months
    }

    private func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

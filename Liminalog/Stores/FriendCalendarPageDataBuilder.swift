import Foundation
import SwiftData

@MainActor
struct FriendCalendarPageDataBuilder {
    let friendID: UUID
    let modelContext: ModelContext
    var calendar: Calendar = .japanese
    var scoreForDate: (Date) -> CalendarDisplayScore? = { _ in nil }

    func pageData(for month: Date) -> CalendarMonthPageData {
        let dates = Self.monthGridDates(for: month, calendar: calendar)
        let gridStart = calendar.startOfDay(for: dates.first ?? month)
        let gridEnd = DayBoundary(date: dates.last ?? month, calendar: calendar).dayEnd
        let allPlans = FriendSharedRecordStore(modelContext: modelContext)
            .plans(friendID: friendID, overlapping: gridStart..<gridEnd)
        var importantPlansByDay: [Date: [CalendarDisplayPlan]] = [:]
        var scoreSummariesByDay: [Date: CalendarDisplayScore] = [:]

        for date in dates {
            let dayStart = calendar.startOfDay(for: date)
            let importantPlans = allPlans
                .filter { $0.overlaps(day: date) && $0.showsInCalendarAsImportant }
                .sorted {
                    if $0.startTime == $1.startTime {
                        return $0.updatedAt < $1.updatedAt
                    }
                    return $0.startTime < $1.startTime
                }
                .map(displayPlan(from:))
            let score = scoreForDate(date)
            if importantPlans.isEmpty && score == nil { continue }
            if !importantPlans.isEmpty {
                importantPlansByDay[dayStart] = importantPlans
            }
            if let score {
                scoreSummariesByDay[dayStart] = score
            }
        }

        return CalendarMonthPageData(
            dates: dates,
            visibleMonth: monthStart(for: month),
            importantPlansByDay: importantPlansByDay,
            scoreSummariesByDay: scoreSummariesByDay,
            didFailToLoadRecords: false
        )
    }

    static func monthGridDates(for month: Date, calendar: Calendar) -> [Date] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let dayCount = calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = (weekdayOffset + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        let weekCount = max(5, min(6, Int(ceil(Double(normalizedOffset + dayCount) / 7.0))))
        return (0..<(weekCount * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func displayPlan(from plan: FriendSharedPlanSnapshot) -> CalendarDisplayPlan {
        CalendarDisplayPlan(
            id: plan.id,
            title: plan.title,
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.categoryColorHex,
            createdAt: plan.updatedAt
        )
    }
}

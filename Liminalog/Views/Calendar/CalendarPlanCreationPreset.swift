import Foundation

struct CalendarPlanCreationPreset: Equatable {
    let initialDate: Date
    let startsAsAllDay: Bool

    static func make(
        for date: Date,
        canCreateTimedPlan: Bool,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> CalendarPlanCreationPreset {
        let dayStart = calendar.startOfDay(for: date)
        guard canCreateTimedPlan else {
            return CalendarPlanCreationPreset(initialDate: dayStart, startsAsAllDay: true)
        }

        let initialDate: Date
        if calendar.isDate(date, inSameDayAs: now) {
            initialDate = now
        } else {
            initialDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        }
        return CalendarPlanCreationPreset(initialDate: initialDate, startsAsAllDay: false)
    }
}

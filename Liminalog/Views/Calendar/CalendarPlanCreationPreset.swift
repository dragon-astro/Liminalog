import Foundation

struct CalendarPlanCreationPreset: Equatable {
    let initialDate: Date
    let startsAsAllDay: Bool

    static func make(
        for date: Date,
        canCreateTimedPlan: Bool,
        includesMemos: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> CalendarPlanCreationPreset? {
        let dayStart = calendar.startOfDay(for: date)
        guard includesMemos || allowsCreation(for: date, now: now, calendar: calendar) else {
            return nil
        }
        if includesMemos && dayStart < calendar.startOfDay(for: now) {
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
            return CalendarPlanCreationPreset(initialDate: start, startsAsAllDay: false)
        }
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

    /// 昨日以前は、時間指定不可を終日予定へ変換して作成制限を迂回させない。
    static func allowsCreation(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: now)
    }
}

import Foundation

enum PlanReminderTiming {
    static let validMinutes = (-5_256_000...5_256_000)
    static let presets = [0, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1_440, 2_880, 10_080, 20_160, 40_320]

    static func label(minutes: Int?, date: Date? = nil, isAllDay: Bool = false) -> String {
        if let date { return date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ja_JP"))) }
        guard let minutes else { return "なし" }
        if minutes == 0 { return isAllDay ? "当日 9:00" : "開始時刻" }
        let amount = abs(minutes)
        let value: String
        if amount % 10_080 == 0 { value = "\(amount / 10_080)週間" }
        else if amount % 1_440 == 0 { value = "\(amount / 1_440)日" }
        else if amount % 60 == 0 { value = "\(amount / 60)時間" }
        else { value = "\(amount)分" }
        return value + (minutes > 0 ? "前" : "後") + (isAllDay && amount % 1_440 == 0 ? " 9:00" : "")
    }

    /// Templates carry a relative delay so each occurrence receives its own reminder.
    static func templateMinutes(minutes: Int?, date: Date?, start: Date, isAllDay: Bool, calendar: Calendar = .current) -> Int? {
        guard let date else { return minutes }
        let base = isAllDay ? (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start) : start
        let offset = Int((base.timeIntervalSince(date) / 60).rounded())
        return validMinutes.contains(offset) ? offset : nil
    }
}

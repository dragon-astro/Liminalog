import Foundation

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

extension Date {
    private static let japaneseLocale = Locale(identifier: "ja_JP")

    /// 時刻のみ "9:30" 形式（日本ロケール固定で 24 時間表記）
    var shortTime: String {
        formatted(.dateTime.locale(Self.japaneseLocale).hour().minute())
    }

    /// "2026年" の形式
    var japaneseYear: String {
        formatted(.dateTime.locale(Self.japaneseLocale).year())
    }

    /// "2026年5月" の形式
    var japaneseYearMonth: String {
        formatted(.dateTime.locale(Self.japaneseLocale).year().month(.wide))
    }

    /// "5月24日" の形式
    var japaneseMonthDay: String {
        formatted(.dateTime.locale(Self.japaneseLocale).month().day())
    }

    /// "5月24日(土)" の形式
    var japaneseMonthDayShortWeekday: String {
        formatted(.dateTime.locale(Self.japaneseLocale).month().day().weekday(.abbreviated))
    }

    /// "2026年5月24日 土曜日" の形式
    var japaneseMonthDayWeekday: String {
        formatted(.dateTime.locale(Self.japaneseLocale).month(.wide).day().weekday(.wide))
    }

    /// "5月24日 18:30" の形式
    var japaneseShortDateTime: String {
        formatted(.dateTime.locale(Self.japaneseLocale).month().day().hour().minute())
    }
}

extension Calendar {
    nonisolated static var japanese: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    static let japaneseShortWeekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
}

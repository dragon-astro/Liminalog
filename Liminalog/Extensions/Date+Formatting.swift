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
    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var japaneseYearMonth: String {
        formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month(.wide))
    }

    var japaneseMonthDayWeekday: String {
        formatted(.dateTime.locale(Locale(identifier: "ja_JP")).month(.wide).day().weekday(.wide))
    }
}

extension Calendar {
    static var japanese: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    static let japaneseShortWeekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
}

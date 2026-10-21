import Foundation

struct PlanRecurrenceRule: Codable, Equatable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var title: String { switch self { case .daily: "日"; case .weekly: "週"; case .monthly: "月"; case .yearly: "年" } }
    }
    enum MonthlyMode: String, Codable, CaseIterable, Identifiable {
        case dayOfMonth, ordinalWeekday
        var id: String { rawValue }
        var title: String { self == .dayOfMonth ? "日付で" : "曜日で" }
    }
    enum MonthlyOrdinal: Int, Codable, CaseIterable, Identifiable {
        case first = 1, second, third, fourth
        case last = -1
        var id: Int { rawValue }
        var title: String { self == .last ? "最終" : "第\(rawValue)" }
    }
    var frequency: Frequency = .weekly
    var interval: Int = 1
    var weekdays: [Int] = []
    var startDate: Date
    var endDate: Date?
    var occurrenceLimit: Int? = nil
    // Old rules used an inclusive end day. Only newly chosen date/time endings use the exact instant.
    var endDateIncludesTime: Bool? = nil
    var monthlyMode: MonthlyMode = .dayOfMonth
    var monthlyOrdinals: [MonthlyOrdinal] = [.first]
    /// Calendar weekday (Sunday = 1); nil follows the starting date's weekday.
    var monthlyWeekday: Int? = nil

    var isValid: Bool {
        (1...365).contains(interval) && weekdays.allSatisfy { (1...7).contains($0) }
            && (monthlyWeekday.map { (1...7).contains($0) } ?? true)
            && (frequency != .monthly || monthlyMode != .ordinalWeekday || !monthlyOrdinals.isEmpty)
            && (endDate.map { Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: startDate) } ?? true)
            && (occurrenceLimit.map { (1...10_000).contains($0) } ?? true)
            && !(occurrenceLimit != nil && endDate != nil)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        guard (1...365).contains(interval), day >= start,
              endDate.map({ day <= calendar.startOfDay(for: $0) }) ?? true else { return false }
        let matches: Bool
        switch frequency {
        case .daily:
            matches = (calendar.dateComponents([.day], from: start, to: day).day ?? -1) % interval == 0
        case .weekly:
            guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
                  let currentWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return false }
            let weeks = (calendar.dateComponents([.day], from: firstWeek, to: currentWeek).day ?? -7) / 7
            matches = weeks % interval == 0 && selectedWeekdays(calendar: calendar).contains(calendar.component(.weekday, from: day))
        case .monthly:
            guard let firstMonth = calendar.dateInterval(of: .month, for: start)?.start,
                  let currentMonth = calendar.dateInterval(of: .month, for: day)?.start else { return false }
            matches = (calendar.dateComponents([.month], from: firstMonth, to: currentMonth).month ?? -1) % interval == 0
                && (monthlyMode == .dayOfMonth
                    ? calendar.component(.day, from: day) == calendar.component(.day, from: start)
                    : monthlyDates(in: currentMonth, calendar: calendar).contains(day))
        case .yearly:
            guard calendar.component(.month, from: day) == calendar.component(.month, from: start),
                  calendar.component(.day, from: day) == calendar.component(.day, from: start),
                  let firstYear = calendar.dateInterval(of: .year, for: start)?.start,
                  let currentYear = calendar.dateInterval(of: .year, for: day)?.start else { return false }
            matches = (calendar.dateComponents([.year], from: firstYear, to: currentYear).year ?? -1) % interval == 0
        }
        guard matches else { return false }
        guard let limit = occurrenceLimit else { return true }
        return limit > 0 && occurrenceNumber(on: day, calendar: calendar) <= limit
    }

    func allows(startingAt date: Date, on occurrenceDay: Date, calendar: Calendar = .current) -> Bool {
        guard contains(occurrenceDay, calendar: calendar) else { return false }
        return endDateIncludesTime != true || endDate.map { date <= $0 } ?? true
    }

    /// Counts scheduled dates, independent of edits, deletion, conflicts or the materialization window.
    private func occurrenceNumber(on day: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: startDate)
        switch frequency {
        case .daily:
            return (calendar.dateComponents([.day], from: start, to: day).day ?? 0) / interval + 1
        case .weekly:
            guard let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
                  let current = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return Int.max }
            let periods = (calendar.dateComponents([.day], from: first, to: current).day ?? 0) / (7 * interval)
            let selected = Set(selectedWeekdays(calendar: calendar))
            func count(in week: Date, from lower: Date, through upper: Date) -> Int {
                (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }
                    .filter { $0 >= lower && $0 <= upper && selected.contains(calendar.component(.weekday, from: $0)) }.count
            }
            if periods == 0 { return count(in: first, from: start, through: day) }
            return count(in: first, from: start, through: current)
                + max(0, periods - 1) * selected.count + count(in: current, from: current, through: day)
        case .monthly:
            guard let first = calendar.dateInterval(of: .month, for: start)?.start,
                  let current = calendar.dateInterval(of: .month, for: day)?.start else { return Int.max }
            let periodCount = (calendar.dateComponents([.month], from: first, to: current).month ?? 0) / interval
            var count = 0
            for period in 0...max(0, periodCount) {
                guard let month = calendar.date(byAdding: .month, value: period * interval, to: first) else { continue }
                count += monthlyDates(in: month, calendar: calendar).filter { $0 >= start && $0 <= day }.count
                if let limit = occurrenceLimit, count > limit { return count }
            }
            return count
        case .yearly:
            let component: Calendar.Component = .year
            guard let first = calendar.dateInterval(of: component, for: start)?.start,
                  let current = calendar.dateInterval(of: component, for: day)?.start else { return Int.max }
            let periodCount = (calendar.dateComponents([component], from: first, to: current).value(for: component) ?? 0) / interval
            var count = 0
            for period in 0...max(0, periodCount) {
                guard let base = calendar.date(byAdding: component, value: period * interval, to: first) else { continue }
                var parts = calendar.dateComponents([.era, .year, .month], from: base)
                parts.month = calendar.component(.month, from: start)
                parts.day = calendar.component(.day, from: start)
                guard let occurrence = calendar.date(from: parts),
                      calendar.component(.month, from: occurrence) == parts.month,
                      calendar.component(.day, from: occurrence) == parts.day else { continue }
                count += 1
                if let limit = occurrenceLimit, count > limit { return count }
            }
            return count
        }
    }

    private func selectedWeekdays(calendar: Calendar) -> [Int] {
        weekdays.isEmpty ? [calendar.component(.weekday, from: startDate)] : weekdays.filter { (1...7).contains($0) }
    }

    func selectedMonthlyWeekday(calendar: Calendar = .current) -> Int {
        monthlyWeekday ?? calendar.component(.weekday, from: startDate)
    }

    /// Builds dates within this month only. In a four-occurrence month, fourth and last
    /// resolve to one date so they never consume two occurrences of a count ending.
    private func monthlyDates(in month: Date, calendar: Calendar) -> [Date] {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let dayNumbers: Set<Int>
        switch monthlyMode {
        case .dayOfMonth:
            dayNumbers = [calendar.component(.day, from: startDate)]
        case .ordinalWeekday:
            let weekday = selectedMonthlyWeekday(calendar: calendar)
            guard (1...7).contains(weekday) else { return [] }
            let firstDay = days.lowerBound + (weekday - calendar.component(.weekday, from: month) + 7) % 7
            dayNumbers = Set(monthlyOrdinals.map { ordinal in
                ordinal == .last
                    ? firstDay + ((days.upperBound - 1 - firstDay) / 7) * 7
                    : firstDay + (ordinal.rawValue - 1) * 7
            })
        }
        return dayNumbers.sorted().filter { days.contains($0) }.compactMap {
            calendar.date(byAdding: .day, value: $0 - days.lowerBound, to: month)
        }
    }

    var cadence: String { interval == 1 ? "毎\(frequency.title)" : "\(interval)\(frequency == .monthly ? "か月" : frequency.title)ごと" }
    var summary: String { summary(calendar: .current) }

    func summary(calendar: Calendar) -> String {
        let labels = ["日", "月", "火", "水", "木", "金", "土"]
        if frequency == .weekly {
            return cadence + " " + selectedWeekdays(calendar: calendar).sorted().map { labels[$0 - 1] }.joined(separator: "・")
        }
        if frequency == .monthly {
            if monthlyMode == .ordinalWeekday {
                let weekday = selectedMonthlyWeekday(calendar: calendar)
                guard (1...7).contains(weekday) else { return cadence }
                let ordinals = MonthlyOrdinal.allCases.filter { monthlyOrdinals.contains($0) }.map(\.title)
                return cadence + " " + ordinals.joined(separator: "・") + labels[weekday - 1] + "曜"
            }
            return cadence + "\(calendar.component(.day, from: startDate))日"
        }
        if frequency == .yearly { return cadence + "\(calendar.component(.month, from: startDate))月\(calendar.component(.day, from: startDate))日" }
        return cadence
    }
    var endingSummary: String {
        if let count = occurrenceLimit { return "\(count)回で終了" }
        if let endDate {
            let style: Date.FormatStyle = endDateIncludesTime == true ? .dateTime.month().day().hour().minute() : .dateTime.month().day()
            return endDate.formatted(style.locale(Locale(identifier: "ja_JP"))) + "まで"
        }
        return "終了しない"
    }
    static func decode(_ data: Data?) -> Self? {
        guard let data, let rule = try? JSONDecoder().decode(Self.self, from: data), rule.isValid else { return nil }
        return rule
    }
    var data: Data? { try? JSONEncoder().encode(self) }
}

extension PlanRecurrenceRule {
    private enum CodingKeys: String, CodingKey {
        case frequency, interval, weekdays, startDate, endDate, occurrenceLimit, endDateIncludesTime
        case monthlyMode, monthlyOrdinals, monthlyWeekday
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try values.decode(Frequency.self, forKey: .frequency)
        interval = try values.decode(Int.self, forKey: .interval)
        weekdays = try values.decode([Int].self, forKey: .weekdays)
        startDate = try values.decode(Date.self, forKey: .startDate)
        endDate = try values.decodeIfPresent(Date.self, forKey: .endDate)
        occurrenceLimit = try values.decodeIfPresent(Int.self, forKey: .occurrenceLimit)
        endDateIncludesTime = try values.decodeIfPresent(Bool.self, forKey: .endDateIncludesTime)
        // Existing persisted JSON has no monthly fields and keeps its original day-of-month rule.
        monthlyMode = try values.decodeIfPresent(MonthlyMode.self, forKey: .monthlyMode) ?? .dayOfMonth
        monthlyOrdinals = try values.decodeIfPresent([MonthlyOrdinal].self, forKey: .monthlyOrdinals) ?? [.first]
        monthlyWeekday = try values.decodeIfPresent(Int.self, forKey: .monthlyWeekday)
    }
}

extension Notification.Name {
    static let planSchedulingChanged = Notification.Name("Liminalog.planSchedulingChanged")
}

import Foundation

struct PlanTemplateSnapshot: Codable, Equatable, Sendable {
    var title: String
    var categoryID: UUID?
    var startMinute: Int
    var endMinute: Int
    var isAllDay: Bool
    var isImportant: Bool
    var note: String?
    var isPublic: Bool

    var durationMinutes: Int {
        max(1, endMinute - startMinute)
    }

    var hasValidTime: Bool {
        guard !isAllDay else { return true }
        return (0..<Self.minutesPerDay).contains(startMinute)
            && endMinute > startMinute
            && endMinute <= startMinute + Self.minutesPerDay
    }

    func interval(
        on targetDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        let boundary = DayBoundary(date: targetDate, calendar: calendar)
        if isAllDay {
            return DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
        }
        guard hasValidTime,
              let start = Self.wallClockDate(
                minuteOffset: startMinute,
                from: boundary.dayStart,
                calendar: calendar
              ),
              let end = Self.wallClockDate(
                minuteOffset: endMinute,
                from: boundary.dayStart,
                calendar: calendar
              ),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static let minutesPerDay = 24 * 60

    /// Converts a template's local wall-clock minute to an absolute date.
    /// Building date components keeps ordinary times such as 09:00 stable on
    /// daylight-saving transition days instead of treating the value as
    /// elapsed seconds since midnight.
    private static func wallClockDate(
        minuteOffset: Int,
        from dayStart: Date,
        calendar: Calendar
    ) -> Date? {
        let dayOffset = minuteOffset / minutesPerDay
        let minuteOfDay = minuteOffset % minutesPerDay
        guard let targetDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: dayStart
        ) else { return nil }

        var components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: targetDay
        )
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.second = 0
        return calendar.date(from: components)
    }
}

struct DayPresetItemsEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var items: [PlanTemplateSnapshot]

    init(
        version: Int = Self.currentVersion,
        items: [PlanTemplateSnapshot]
    ) {
        self.version = version
        self.items = items
    }
}

enum DayPresetItemsCodec {
    enum CodecError: Error, Equatable {
        case invalidPayload
        case unsupportedVersion(Int)
    }

    static func encode(
        _ items: [PlanTemplateSnapshot],
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try encoder.encode(DayPresetItemsEnvelope(items: items))
    }

    static func decode(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [PlanTemplateSnapshot] {
        let envelope: DayPresetItemsEnvelope
        do {
            envelope = try decoder.decode(DayPresetItemsEnvelope.self, from: data)
        } catch {
            throw CodecError.invalidPayload
        }
        guard envelope.version == DayPresetItemsEnvelope.currentVersion else {
            throw CodecError.unsupportedVersion(envelope.version)
        }
        return envelope.items
    }
}

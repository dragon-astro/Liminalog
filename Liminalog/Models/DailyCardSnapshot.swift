import Foundation
import SwiftData

enum DailyCardPersonaKind: String, Codable, CaseIterable, Identifiable {
    case missingDay
    case planMatched
    case chargeDay
    case signal
    case noPlan
    case shape

    var id: String { rawValue }
}

struct DailyCardSnapshotFactPayload: Codable, Hashable {
    var id: String
    var title: String
    var value: String
    var suffix: String?
    var systemImage: String
}

struct DailyCardSnapshotCategoryPayload: Codable, Hashable {
    var categoryID: UUID
    var name: String
    var colorHex: String
    var duration: TimeInterval
}

struct DailyCardTitleCollectionEntry: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let personaKind: DailyCardPersonaKind
    let symbol: String
    let count: Int
    let latestDayStart: Date
}

@Model
final class DailyCardSnapshot {
    var id: UUID = UUID()
    var dayStart: Date = Date.distantPast
    var dayIdentifier: String = ""
    var schemaVersion: Int = 1
    var personaKindRawValue: String = DailyCardPersonaKind.shape.rawValue
    var title: String = ""
    var message: String = ""
    var symbol: String = "sparkles"
    var score: Int = 0
    var plannedDuration: TimeInterval = 0
    var recordedDuration: TimeInterval = 0
    var factPayloadJSON: String = "[]"
    var categoryPayloadJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var personaKind: DailyCardPersonaKind {
        get { DailyCardPersonaKind(rawValue: personaKindRawValue) ?? .shape }
        set { personaKindRawValue = newValue.rawValue }
    }

    var facts: [DailyCardSnapshotFactPayload] {
        Self.decode([DailyCardSnapshotFactPayload].self, from: factPayloadJSON) ?? []
    }

    var categories: [DailyCardSnapshotCategoryPayload] {
        Self.decode([DailyCardSnapshotCategoryPayload].self, from: categoryPayloadJSON) ?? []
    }

    init() {}

    static func dayIdentifier(for dayStart: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        ]
        .map { String(format: "%02d", $0) }
        .joined(separator: "-")
    }

    static func encode<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from string: String) -> Value? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

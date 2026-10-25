import Foundation
import SwiftData

enum PlanPresetPlacementMode: String, CaseIterable, Codable, Sendable {
    case duration
    case fixedTime

    var title: String {
        switch self {
        case .duration: "長さだけ"
        case .fixedTime: "時刻を固定"
        }
    }
}

@Model
final class PlanPreset {
    var id: UUID = UUID()
    var name: String = ""
    var title: String = ""
    var categoryID: UUID?
    var startMinute: Int = 9 * 60
    var endMinute: Int = 10 * 60
    var isMemo: Bool = false
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var reminderMinutesBefore: Int?
    var placementModeRawValue: String = PlanPresetPlacementMode.duration.rawValue
    var sortOrder: Int = 0
    var recurrenceData: Data?
    var lastUsedAt: Date?
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        name: String,
        title: String,
        categoryID: UUID? = nil,
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        placementMode: PlanPresetPlacementMode = .duration,
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.title = title
        self.categoryID = categoryID
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.isAllDay = isAllDay
        self.isImportant = isImportant
        self.note = note
        self.isPublic = isPublic
        self.placementModeRawValue = placementMode.rawValue
        self.sortOrder = sortOrder
        self.lastUsedAt = nil
        self.useCount = 0
        self.createdAt = now
        self.updatedAt = now
    }

    var snapshot: PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title,
            categoryID: categoryID,
            startMinute: startMinute,
            endMinute: endMinute,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note,
            isPublic: isPublic,
            reminderMinutesBefore: reminderMinutesBefore,
            isMemo: false
        )
    }

    var placementMode: PlanPresetPlacementMode {
        get { PlanPresetPlacementMode(rawValue: placementModeRawValue) ?? .duration }
        set { placementModeRawValue = newValue.rawValue }
    }

    /// 予定プリセットは予定名そのものを識別名として扱う。
    /// 旧データで予定名が空の場合だけ、従来のプリセット名へフォールバックする。
    var displayName: String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? name : normalizedTitle
    }
}

@Model
final class DayPreset {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#2F80ED"
    var icon: String = "calendar"
    var itemsData: Data = Data()
    var itemCount: Int = 0
    var sortOrder: Int = 0
    var recurrenceData: Data?
    var lastUsedAt: Date?
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        name: String,
        itemsData: Data,
        itemCount: Int,
        colorHex: String = "#2F80ED",
        icon: String = "calendar",
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.itemsData = itemsData
        self.itemCount = itemCount
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.lastUsedAt = nil
        self.useCount = 0
        self.createdAt = now
        self.updatedAt = now
    }
}

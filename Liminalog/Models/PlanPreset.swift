import Foundation
import SwiftData

@Model
final class PlanPreset {
    var id: UUID = UUID()
    var name: String = ""
    var title: String = ""
    var categoryID: UUID?
    var startMinute: Int = 9 * 60
    var endMinute: Int = 10 * 60
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var sortOrder: Int = 0
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
            isPublic: isPublic
        )
    }
}

@Model
final class DayPreset {
    var id: UUID = UUID()
    var name: String = ""
    var itemsData: Data = Data()
    var itemCount: Int = 0
    var sortOrder: Int = 0
    var lastUsedAt: Date?
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        name: String,
        itemsData: Data,
        itemCount: Int,
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.itemsData = itemsData
        self.itemCount = itemCount
        self.sortOrder = sortOrder
        self.lastUsedAt = nil
        self.useCount = 0
        self.createdAt = now
        self.updatedAt = now
    }
}

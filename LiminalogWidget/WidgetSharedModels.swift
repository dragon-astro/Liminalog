import Foundation
import SwiftData

enum VisibilityScope: String, Codable {
    case all
    case preset
    case none
}

enum VisibilityLevel: String, Codable {
    case all, partial, none
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var icon: String?
    var sortOrder: Int = 0
    var isDefault: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    var chapters: [Chapter]? = []

    @Relationship(deleteRule: .nullify, inverse: \PlanBlock.category)
    var plans: [PlanBlock]? = []

    init() {}
}

@Model
final class CategorySet {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var slots: [UUID?] = Array<UUID?>(repeating: nil, count: 8)
    var isDefault: Bool = false
    var createdAt: Date = Date()

    static let slotCount = 8

    init() {}
}

@Model
final class Chapter {
    var id: UUID = UUID()
    var category: Category?
    var startTime: Date = Date()
    var endTime: Date?
    var note: String?
    var mood: String?
    var photoLocalIdentifier: String?
    var thumbnailData: Data?
    var locationName: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(category: Category, startTime: Date) {
        self.id = UUID()
        self.category = category
        self.startTime = startTime
        self.endTime = nil
        self.note = nil
        self.mood = nil
        self.photoLocalIdentifier = nil
        self.thumbnailData = nil
        self.locationName = nil
        self.isPublic = true
        self.visibilityScope = .all
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var category: Category?
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var sourceEventID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class VisibilityPreset {
    var id: UUID = UUID()
    var name: String = ""
    var level: VisibilityLevel = VisibilityLevel.all
    var builtInKey: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class UserSettings {
    var id: UUID = UUID()
    var settingsKey: String = "default"
    var defaultVisibility: VisibilityScope = VisibilityScope.all
    var themeName: String = "default"
    var enabledCategorySetID: UUID?
    var calendarSyncEnabled: Bool = false
    var showCalendarOverlay: Bool = true
    var dashboardCardOrder: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class CalendarEventCache {
    var id: UUID = UUID()
    var eventIdentifier: String = ""
    var calendarIdentifier: String = ""
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var colorHex: String?
    var lastSyncedAt: Date = Date()

    init() {}
}

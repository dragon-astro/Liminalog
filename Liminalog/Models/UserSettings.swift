import Foundation
import SwiftData

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

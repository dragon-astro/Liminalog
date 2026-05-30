import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID = UUID()
    var settingsKey: String = "default"
    var profileDisplayName: String = ""
    var profileBio: String = ""
    var profileImageData: Data?
    var profileAccentColorHex: String = "#2F80ED"
    var profileBadgeID: String = "starter"
    var profileIconFrameID: String = "halo"
    var profileStreakIconID: String = "flame"
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

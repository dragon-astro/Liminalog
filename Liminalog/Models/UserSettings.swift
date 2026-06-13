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
    var profileIconFrameID: String = "clear_air"
    var profileStreakIconID: String = "flame"
    var profileCardStyleID: String = "quiet_sky"
    var cloudUsername: String = ""
    var cloudUsernameNormalized: String = ""
    var cloudUserRecordName: String = ""
    var cloudUsernameRegisteredAt: Date?
    var equippedUnlockItemKeys: [String] = []
    var seenUnlockItemKeys: [String] = []
    var defaultVisibility: VisibilityScope = VisibilityScope.all
    var themeName: String = "default"
    var enabledCategorySetID: UUID?
    var calendarSyncEnabled: Bool = false
    var showCalendarOverlay: Bool = true
    var dashboardCardOrder: [String] = []
    var dashboardHiddenCardKeys: [String] = []
    var didSeedInitialFriendSets: Bool = false
    var finalizedCumulativeScore: Int = 0
    var isFinalizedScoreLedgerInitialized: Bool = false
    var finalizedScoreReconciledThroughDayStart: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

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

enum AudienceSource: String, Codable, CaseIterable {
    case categoryDefaultSnapshot
    case custom
}

enum DailyCardCategoryIntent: String, Codable, CaseIterable, Identifiable {
    case neutral
    case increase
    case decrease

    var id: String { rawValue }
}

enum PublishMode: String, Codable, CaseIterable, Identifiable {
    case realtime
    case nextDay
    case none

    var id: String { rawValue }
}

enum FriendStatus: String, Codable, CaseIterable, Identifiable {
    case pendingIncoming
    case pendingOutgoing
    case accepted
    case blocked

    var id: String { rawValue }
}

enum UnlockKind: String, Codable, CaseIterable, Identifiable {
    case theme
    case iconFrame
    case nameBadge
    case streakIcon
    case cardStyle
    case iconSet
    case barStyle
    case monthArt

    var id: String { rawValue }
}

enum UnlockRequirementKind: String, Codable, CaseIterable, Identifiable {
    case cumulativeScore
    case recordedDays
    case recordedHours
    case streakDays
    case earlyRecordDays
    case lateNightRecordDays
    case distinctCategoryCount
    case planMatchedDays
    case chargeDays
    case morningPersonaDays
    case nightPersonaDays
    case recordingHabitDays
    case personalBestDays
    case returnAfterGapDays
    case firstRecordDays
    case balancedDays
    case focusedDays
    case changeSignalDays

    var id: String { rawValue }
}

enum DailyCardPersonaKind: String, Codable, CaseIterable, Identifiable {
    case missingDay
    case planMatched
    case chargeDay
    case signal
    case noPlan
    case shape

    var id: String { rawValue }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var icon: String?
    var sortOrder: Int = 0
    var isDefault: Bool = false
    var dailyCardIntentRawValue: String = DailyCardCategoryIntent.neutral.rawValue
    var isDailyCardSleepCategory: Bool = false
    var defaultAudienceFriendSetIDs: [UUID] = []
    var defaultAudienceIncludedFriendIDs: [UUID] = []
    var defaultAudienceExcludedFriendIDs: [UUID] = []
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
    var audienceFriendIDs: [UUID] = []
    var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
    var hasAudienceSnapshot: Bool = false
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
        self.audienceFriendIDs = []
        self.audienceSourceRawValue = AudienceSource.categoryDefaultSnapshot.rawValue
        self.hasAudienceSnapshot = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct RecordingSurfaceSnapshot: Codable, Hashable {
    struct Cell: Codable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let icon: String?
    }

    let selectedCategorySetID: UUID?
    let categorySetName: String
    let cells: [Cell?]

    var categories: [Cell] {
        cells.compactMap { $0 }
    }
}

struct RecordingSwitchResult {
    let activeChapter: Chapter?
    let didCreateChapter: Bool
    let closedChapterCount: Int
}

enum RecordingSwitchLogic {
    @discardableResult
    static func switchToCategory(
        _ category: Category,
        at now: Date,
        activeChapters: [Chapter],
        insert: (Chapter) -> Void
    ) -> RecordingSwitchResult {
        let sameCategoryActive = activeChapters.first { $0.category?.id == category.id }
        var activeAfterChange = sameCategoryActive
        var closedChapterCount = 0

        for chapter in activeChapters where chapter.id != sameCategoryActive?.id {
            chapter.endTime = now
            chapter.updatedAt = now
            closedChapterCount += 1
        }

        guard sameCategoryActive == nil else {
            return RecordingSwitchResult(
                activeChapter: activeAfterChange,
                didCreateChapter: false,
                closedChapterCount: closedChapterCount
            )
        }

        let chapter = Chapter(category: category, startTime: now)
        insert(chapter)
        activeAfterChange = chapter

        return RecordingSwitchResult(
            activeChapter: activeAfterChange,
            didCreateChapter: true,
            closedChapterCount: closedChapterCount
        )
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
    var audienceFriendIDs: [UUID] = []
    var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
    var hasAudienceSnapshot: Bool = false
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
    var isBuiltIn: Bool = false
    var sortOrder: Int = 0
    var publishModeRawValue: String = PublishMode.realtime.rawValue
    var hideMoodAndNote: Bool = false
    var hidePhoto: Bool = true
    var hideLocation: Bool = true
    var excludedCategoryIDs: [UUID] = []
    var freeTimeOnly: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

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

@Model
final class UnlockItem {
    var id: UUID = UUID()
    var key: String = ""
    var kindRawValue: String = UnlockKind.theme.rawValue
    var requiredCumulativeScore: Int = 0
    var requirementKindRawValue: String = UnlockRequirementKind.cumulativeScore.rawValue
    var requiredValue: Int = 0
    var unlockedAt: Date?
    var displayName: String = ""
    var systemImageName: String = "sparkles"
    var tintHex: String = "#C9A7FF"
    var targetID: String = ""
    var thumbnailName: String?
    var sortOrder: Int = 0
    var isBuiltIn: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class Friend {
    var id: UUID = UUID()
    var userRecordID: String = ""
    var displayName: String = ""
    var handle: String = ""
    var bio: String?
    var avatarSystemImage: String = "person.crop.circle.fill"
    var accentColorHex: String = "#2F80ED"
    var profileBadgeID: String = "starter"
    var profileIconFrameID: String = "clear_air"
    var profileStreakIconID: String = "flame"
    var profileCardStyleID: String = "quiet_sky"
    var statusRawValue: String = FriendStatus.pendingOutgoing.rawValue
    var isFavorite: Bool = false
    var shareURL: String?
    var inviteCode: String = ""
    var visibilityPresetID: UUID?
    var currentStatusTitle: String = ""
    var currentStatusIcon: String = "circle.dashed"
    var currentStatusColorHex: String = "#8E8E93"
    var currentMoodText: String = ""
    var currentStatusStartedAt: Date?
    var currentStatusUpdatedAt: Date?
    var todayScore: Double = 0
    var yesterdayScore: Double = 0
    var weekScore: Double = 0
    var monthScore: Double = 0
    var yearScore: Double = 0
    var sharedPlansJSON: String = "[]"
    var sharedActivitiesJSON: String = "[]"
    @Relationship(deleteRule: .cascade, inverse: \FriendCategoryMapping.friend)
    var categoryMappings: [FriendCategoryMapping]? = []
    var streakCount: Int = 0
    var lastSeenAt: Date?
    var acceptedAt: Date?
    var blockedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class FriendSet {
    var id: UUID = UUID()
    var name: String = ""
    var memberFriendIDs: [UUID] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class FriendCategoryMapping {
    var id: UUID = UUID()
    @Relationship(deleteRule: .nullify)
    var friend: Friend?
    var myCategoryID: UUID = UUID()
    var friendCategoryID: UUID = UUID()
    var useUnifiedColor: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
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

    init() {}
}

@Model
final class FriendSharedPlanRecord {
    #Index<FriendSharedPlanRecord>([\.friendID, \.startTime])

    var friendID: UUID = UUID()
    var sourceID: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var categoryID: UUID?
    var categoryTitle: String = ""
    var categoryIconName: String = "calendar"
    var categoryColorHex: String = "#2F80ED"
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class FriendSharedChapterRecord {
    #Index<FriendSharedChapterRecord>([\.friendID, \.startTime])

    var friendID: UUID = UUID()
    var sourceID: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var categoryID: UUID?
    var categoryTitle: String = ""
    var categoryIconName: String = "circle.fill"
    var categoryColorHex: String = "#2F80ED"
    var note: String?
    var mood: String?
    var locationName: String?
    var updatedAt: Date = Date()

    init() {}
}

@Model
final class FriendSharePublishedItem {
    #Index<FriendSharePublishedItem>([\.targetUserRecordName])

    var targetUserRecordName: String = ""
    var kindRawValue: String = ""
    var sourceID: UUID = UUID()
    var fingerprint: String = ""

    init() {}
}

@Model
final class FriendShareZoneSyncState {
    var ownerUserRecordName: String = ""
    var changeTokenData: Data?
    var updatedAt: Date = Date()

    init() {}
}

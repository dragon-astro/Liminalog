import CryptoKit
import Foundation
import SwiftData

enum FriendStatus: String, Codable, CaseIterable, Identifiable {
    case pendingIncoming
    case pendingOutgoing
    case accepted
    case blocked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pendingIncoming:
            "承認待ち"
        case .pendingOutgoing:
            "招待中"
        case .accepted:
            "友達"
        case .blocked:
            "ブロック中"
        }
    }
}

@Model
final class Friend {
    var id: UUID = UUID()
    var userRecordID: String = ""
    var displayName: String = ""
    var handle: String = ""
    var bio: String?
    var profileImageData: Data?
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
    /// 友達の累積スコア（365日窓・Lv表示用）。共有スナップショット由来。永続化はCloudKitスキーマ固定後に扱う。
    @Transient
    var cumulativeScore: Int = 0
    /// 旧・塊JSON方式の名残。CloudKit同期スキーマは追記専用（プロパティ削除は既存ストアを壊す）ため、
    /// 未使用のまま残置している。読み書きしないこと。個別行キャッシュ（FriendSharedRecord）が後継。
    var sharedPlansJSON: String = "[]"
    var sharedActivitiesJSON: String = "[]"
    /// CloudKit統合は全リレーションに inverse が必須（無いと同期コンテナがロード拒否される。実機で観測）。
    @Relationship(deleteRule: .cascade, inverse: \FriendCategoryMapping.friend)
    var categoryMappings: [FriendCategoryMapping]? = []
    var streakCount: Int = 0
    var lastSeenAt: Date?
    var acceptedAt: Date?
    var blockedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var status: FriendStatus {
        get { FriendStatus(rawValue: statusRawValue) ?? .pendingOutgoing }
        set { statusRawValue = newValue.rawValue }
    }

    var isPending: Bool {
        status == .pendingIncoming || status == .pendingOutgoing
    }

    init() {}

    init(
        displayName: String,
        handle: String = "",
        status: FriendStatus = .pendingOutgoing,
        inviteCode: String = "",
        shareURL: String? = nil,
        accentColorHex: String = "#2F80ED",
        avatarSystemImage: String = "person.crop.circle.fill",
        now: Date = Date()
    ) {
        self.id = UUID()
        self.userRecordID = ""
        self.displayName = displayName
        self.handle = handle
        self.bio = nil
        self.profileImageData = nil
        self.avatarSystemImage = avatarSystemImage
        self.accentColorHex = accentColorHex
        self.profileBadgeID = "starter"
        self.profileIconFrameID = "clear_air"
        self.profileStreakIconID = "flame"
        self.profileCardStyleID = "quiet_sky"
        self.statusRawValue = status.rawValue
        self.isFavorite = false
        self.shareURL = shareURL
        self.inviteCode = inviteCode
        self.visibilityPresetID = nil
        self.currentStatusTitle = ""
        self.currentStatusIcon = "circle.dashed"
        self.currentStatusColorHex = "#8E8E93"
        self.currentMoodText = ""
        self.currentStatusStartedAt = nil
        self.currentStatusUpdatedAt = nil
        self.todayScore = 0
        self.yesterdayScore = 0
        self.weekScore = 0
        self.monthScore = 0
        self.yearScore = 0
        self.sharedPlansJSON = "[]"
        self.sharedActivitiesJSON = "[]"
        self.streakCount = 0
        self.lastSeenAt = nil
        self.acceptedAt = status == .accepted ? now : nil
        self.blockedAt = status == .blocked ? now : nil
        self.createdAt = now
        self.updatedAt = now
    }

    func score(for period: FriendScorePeriod) -> Double {
        switch period {
        case .day:
            // Friend-side arbitrary daily scores are not synced yet.
            // Until CloudKit provides per-day score snapshots, detail ranking reuses yesterdayScore.
            yesterdayScore
        case .today:
            todayScore
        case .yesterday:
            yesterdayScore
        case .week:
            weekScore
        case .month:
            monthScore
        case .year:
            yearScore
        }
    }

}

struct FriendSharedPlanSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var categoryID: UUID?
    var title: String
    var startTime: Date
    var endTime: Date
    var isAllDay: Bool
    var isImportant: Bool
    var categoryTitle: String
    var categoryIconName: String
    var categoryColorHex: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        categoryTitle: String = "",
        categoryIconName: String = "calendar",
        categoryColorHex: String = "#2F80ED",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.isImportant = isImportant
        self.categoryTitle = categoryTitle
        self.categoryIconName = categoryIconName
        self.categoryColorHex = categoryColorHex
        self.updatedAt = updatedAt
    }

    init(plan: PlanBlock) {
        self.id = plan.id
        self.categoryID = plan.category?.id
        self.title = plan.title
        self.startTime = plan.startTime
        self.endTime = plan.endTime
        self.isAllDay = plan.isAllDay
        self.isImportant = plan.isImportant
        self.categoryTitle = plan.category?.name ?? ""
        self.categoryIconName = plan.category?.icon ?? "calendar"
        self.categoryColorHex = plan.category?.colorHex ?? "#2F80ED"
        self.updatedAt = plan.updatedAt
    }

    static func snapshots(
        from plans: [PlanBlock],
        visibilityPreset: VisibilityPreset? = nil,
        recipientFriendID: UUID? = nil,
        acceptedFriendIDs: Set<UUID> = [],
        now: Date = Date()
    ) -> [FriendSharedPlanSnapshot] {
        let policy = FriendSharingVisibilityPolicy(
            visibilityPreset: visibilityPreset,
            recipientFriendID: recipientFriendID,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )

        return plans
            .compactMap { policy.snapshot(for: $0) }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.startTime < $1.startTime
            }
    }

    var showsInCalendarAsImportant: Bool {
        isAllDay || isImportant
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = isAllDay ? endTime.addingTimeInterval(-1) : endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let dayStart = Calendar.japanese.startOfDay(for: day)
        let dayEnd = Calendar.japanese.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

struct FriendSharedActivitySnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var categoryID: UUID?
    var title: String
    var startTime: Date
    var endTime: Date
    var categoryTitle: String
    var categoryIconName: String
    var categoryColorHex: String
    var note: String?
    var mood: String?
    var locationName: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        categoryTitle: String = "",
        categoryIconName: String = "circle.fill",
        categoryColorHex: String = "#2F80ED",
        note: String? = nil,
        mood: String? = nil,
        locationName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.categoryTitle = categoryTitle
        self.categoryIconName = categoryIconName
        self.categoryColorHex = categoryColorHex
        self.note = note
        self.mood = mood
        self.locationName = locationName
        self.updatedAt = updatedAt
    }

    init(chapter: Chapter, now: Date = Date()) {
        self.id = chapter.id
        self.categoryID = chapter.category?.id
        self.title = chapter.category?.name ?? "未分類"
        self.startTime = chapter.startTime
        self.endTime = max(chapter.endTime ?? now, chapter.startTime)
        self.categoryTitle = chapter.category?.name ?? "未分類"
        self.categoryIconName = chapter.category?.icon ?? "circle.fill"
        self.categoryColorHex = chapter.category?.colorHex ?? "#2F80ED"
        self.note = chapter.note
        self.mood = chapter.mood
        self.locationName = chapter.locationName
        self.updatedAt = chapter.updatedAt
    }

    static func snapshots(
        from chapters: [Chapter],
        now: Date = Date(),
        visibilityPreset: VisibilityPreset? = nil,
        recipientFriendID: UUID? = nil,
        acceptedFriendIDs: Set<UUID> = []
    ) -> [FriendSharedActivitySnapshot] {
        let policy = FriendSharingVisibilityPolicy(
            visibilityPreset: visibilityPreset,
            recipientFriendID: recipientFriendID,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )

        return chapters
            .compactMap { policy.snapshot(for: $0, now: now) }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.startTime < $1.startTime
            }
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let dayStart = Calendar.japanese.startOfDay(for: day)
        let dayEnd = Calendar.japanese.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

struct FriendSharedDailyScoreSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var dayStart: Date
    var dayIdentifier: String
    var score: Int
    var plannedDuration: TimeInterval
    var recordedDuration: TimeInterval
    var hasData: Bool
    var updatedAt: Date

    init(
        id: UUID? = nil,
        dayStart: Date,
        dayIdentifier: String,
        score: Int,
        plannedDuration: TimeInterval,
        recordedDuration: TimeInterval,
        hasData: Bool,
        updatedAt: Date = Date()
    ) {
        self.dayStart = dayStart
        self.dayIdentifier = dayIdentifier
        self.id = id ?? Self.stableID(for: dayIdentifier)
        self.score = score
        self.plannedDuration = plannedDuration
        self.recordedDuration = recordedDuration
        self.hasData = hasData
        self.updatedAt = updatedAt
    }

    init(summary: ScoreSummary, calendar: Calendar = .japanese, updatedAt: Date = Date()) {
        let dayStart = calendar.startOfDay(for: summary.date)
        let dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
        self.init(
            dayStart: dayStart,
            dayIdentifier: dayIdentifier,
            score: Int(summary.totalScore.rounded()),
            plannedDuration: summary.plannedDuration,
            recordedDuration: summary.recordedDuration,
            hasData: summary.plannedDuration > 0,
            updatedAt: updatedAt
        )
    }

    static func sourceID(for dayStart: Date, calendar: Calendar = .japanese) -> UUID {
        stableID(for: DailyCardSnapshot.dayIdentifier(for: calendar.startOfDay(for: dayStart), calendar: calendar))
    }

    private static func stableID(for dayIdentifier: String) -> UUID {
        let digest = SHA256.hash(data: Data("friend-shared-score:\(dayIdentifier)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let first32 = String(hex.prefix(32))
        let part1 = String(first32.prefix(8))
        let part2 = String(first32.dropFirst(8).prefix(4))
        let part3 = String(first32.dropFirst(12).prefix(4))
        let part4 = String(first32.dropFirst(16).prefix(4))
        let part5 = String(first32.dropFirst(20).prefix(12))
        let formatted = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"
        return UUID(uuidString: formatted) ?? UUID()
    }
}

private struct FriendSharingVisibilityPolicy {
    private static let redactedPlanTitle = "予定あり"
    private static let redactedPlanCategoryColorHex = "#8E8E93"

    private let publishMode: PublishMode
    private let publishingDisabled: Bool
    private let hideMoodAndNote: Bool
    private let hideLocation: Bool
    private let freeTimeOnly: Bool
    private let excludedCategoryIDs: Set<UUID>
    private let recipientFriendID: UUID?
    private let acceptedFriendIDs: Set<UUID>
    private let now: Date

    init(
        visibilityPreset: VisibilityPreset?,
        recipientFriendID: UUID? = nil,
        acceptedFriendIDs: Set<UUID> = [],
        now: Date = Date()
    ) {
        let publishMode = visibilityPreset?.publishMode ?? .realtime
        let level = visibilityPreset?.level ?? .all

        self.publishMode = publishMode
        self.publishingDisabled = publishMode == .none || level == .none
        self.hideMoodAndNote = visibilityPreset?.hideMoodAndNote ?? false
        self.hideLocation = visibilityPreset?.hideLocation ?? false
        self.freeTimeOnly = visibilityPreset?.freeTimeOnly ?? false
        self.excludedCategoryIDs = Set(visibilityPreset?.excludedCategoryIDs ?? [])
        self.recipientFriendID = recipientFriendID
        self.acceptedFriendIDs = acceptedFriendIDs
        self.now = now
    }

    func snapshot(for plan: PlanBlock) -> FriendSharedPlanSnapshot? {
        guard !publishingDisabled,
              isPublishableThroughTiming(endTime: plan.endTime),
              isVisible(
                isPublic: plan.isPublic,
                audienceFriendIDs: plan.audienceFriendIDs,
                hasAudienceSnapshot: plan.hasAudienceSnapshot
              ),
              !isExcluded(plan.category)
        else { return nil }

        var snapshot = FriendSharedPlanSnapshot(plan: plan)
        if freeTimeOnly {
            snapshot.categoryID = nil
            snapshot.title = Self.redactedPlanTitle
            snapshot.categoryTitle = ""
            snapshot.categoryIconName = "calendar"
            snapshot.categoryColorHex = Self.redactedPlanCategoryColorHex
        }
        return snapshot
    }

    func snapshot(for chapter: Chapter, now: Date) -> FriendSharedActivitySnapshot? {
        let effectiveEndTime = max(chapter.endTime ?? now, chapter.startTime)
        guard !publishingDisabled,
              isPublishableThroughTiming(endTime: effectiveEndTime),
              isVisible(
                isPublic: chapter.isPublic,
                audienceFriendIDs: chapter.audienceFriendIDs,
                hasAudienceSnapshot: chapter.hasAudienceSnapshot
              ),
              !isExcluded(chapter.category)
        else { return nil }

        var snapshot = FriendSharedActivitySnapshot(chapter: chapter, now: now)
        if hideMoodAndNote {
            snapshot.note = nil
            snapshot.mood = nil
        }
        if hideLocation {
            snapshot.locationName = nil
        }
        return snapshot
    }

    private func isPublishableThroughTiming(endTime: Date) -> Bool {
        switch publishMode {
        case .realtime:
            return true
        case .nextDay:
            let todayStart = Calendar.japanese.startOfDay(for: now)
            return endTime <= todayStart
        case .none:
            return false
        }
    }

    private func isExcluded(_ category: Category?) -> Bool {
        guard let category else { return false }
        return excludedCategoryIDs.contains(category.id)
    }

    private func isVisible(
        isPublic: Bool,
        audienceFriendIDs: [UUID],
        hasAudienceSnapshot: Bool
    ) -> Bool {
        guard let recipientFriendID else { return isPublic }
        return AudienceResolver.isFriendInAudience(
            isPublic: isPublic,
            audienceFriendIDs: audienceFriendIDs,
            hasAudienceSnapshot: hasAudienceSnapshot,
            friendID: recipientFriendID,
            acceptedFriendIDs: acceptedFriendIDs
        )
    }
}

private extension JSONEncoder {
    static var liminalog: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var liminalog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum FriendScorePeriod: String, CaseIterable, Identifiable {
    case day
    case today
    case yesterday
    case week
    case month
    case year

    var id: String { rawValue }

    static var detailCases: [FriendScorePeriod] {
        [.day, .week, .month, .year]
    }

    var label: String {
        switch self {
        case .day:
            "日間"
        case .today:
            "今日"
        case .yesterday:
            "昨日"
        case .week:
            "週間"
        case .month:
            "月間"
        case .year:
            "年間"
        }
    }
}

struct FriendInvitePayload: Equatable {
    static let scheme = "liminalog"
    static let host = "friend-invite"

    let code: String
    let displayName: String
    let username: String?

    init(code: String, displayName: String, username: String? = nil) {
        self.code = Self.normalizedCode(code)
        self.displayName = displayName
        self.username = username.flatMap(UserIDNormalizer.normalizedValue)
    }

    init(username: String, displayName: String) {
        let normalizedUsername = UserIDNormalizer.normalizedValue(username) ?? Self.normalizedCode(username).lowercased()
        self.code = Self.normalizedCode(normalizedUsername)
        self.displayName = displayName
        self.username = normalizedUsername
    }

    init?(url: URL) {
        guard
            url.scheme == Self.scheme,
            url.host == Self.host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !Self.normalizedCode(code).isEmpty
        else { return nil }

        let name = components.queryItems?.first(where: { $0.name == "name" })?.value ?? "Liminalogユーザー"
        let username = components.queryItems?.first(where: { $0.name == "username" })?.value
        self.init(code: code, displayName: name, username: username)
    }

    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let payload = FriendInvitePayload(url: url) {
            self = payload
            return
        }
        if trimmed.contains("://") {
            return nil
        }

        let code = Self.normalizedCode(trimmed)
        guard !code.isEmpty else { return nil }
        self.init(code: code, displayName: "Liminalogユーザー")
    }

    var url: URL {
        var queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "name", value: displayName)
        ]
        if let username {
            queryItems.append(URLQueryItem(name: "username", value: username))
        }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = queryItems
        return components.url!
    }

    var shareMessage: String {
        "\(displayName)さんからLiminalogの招待です"
    }

    static func code(from id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).uppercased()
    }

    static func normalizedCode(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }
}

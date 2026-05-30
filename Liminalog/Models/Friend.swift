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
    var avatarSystemImage: String = "person.crop.circle.fill"
    var accentColorHex: String = "#2F80ED"
    var profileBadgeID: String = "starter"
    var profileIconFrameID: String = "halo"
    var profileStreakIconID: String = "flame"
    var profileCardStyleID: String = "clean"
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
    var streakCount: Int = 0
    var sharedPlansJSON: String = "[]"
    var sharedActivitiesJSON: String = "[]"
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
        self.avatarSystemImage = avatarSystemImage
        self.accentColorHex = accentColorHex
        self.profileBadgeID = "starter"
        self.profileIconFrameID = "halo"
        self.profileStreakIconID = "flame"
        self.profileCardStyleID = "clean"
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
        self.streakCount = 0
        self.sharedPlansJSON = "[]"
        self.sharedActivitiesJSON = "[]"
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

    var sharedPlans: [FriendSharedPlanSnapshot] {
        guard let data = sharedPlansJSON.data(using: .utf8),
              let plans = try? JSONDecoder.liminalog.decode([FriendSharedPlanSnapshot].self, from: data)
        else { return [] }
        return plans
    }

    func setSharedPlans(_ plans: [FriendSharedPlanSnapshot]) {
        guard let data = try? JSONEncoder.liminalog.encode(plans),
              let json = String(data: data, encoding: .utf8)
        else { return }
        sharedPlansJSON = json
        updatedAt = Date()
    }

    var sharedActivities: [FriendSharedActivitySnapshot] {
        guard let data = sharedActivitiesJSON.data(using: .utf8),
              let activities = try? JSONDecoder.liminalog.decode([FriendSharedActivitySnapshot].self, from: data)
        else { return [] }
        return activities
    }

    func setSharedActivities(_ activities: [FriendSharedActivitySnapshot]) {
        guard let data = try? JSONEncoder.liminalog.encode(activities),
              let json = String(data: data, encoding: .utf8)
        else { return }
        sharedActivitiesJSON = json
        updatedAt = Date()
    }
}

struct FriendSharedPlanSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
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

    static func snapshots(from plans: [PlanBlock]) -> [FriendSharedPlanSnapshot] {
        plans
            .filter(\.isPublic)
            .map(FriendSharedPlanSnapshot.init(plan:))
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

    static func snapshots(from chapters: [Chapter], now: Date = Date()) -> [FriendSharedActivitySnapshot] {
        chapters
            .filter(\.isPublic)
            .map { FriendSharedActivitySnapshot(chapter: $0, now: now) }
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

    init(code: String, displayName: String) {
        self.code = Self.normalizedCode(code)
        self.displayName = displayName
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
        self.init(code: code, displayName: name)
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
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "name", value: displayName)
        ]
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

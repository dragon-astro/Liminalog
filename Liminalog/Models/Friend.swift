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
        self.lastSeenAt = nil
        self.acceptedAt = status == .accepted ? now : nil
        self.blockedAt = status == .blocked ? now : nil
        self.createdAt = now
        self.updatedAt = now
    }

    func score(for period: FriendScorePeriod) -> Double {
        switch period {
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

enum FriendScorePeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case week
    case month
    case year

    var id: String { rawValue }

    static var detailCases: [FriendScorePeriod] {
        [.week, .month, .year]
    }

    var label: String {
        switch self {
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
    let accentColorHex: String

    init(code: String, displayName: String, accentColorHex: String) {
        self.code = Self.normalizedCode(code)
        self.displayName = displayName
        self.accentColorHex = accentColorHex
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
        let color = components.queryItems?.first(where: { $0.name == "color" })?.value ?? "#2F80ED"
        self.init(code: code, displayName: name, accentColorHex: color)
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
        self.init(code: code, displayName: "Liminalogユーザー", accentColorHex: "#2F80ED")
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "name", value: displayName),
            URLQueryItem(name: "color", value: accentColorHex)
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

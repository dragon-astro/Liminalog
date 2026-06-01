import Foundation
import SwiftData

enum UnlockKind: String, Codable, CaseIterable, Identifiable {
    case theme
    case iconFrame
    case nameBadge
    case streakIcon
    case cardStyle
    case appIcon
    case stamp
    case barStyle
    case cardTemplate

    var id: String { rawValue }
}

@Model
final class UnlockItem {
    var id: UUID = UUID()
    var key: String = ""
    var kindRawValue: String = UnlockKind.theme.rawValue
    var requiredCumulativeScore: Int = 0
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

    var kind: UnlockKind {
        get { UnlockKind(rawValue: kindRawValue) ?? .theme }
        set { kindRawValue = newValue.rawValue }
    }

    init() {}

    init(seed: UnlockCatalogItem, now: Date = Date()) {
        self.id = UUID()
        self.key = seed.key
        self.kindRawValue = seed.kind.rawValue
        self.requiredCumulativeScore = seed.requiredCumulativeScore
        self.displayName = seed.displayName
        self.systemImageName = seed.systemImageName
        self.tintHex = seed.tintHex
        self.targetID = seed.targetID
        self.sortOrder = seed.sortOrder
        self.isBuiltIn = true
        self.createdAt = now
        self.updatedAt = now
    }
}

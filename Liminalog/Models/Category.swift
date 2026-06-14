import Foundation
import SwiftData
import SwiftUI

enum DailyCardCategoryIntent: String, Codable, CaseIterable, Identifiable {
    case neutral
    case increase
    case decrease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral:
            "中立"
        case .increase:
            "増やしたい"
        case .decrease:
            "減らしたい"
        }
    }
}

enum CategoryAnalysisKind: String, Codable, CaseIterable, Identifiable {
    case unspecified
    case sleep
    case work
    case study
    case hobbyPlay
    case exercise
    case household

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified:
            "未指定"
        case .sleep:
            "睡眠"
        case .work:
            "仕事"
        case .study:
            "勉強"
        case .hobbyPlay:
            "趣味・遊び"
        case .exercise:
            "運動"
        case .household:
            "家事・生活"
        }
    }
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
    var analysisKindRawValue: String = CategoryAnalysisKind.unspecified.rawValue
    var isDailyCardSleepCategory: Bool = false
    var defaultAudienceFriendSetIDs: [UUID] = []
    var defaultAudienceIncludedFriendIDs: [UUID] = []
    var defaultAudienceExcludedFriendIDs: [UUID] = []
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    var chapters: [Chapter]? = []

    @Relationship(deleteRule: .nullify, inverse: \PlanBlock.category)
    var plans: [PlanBlock]? = []

    var color: Color { Color.cachedHex(colorHex) }
    var displayColor: Color { Color.cachedDisplayHex(colorHex) }
    var dailyCardIntent: DailyCardCategoryIntent {
        get { DailyCardCategoryIntent(rawValue: dailyCardIntentRawValue) ?? .neutral }
        set { dailyCardIntentRawValue = newValue.rawValue }
    }
    var analysisKind: CategoryAnalysisKind {
        get {
            if let kind = CategoryAnalysisKind(rawValue: analysisKindRawValue), kind != .unspecified {
                return kind
            }
            return isDailyCardSleepCategory ? .sleep : .unspecified
        }
        set {
            analysisKindRawValue = newValue.rawValue
            isDailyCardSleepCategory = newValue == .sleep
        }
    }

    init() {}

    init(
        name: String,
        colorHex: String,
        icon: String? = nil,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        analysisKind: CategoryAnalysisKind = .unspecified,
        isDailyCardSleepCategory: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.dailyCardIntentRawValue = dailyCardIntent.rawValue
        let resolvedAnalysisKind = analysisKind == .unspecified && isDailyCardSleepCategory ? CategoryAnalysisKind.sleep : analysisKind
        self.analysisKindRawValue = resolvedAnalysisKind.rawValue
        self.isDailyCardSleepCategory = resolvedAnalysisKind == .sleep
        self.defaultAudienceFriendSetIDs = []
        self.defaultAudienceIncludedFriendIDs = []
        self.defaultAudienceExcludedFriendIDs = []
        self.createdAt = Date()
        self.chapters = []
        self.plans = []
    }
}

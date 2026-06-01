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

    init() {}

    init(
        name: String,
        colorHex: String,
        icon: String? = nil,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        isDailyCardSleepCategory: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.dailyCardIntentRawValue = dailyCardIntent.rawValue
        self.isDailyCardSleepCategory = isDailyCardSleepCategory
        self.createdAt = Date()
        self.chapters = []
        self.plans = []
    }
}

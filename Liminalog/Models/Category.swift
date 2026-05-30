import Foundation
import SwiftData
import SwiftUI

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var icon: String?
    var sortOrder: Int = 0
    var isDefault: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    var chapters: [Chapter]? = []

    @Relationship(deleteRule: .nullify, inverse: \PlanBlock.category)
    var plans: [PlanBlock]? = []

    var color: Color { Color.cachedHex(colorHex) }

    init() {}

    init(name: String, colorHex: String, icon: String? = nil, sortOrder: Int = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = Date()
        self.chapters = []
        self.plans = []
    }
}

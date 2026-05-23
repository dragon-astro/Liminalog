import Foundation
import SwiftData
import SwiftUI

@Model
final class Category {
    var id: UUID
    var name: String
    var colorHex: String
    var icon: String?
    var sortOrder: Int
    var usageCount: Int = 0
    var isDefault: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    var chapters: [Chapter]

    var color: Color { Color(hex: colorHex) }
    var totalUsageCount: Int { max(usageCount, chapters.count) }

    init(name: String, colorHex: String, icon: String? = nil, sortOrder: Int = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.usageCount = 0
        self.isDefault = isDefault
        self.createdAt = Date()
        self.chapters = []
    }
}

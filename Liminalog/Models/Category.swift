import Foundation
import SwiftData
import SwiftUI

@Model
final class Category {
    var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var isDefault: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    var chapters: [Chapter]

    var color: Color { Color(hex: colorHex) }
    var usageCount: Int { chapters.count }

    init(name: String, colorHex: String, sortOrder: Int = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.createdAt = Date()
        self.chapters = []
    }
}

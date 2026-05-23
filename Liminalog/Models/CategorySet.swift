import Foundation
import SwiftData

@Model
final class CategorySet {
    var id: UUID
    var name: String
    var sortOrder: Int
    var categoryIDs: [UUID]
    var createdAt: Date

    init(name: String, sortOrder: Int = 0, categoryIDs: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.categoryIDs = Array(categoryIDs.prefix(8))
        self.createdAt = Date()
    }
}

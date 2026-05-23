import Foundation
import SwiftData

@Model
final class PlanBlock {
    var id: UUID
    var category: Category?
    var title: String
    var startTime: Date
    var endTime: Date
    var isAllDay: Bool
    var note: String?
    var isPublic: Bool
    var createdAt: Date

    var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 0)
    }

    init(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, note: String? = nil, isPublic: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.note = note
        self.isPublic = isPublic
        self.createdAt = Date()
    }
}

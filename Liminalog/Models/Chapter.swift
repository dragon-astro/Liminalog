import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID
    var category: Category?
    var startTime: Date
    var endTime: Date?
    var note: String?
    var mood: String?
    var createdAt: Date

    var isActive: Bool { endTime == nil }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var durationLive: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    init(category: Category, startTime: Date = Date()) {
        self.id = UUID()
        self.category = category
        self.startTime = startTime
        self.endTime = nil
        self.note = nil
        self.mood = nil
        self.createdAt = Date()
    }
}

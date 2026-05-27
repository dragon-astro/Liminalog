import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID = UUID()
    var category: Category?
    var startTime: Date = Date()
    var endTime: Date?
    var note: String?
    var mood: String?
    var photoLocalIdentifier: String?
    var thumbnailData: Data?
    var locationName: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var isActive: Bool { endTime == nil }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var durationLive: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    init() {}

    init(category: Category, startTime: Date = Date()) {
        self.id = UUID()
        self.category = category
        self.startTime = startTime
        self.endTime = nil
        self.note = nil
        self.mood = nil
        self.photoLocalIdentifier = nil
        self.thumbnailData = nil
        self.locationName = nil
        self.isPublic = true
        self.visibilityScope = .all
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

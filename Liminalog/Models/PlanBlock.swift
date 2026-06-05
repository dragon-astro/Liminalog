import Foundation
import SwiftData

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var category: Category?
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var audienceFriendIDs: [UUID] = []
    var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
    var hasAudienceSnapshot: Bool = false
    var sourceEventID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 0)
    }

    init() {}

    init(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, isImportant: Bool = false, note: String? = nil, isPublic: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.isImportant = isImportant
        self.note = note
        self.isPublic = isPublic
        self.visibilityScope = .all
        self.audienceFriendIDs = []
        self.audienceSourceRawValue = AudienceSource.categoryDefaultSnapshot.rawValue
        self.hasAudienceSnapshot = false
        self.sourceEventID = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var audienceSource: AudienceSource {
        get { AudienceSource(rawValue: audienceSourceRawValue) ?? .categoryDefaultSnapshot }
        set { audienceSourceRawValue = newValue.rawValue }
    }
}

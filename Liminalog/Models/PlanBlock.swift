import Foundation
import SwiftData

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var category: Category?
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isMemo: Bool = false
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var locationName: String?
    var urlString: String?
    var note: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var audienceFriendIDs: [UUID] = []
    var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
    var hasAudienceSnapshot: Bool = false
    var reminderMinutesBefore: Int?
    var reminderDate: Date?
    var recurrenceSeriesID: UUID?
    var sourceEventID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var duration: TimeInterval {
        max(endTime.timeIntervalSince(startTime), 0)
    }

    /// Showcase plans use the source field as a seed marker, not an EventKit ID.
    var hasExternalCalendarSource: Bool {
        guard let sourceEventID else { return false }
        return !sourceEventID.hasPrefix("debug.preview.")
    }

    init() {}

    init(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, isMemo: Bool = false, isImportant: Bool = false, note: String? = nil, locationName: String? = nil, urlString: String? = nil, isPublic: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isMemo = isMemo
        self.isAllDay = isAllDay
        self.isImportant = isImportant
        self.locationName = PlanExtraDetails.normalized(locationName)
        self.urlString = PlanExtraDetails.normalized(urlString)
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

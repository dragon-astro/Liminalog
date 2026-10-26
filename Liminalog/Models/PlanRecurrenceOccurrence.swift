import Foundation
import SwiftData

/// Kept when an occurrence is deleted, so automatic filling never recreates it.
@Model
final class PlanRecurrenceOccurrence {
    var id: UUID = UUID()
    var seriesID: UUID = UUID()
    var itemID: UUID = UUID()
    var day: Date = Date()
    var planID: UUID?
    var baselineData: Data?
    var isBlocked: Bool = false
    var createdAt: Date = Date()

    init(seriesID: UUID, itemID: UUID, day: Date) {
        self.seriesID = seriesID
        self.itemID = itemID
        self.day = day
    }
}

struct PlanRecurrenceBaseline: Codable, Equatable {
    let title: String
    let categoryID: UUID?
    let start: Date
    let end: Date
    private var memo: Bool? = nil
    let isAllDay: Bool
    let isImportant: Bool
    let locationName: String?
    let urlString: String?
    let note: String?
    let isPublic: Bool
    let reminder: Int?
    var reminderDate: Date? = nil
    let audienceSource: String
    let hasAudienceSnapshot: Bool
    let audienceIDs: [UUID]

    init(_ plan: PlanBlock) {
        title = plan.title; categoryID = plan.category?.id
        start = plan.startTime; end = plan.endTime
        memo = plan.isMemo ? true : nil
        isAllDay = plan.isAllDay; isImportant = plan.isImportant
        locationName = plan.locationName; urlString = plan.urlString
        note = plan.note; isPublic = plan.isPublic; reminder = plan.reminderMinutesBefore
        reminderDate = plan.reminderDate
        audienceSource = plan.audienceSource.rawValue
        hasAudienceSnapshot = plan.hasAudienceSnapshot
        audienceIDs = plan.audienceFriendIDs.sorted { $0.uuidString < $1.uuidString }
    }
    var data: Data? { try? JSONEncoder().encode(self) }
    func matches(_ data: Data?) -> Bool {
        guard let data, let previous = try? JSONDecoder().decode(Self.self, from: data) else { return false }
        return self == previous
    }
}

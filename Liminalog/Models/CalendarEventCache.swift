import Foundation
import SwiftData

@Model
final class CalendarEventCache {
    var id: UUID = UUID()
    var eventIdentifier: String = ""
    var calendarIdentifier: String = ""
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var colorHex: String?
    var lastSyncedAt: Date = Date()

    init() {}
}

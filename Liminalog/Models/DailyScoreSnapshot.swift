import Foundation
import SwiftData

@Model
final class DailyScoreSnapshot {
    var id: UUID = UUID()
    var dayStart: Date = Date.distantPast
    var dayIdentifier: String = ""
    var score: Int = 0
    var plannedDuration: TimeInterval = 0
    var recordedDuration: TimeInterval = 0
    var hasRecord: Bool = false
    var earlyRecordDay: Bool = false
    var lateNightRecordDay: Bool = false
    var categoryIDs: [UUID] = []
    var planMatchedDay: Bool = false
    var chargeDay: Bool = false
    var morningPersonaDay: Bool = false
    var nightPersonaDay: Bool = false
    var recordingHabitDay: Bool = false
    var personalBestDay: Bool = false
    var returnAfterGapDay: Bool = false
    var firstRecordDay: Bool = false
    var balancedDay: Bool = false
    var focusedDay: Bool = false
    var changeSignalDay: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}
}

extension DailyScoreSnapshot {
    var shouldDisplayAsDailyCard: Bool {
        hasRecord || recordedDuration > 0 || plannedDuration > 0 || score > 0
    }
}

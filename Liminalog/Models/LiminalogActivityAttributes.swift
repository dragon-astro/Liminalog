import Foundation
import ActivityKit

struct LiminalogActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var categoryName: String?
        var colorHex: String
        var icon: String?
        var startedAt: Date?
        var isPublic: Bool
        var categorySetName: String

        var isRecording: Bool {
            categoryName != nil && startedAt != nil
        }
    }

    var id: String = "liminalog-current-status"
}

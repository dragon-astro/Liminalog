import Foundation
import ActivityKit

struct LiminalogActivityAttributes: ActivityAttributes {
    public struct IslandCategory: Codable, Hashable, Identifiable {
        var id: UUID
        var name: String
        var colorHex: String
        var icon: String?
    }

    public struct ContentState: Codable, Hashable {
        var activeCategoryID: UUID?
        var categoryName: String?
        var colorHex: String
        var icon: String?
        var startedAt: Date?
        var isPublic: Bool
        var categorySetName: String
        var categories: [IslandCategory]

        var isRecording: Bool {
            categoryName != nil && startedAt != nil
        }
    }

    var id: String = "liminalog-current-status"
}

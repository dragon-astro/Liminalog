import Foundation
import SwiftData

enum VisibilityLevel: String, Codable {
    case all, partial, none
}

@Model
final class VisibilityPreset {
    var id: UUID
    var name: String
    var level: VisibilityLevel

    init(name: String, level: VisibilityLevel) {
        self.id = UUID()
        self.name = name
        self.level = level
    }
}

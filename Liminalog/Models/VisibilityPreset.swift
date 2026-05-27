import Foundation
import SwiftData

enum VisibilityLevel: String, Codable {
    case all, partial, none
}

@Model
final class VisibilityPreset {
    var id: UUID = UUID()
    var name: String = ""
    var level: VisibilityLevel = VisibilityLevel.all
    var builtInKey: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(name: String, level: VisibilityLevel) {
        self.id = UUID()
        self.name = name
        self.level = level
        self.builtInKey = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

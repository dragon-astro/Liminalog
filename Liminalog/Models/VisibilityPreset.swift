import Foundation
import SwiftData

enum VisibilityLevel: String, Codable {
    case all, partial, none
}

enum PublishMode: String, Codable, CaseIterable, Identifiable {
    case realtime
    case nextDay
    case none

    var id: String { rawValue }
}

@Model
final class VisibilityPreset {
    var id: UUID = UUID()
    var name: String = ""
    /// Legacy coarse level kept for migration/backward compatibility. New UI should prefer `publishMode` + detail flags.
    var level: VisibilityLevel = VisibilityLevel.all
    var builtInKey: String?
    var isBuiltIn: Bool = false
    var sortOrder: Int = 0
    var publishModeRawValue: String = PublishMode.realtime.rawValue
    var hideMoodAndNote: Bool = false
    var hidePhoto: Bool = true
    var hideLocation: Bool = true
    var excludedCategoryIDs: [UUID] = []
    var freeTimeOnly: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var publishMode: PublishMode {
        get { PublishMode(rawValue: publishModeRawValue) ?? .realtime }
        set {
            publishModeRawValue = newValue.rawValue
            level = newValue == .none ? .none : level
        }
    }

    init() {}

    init(
        name: String,
        level: VisibilityLevel = .all,
        builtInKey: String? = nil,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        publishMode: PublishMode = .realtime,
        hideMoodAndNote: Bool = false,
        hidePhoto: Bool = true,
        hideLocation: Bool = true,
        excludedCategoryIDs: [UUID] = [],
        freeTimeOnly: Bool = false,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.level = level
        self.builtInKey = builtInKey
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.publishModeRawValue = publishMode.rawValue
        self.hideMoodAndNote = hideMoodAndNote
        self.hidePhoto = hidePhoto
        self.hideLocation = hideLocation
        self.excludedCategoryIDs = excludedCategoryIDs
        self.freeTimeOnly = freeTimeOnly
        self.createdAt = now
        self.updatedAt = now
    }
}

enum VisibilityPresetCustomization {
    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let customizedPresetIDsKey = "visibilityPresets.customizedDetailIDs"

    static func isCustomized(_ presetID: UUID, defaults: UserDefaults = defaultDefaults) -> Bool {
        Set(defaults.stringArray(forKey: customizedPresetIDsKey) ?? []).contains(presetID.uuidString)
    }

    static func markCustomized(_ presetID: UUID, defaults: UserDefaults = defaultDefaults) {
        var ids = Set(defaults.stringArray(forKey: customizedPresetIDsKey) ?? [])
        ids.insert(presetID.uuidString)
        defaults.set(Array(ids).sorted(), forKey: customizedPresetIDsKey)
    }

    private static var defaultDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

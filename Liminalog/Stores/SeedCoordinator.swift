import Foundation
import SwiftData

@MainActor
enum SeedCoordinator {
    @discardableResult
    static func ensureUserSettings(in context: ModelContext, now: Date = Date()) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.settingsKey == "default" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let settings = (try? context.fetch(descriptor)) ?? []

        guard let primary = settings.first else {
            let created = UserSettings()
            created.createdAt = now
            created.updatedAt = now
            context.insert(created)
            try? context.save()
            return created
        }

        for duplicate in settings.dropFirst() {
            merge(duplicate, into: primary)
            context.delete(duplicate)
        }

        if settings.count > 1 {
            primary.updatedAt = now
            try? context.save()
        }

        return primary
    }

    static func consolidateBuiltInVisibilityPresets(in context: ModelContext, now: Date = Date()) {
        let descriptor = FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let presets = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: presets) { $0.builtInKey ?? $0.name }
        var didChange = false

        for group in grouped.values where group.count > 1 {
            guard let primary = group.first else { continue }
            for duplicate in group.dropFirst() {
                if primary.name.isEmpty {
                    primary.name = duplicate.name
                }
                context.delete(duplicate)
                didChange = true
            }
            primary.updatedAt = now
        }

        if didChange {
            try? context.save()
        }
    }

    private static func merge(_ duplicate: UserSettings, into primary: UserSettings) {
        if primary.themeName == "default", duplicate.themeName != "default" {
            primary.themeName = duplicate.themeName
        }
        if primary.enabledCategorySetID == nil {
            primary.enabledCategorySetID = duplicate.enabledCategorySetID
        }
        if !primary.calendarSyncEnabled {
            primary.calendarSyncEnabled = duplicate.calendarSyncEnabled
        }
        if primary.dashboardCardOrder.isEmpty {
            primary.dashboardCardOrder = duplicate.dashboardCardOrder
        }
        primary.showCalendarOverlay = primary.showCalendarOverlay || duplicate.showCalendarOverlay
        primary.defaultVisibility = newer(primary: primary, duplicate: duplicate).defaultVisibility
    }

    private static func newer(primary: UserSettings, duplicate: UserSettings) -> UserSettings {
        duplicate.updatedAt > primary.updatedAt ? duplicate : primary
    }
}

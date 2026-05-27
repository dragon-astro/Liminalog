import Foundation
import SwiftData

enum SharedModelContainer {
    static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    static let cloudKitContainerID = "iCloud.app.YasudaRyuga.Liminalog"

    static let shared: ModelContainer = {
        do {
            return try appGroupCloud()
        } catch {
            NSLog("Liminalog: falling back to local-only ModelContainer because shared Cloud container failed: \(String(describing: error))")
            do {
                return try localOnly()
            } catch {
                fatalError("Failed to create local ModelContainer: \(error)")
            }
        }
    }()

    static var cloudSchema: Schema {
        Schema([
            Category.self,
            CategorySet.self,
            Chapter.self,
            PlanBlock.self,
            VisibilityPreset.self,
            UserSettings.self
        ])
    }

    static var localCacheSchema: Schema {
        Schema([
            CalendarEventCache.self
        ])
    }

    static var schema: Schema {
        Schema([
            Category.self,
            CategorySet.self,
            Chapter.self,
            PlanBlock.self,
            VisibilityPreset.self,
            UserSettings.self,
            CalendarEventCache.self
        ])
    }

    static func localOnly() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Local",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func appGroupCloud() throws -> ModelContainer {
        let cloudConfiguration = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        let localCacheConfiguration = ModelConfiguration(
            "LocalCache",
            schema: localCacheSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [cloudConfiguration, localCacheConfiguration]
        )
    }
}

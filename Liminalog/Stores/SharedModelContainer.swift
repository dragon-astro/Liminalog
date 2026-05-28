import Foundation
import SwiftData

enum SharedModelContainer {
    static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    static let cloudKitContainerID = "iCloud.app.YasudaRyuga.Liminalog"
    private static let developmentStoreVersionKey = "development.storeVersion"
    private static let currentDevelopmentStoreVersion = 2026052902

    static let shared: ModelContainer = {
        do {
            return try appGroupCloud()
        } catch {
            NSLog("Liminalog: falling back to local-only ModelContainer because shared Cloud container failed: \(String(describing: error))")
            do {
                return try localOnly()
            } catch {
                NSLog("Liminalog: falling back to in-memory ModelContainer because local ModelContainer failed: \(String(describing: error))")
                do {
                    return try inMemory()
                } catch {
                    let message = "Liminalog: failed to create any ModelContainer: \(String(describing: error))"
                    NSLog("%@", message)
                    return try! inMemory()
                }
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
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "InMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func appGroupCloud() throws -> ModelContainer {
        prepareDevelopmentStoresIfNeeded()

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

    private static func prepareDevelopmentStoresIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let defaults = UserDefaults(suiteName: appGroupID),
              defaults.integer(forKey: developmentStoreVersionKey) != currentDevelopmentStoreVersion
        else { return }

        resetDevelopmentStores()
        defaults.set(currentDevelopmentStoreVersion, forKey: developmentStoreVersionKey)
        defaults.synchronize()
        #endif
    }

    private static func resetDevelopmentStores() {
        #if DEBUG
        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let supportURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let storeNames = [
            "Cloud.store",
            "Local.store",
            "LocalCache.store"
        ]
        let suffixes = ["", "-shm", "-wal"]

        for storeName in storeNames {
            for suffix in suffixes {
                let url = supportURL.appendingPathComponent(storeName + suffix)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    NSLog("Liminalog: failed to remove development store file \(url.lastPathComponent): \(String(describing: error))")
                }
            }
        }

        let cloudSupportURL = supportURL.appendingPathComponent(".Cloud_SUPPORT", isDirectory: true)
        if FileManager.default.fileExists(atPath: cloudSupportURL.path) {
            do {
                try FileManager.default.removeItem(at: cloudSupportURL)
            } catch {
                NSLog("Liminalog: failed to remove development CloudKit support directory: \(String(describing: error))")
            }
        }

        if let defaults = UserDefaults(suiteName: appGroupID) {
            [
                "recording.activeCategoryID",
                "recording.pendingCategoryID",
                "recording.enabledCategorySetID",
                "recording.surfaceSnapshot"
            ].forEach { defaults.removeObject(forKey: $0) }
            defaults.synchronize()
        }

        NSLog("Liminalog: reset development SwiftData stores for schema version \(currentDevelopmentStoreVersion)")
        #endif
    }
}

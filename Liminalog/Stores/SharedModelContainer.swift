import Foundation
import SQLite3
import SwiftData

enum SharedModelContainer {
    static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    static let cloudKitContainerID = "iCloud.app.YasudaRyuga.Liminalog"
    private static let developmentStoreVersionKey = "development.storeVersion"
    private static let developmentStoreResetRequestedKey = "development.resetStoreOnNextLaunch"
    private static let currentDevelopmentStoreVersion = 2026060701
    private static let requiredDevelopmentStoreColumns: [(table: String, columns: [String])] = [
        ("ZCATEGORY", ["ZDAILYCARDINTENTRAWVALUE", "ZISDAILYCARDSLEEPCATEGORY", "ZDEFAULTAUDIENCEFRIENDSETIDS", "ZDEFAULTAUDIENCEINCLUDEDFRIENDIDS", "ZDEFAULTAUDIENCEEXCLUDEDFRIENDIDS"]),
        ("ZCHAPTER", ["ZAUDIENCEFRIENDIDS", "ZAUDIENCESOURCERAWVALUE", "ZHASAUDIENCESNAPSHOT"]),
        ("ZPLANBLOCK", ["ZAUDIENCEFRIENDIDS", "ZAUDIENCESOURCERAWVALUE", "ZHASAUDIENCESNAPSHOT"]),
        ("ZUSERSETTINGS", ["ZPROFILEACCENTCOLORHEX", "ZPROFILEBADGEID", "ZPROFILEICONFRAMEID", "ZPROFILESTREAKICONID", "ZPROFILECARDSTYLEID", "ZCLOUDUSERNAME", "ZCLOUDUSERNAMENORMALIZED", "ZCLOUDUSERRECORDNAME", "ZCLOUDUSERNAMEREGISTEREDAT", "ZDASHBOARDHIDDENCARDKEYS", "ZDIDSEEDINITIALFRIENDSETS"]),
        ("ZFRIEND", ["ZSTATUSRAWVALUE", "ZPROFILEBADGEID", "ZPROFILEICONFRAMEID", "ZPROFILESTREAKICONID", "ZPROFILECARDSTYLEID", "ZSTREAKCOUNT", "ZMONTHSCORE", "ZYEARSCORE", "ZSHAREDPLANSJSON", "ZSHAREDACTIVITIESJSON"]),
        ("ZFRIENDSET", ["ZNAME", "ZMEMBERFRIENDIDS", "ZSORTORDER"]),
        ("ZFRIENDCATEGORYMAPPING", ["ZMYCATEGORYID", "ZFRIENDCATEGORYID", "ZUSEUNIFIEDCOLOR"]),
        ("ZDAILYCARDSNAPSHOT", ["ZDAYIDENTIFIER", "ZPERSONAKINDRAWVALUE", "ZTITLE", "ZFACTPAYLOADJSON", "ZCATEGORYPAYLOADJSON"]),
        ("ZUNLOCKITEM", ["ZKEY", "ZKINDRAWVALUE", "ZREQUIREDCUMULATIVESCORE", "ZREQUIREMENTKINDRAWVALUE", "ZREQUIREDVALUE", "ZTARGETID", "ZISBUILTIN"]),
        ("ZVISIBILITYPRESET", ["ZISBUILTIN", "ZSORTORDER", "ZPUBLISHMODERAWVALUE", "ZHIDEMOODANDNOTE", "ZHIDEPHOTO", "ZHIDELOCATION", "ZEXCLUDEDCATEGORYIDS", "ZFREETIMEONLY"])
    ]

    static let shared: ModelContainer = {
        do {
            return try appGroupCloud()
        } catch {
            NSLog("Liminalog: falling back to local-only ModelContainer because shared Cloud container failed: \(String(describing: error))")
            do {
                return try appGroupLocalOnly()
            } catch {
                NSLog("Liminalog: falling back to app-local ModelContainer because app group local ModelContainer failed: \(String(describing: error))")
                do {
                    return try localOnly()
                } catch {
                    NSLog("Liminalog: falling back to in-memory ModelContainer because app-local ModelContainer failed: \(String(describing: error))")
                    do {
                        return try inMemory()
                    } catch {
                        let message = "Liminalog: failed to create any ModelContainer: \(String(describing: error))"
                        NSLog("%@", message)
                        return try! inMemory()
                    }
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
            UnlockItem.self,
            VisibilityPreset.self,
            UserSettings.self,
            Friend.self,
            FriendSet.self,
            FriendCategoryMapping.self,
            DailyCardSnapshot.self
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
            UnlockItem.self,
            VisibilityPreset.self,
            UserSettings.self,
            Friend.self,
            FriendSet.self,
            FriendCategoryMapping.self,
            DailyCardSnapshot.self,
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

    static func appGroupLocalOnly() throws -> ModelContainer {
        prepareDevelopmentStoresIfNeeded()

        let cloudConfiguration = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
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
              let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
              )
        else { return }

        let supportURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        guard developmentStoreResetWasRequested(defaults: defaults) else {
            if defaults.integer(forKey: developmentStoreVersionKey) != currentDevelopmentStoreVersion {
                defaults.set(currentDevelopmentStoreVersion, forKey: developmentStoreVersionKey)
                defaults.synchronize()
            }
            return
        }

        resetDevelopmentStores(supportURL: supportURL)
        defaults.removeObject(forKey: developmentStoreResetRequestedKey)
        defaults.set(currentDevelopmentStoreVersion, forKey: developmentStoreVersionKey)
        defaults.synchronize()
        #endif
    }

    private static func developmentStoreResetWasRequested(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: developmentStoreResetRequestedKey) ||
            ProcessInfo.processInfo.arguments.contains("-LiminalogResetDevelopmentStore")
    }

    private static func developmentStoreNeedsReset(defaults: UserDefaults, supportURL: URL) -> Bool {
        defaults.integer(forKey: developmentStoreVersionKey) != currentDevelopmentStoreVersion ||
            developmentCloudStoreIsMissingRequiredMarkers(supportURL: supportURL)
    }

    private static func developmentCloudStoreIsMissingRequiredMarkers(supportURL: URL) -> Bool {
        let cloudStoreURL = supportURL.appendingPathComponent("Cloud.store")
        guard FileManager.default.fileExists(atPath: cloudStoreURL.path) else { return false }

        return requiredDevelopmentStoreColumns.contains { requirement in
            !developmentStore(
                at: cloudStoreURL,
                hasColumns: requirement.columns,
                inTable: requirement.table
            )
        }
    }

    private static func developmentStore(
        at storeURL: URL,
        hasColumns requiredColumns: [String],
        inTable tableName: String
    ) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return false
        }
        defer {
            sqlite3_close(database)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(tableName))", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }
        defer {
            sqlite3_finalize(statement)
        }

        var columnNames = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let columnText = sqlite3_column_text(statement, 1) else { continue }
            columnNames.insert(String(cString: columnText))
        }

        return requiredColumns.allSatisfy { columnNames.contains($0) }
    }

    private static func resetDevelopmentStores(supportURL: URL) {
        #if DEBUG
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
                "recording.surfaceSnapshot",
                "recording.widget.mediumCategorySetMode",
                "recording.widget.mediumCategorySetID"
            ].forEach { defaults.removeObject(forKey: $0) }
            (0..<4).forEach { defaults.removeObject(forKey: "recording.widget.smallCategoryID.\($0)") }
            defaults.synchronize()
        }

        NSLog("Liminalog: reset development SwiftData stores for schema version \(currentDevelopmentStoreVersion)")
        #endif
    }
}

import CloudKit
import Foundation
import SQLite3
import SwiftData

enum SharedModelContainer {
    static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    static let cloudKitContainerID = "iCloud.app.YasudaRyuga.Liminalog"
    private static let developmentStoreVersionKey = "development.storeVersion"
    private static let developmentStoreResetRequestedKey = "development.resetStoreOnNextLaunch"
    private static let currentDevelopmentStoreVersion = 2026061302
    private static var cloudStoreConfigurationName: String {
        #if DEBUG
        "CloudDevelopment\(currentDevelopmentStoreVersion)"
        #else
        "Cloud"
        #endif
    }
    private static var localCacheStoreConfigurationName: String {
        #if DEBUG
        "LocalCacheDevelopment\(currentDevelopmentStoreVersion)"
        #else
        "LocalCache"
        #endif
    }
    private static let requiredDevelopmentStoreColumns: [(table: String, columns: [String])] = [
        ("ZCATEGORY", ["ZDAILYCARDINTENTRAWVALUE", "ZISDAILYCARDSLEEPCATEGORY", "ZDEFAULTAUDIENCEFRIENDSETIDS", "ZDEFAULTAUDIENCEINCLUDEDFRIENDIDS", "ZDEFAULTAUDIENCEEXCLUDEDFRIENDIDS"]),
        ("ZCHAPTER", ["ZAUDIENCEFRIENDIDS", "ZAUDIENCESOURCERAWVALUE", "ZHASAUDIENCESNAPSHOT"]),
        ("ZPLANBLOCK", ["ZAUDIENCEFRIENDIDS", "ZAUDIENCESOURCERAWVALUE", "ZHASAUDIENCESNAPSHOT"]),
        ("ZUSERSETTINGS", ["ZPROFILEACCENTCOLORHEX", "ZPROFILEBADGEID", "ZPROFILEICONFRAMEID", "ZPROFILESTREAKICONID", "ZPROFILECARDSTYLEID", "ZCLOUDUSERNAME", "ZCLOUDUSERNAMENORMALIZED", "ZCLOUDUSERRECORDNAME", "ZCLOUDUSERNAMEREGISTEREDAT", "ZDASHBOARDHIDDENCARDKEYS", "ZDIDSEEDINITIALFRIENDSETS", "ZFINALIZEDCUMULATIVESCORE", "ZISFINALIZEDSCORELEDGERINITIALIZED", "ZFINALIZEDSCORERECONCILEDTHROUGHDAYSTART"]),
        ("ZFRIEND", ["ZSTATUSRAWVALUE", "ZPROFILEBADGEID", "ZPROFILEICONFRAMEID", "ZPROFILESTREAKICONID", "ZPROFILECARDSTYLEID", "ZSTREAKCOUNT", "ZMONTHSCORE", "ZYEARSCORE", "ZSHAREDPLANSJSON", "ZSHAREDACTIVITIESJSON"]),
        ("ZFRIENDSET", ["ZNAME", "ZMEMBERFRIENDIDS", "ZSORTORDER"]),
        ("ZFRIENDCATEGORYMAPPING", ["ZMYCATEGORYID", "ZFRIENDCATEGORYID", "ZUSEUNIFIEDCOLOR"]),
        ("ZDAILYCARDSNAPSHOT", ["ZDAYIDENTIFIER", "ZPERSONAKINDRAWVALUE", "ZTITLE", "ZFACTPAYLOADJSON", "ZCATEGORYPAYLOADJSON"]),
        ("ZDAILYSCORESNAPSHOT", ["ZDAYIDENTIFIER", "ZSCORE", "ZPLANNEDDURATION", "ZRECORDEDDURATION", "ZHASRECORD", "ZEARLYRECORDDAY", "ZLATENIGHTRECORDDAY", "ZCATEGORYIDS", "ZPLANMATCHEDDAY", "ZCHARGEDAY", "ZMORNINGPERSONADAY", "ZNIGHTPERSONADAY", "ZRECORDINGHABITDAY", "ZPERSONALBESTDAY", "ZRETURNAFTERGAPDAY", "ZFIRSTRECORDDAY", "ZBALANCEDDAY", "ZFOCUSEDDAY", "ZCHANGESIGNALDAY"]),
        ("ZUNLOCKITEM", ["ZKEY", "ZKINDRAWVALUE", "ZREQUIREDCUMULATIVESCORE", "ZREQUIREMENTKINDRAWVALUE", "ZREQUIREDVALUE", "ZTARGETID", "ZISBUILTIN"]),
        ("ZVISIBILITYPRESET", ["ZISBUILTIN", "ZSORTORDER", "ZPUBLISHMODERAWVALUE", "ZHIDEMOODANDNOTE", "ZHIDEPHOTO", "ZHIDELOCATION", "ZEXCLUDEDCATEGORYIDS", "ZFREETIMEONLY"])
    ]
    private static let requiredDevelopmentLocalCacheStoreColumns: [(table: String, columns: [String])] = [
        ("ZCALENDAREVENTCACHE", ["ZEVENTIDENTIFIER", "ZCALENDARIDENTIFIER", "ZTITLE", "ZSTARTTIME", "ZENDTIME"]),
        ("ZFRIENDSHAREDPLANRECORD", ["ZFRIENDID", "ZSOURCEID", "ZTITLE", "ZSTARTTIME", "ZENDTIME", "ZUPDATEDAT"]),
        ("ZFRIENDSHAREDCHAPTERRECORD", ["ZFRIENDID", "ZSOURCEID", "ZTITLE", "ZSTARTTIME", "ZENDTIME", "ZUPDATEDAT"]),
        ("ZFRIENDSHAREPUBLISHEDITEM", ["ZTARGETUSERRECORDNAME", "ZKINDRAWVALUE", "ZSOURCEID", "ZFINGERPRINT"]),
        ("ZFRIENDSHAREZONESYNCSTATE", ["ZOWNERUSERRECORDNAME", "ZCHANGETOKENDATA", "ZUPDATEDAT"])
    ]

    /// `shared` がどの保存先で起動できたか。cloudSync 以外は機能が縮退しているため、
    /// UI 側（RootTabView）が起動時にユーザーへ告知する。
    enum StorageMode {
        case cloudSync
        case appGroupLocal
        case deviceLocal
        case inMemory
    }

    nonisolated(unsafe) private(set) static var storageMode: StorageMode = .cloudSync

    static let shared: ModelContainer = {
        do {
            let container = try appGroupCloud()
            storageMode = .cloudSync
            return container
        } catch {
            NSLog("Liminalog: falling back to local-only ModelContainer because shared Cloud container failed: \(String(describing: error))")
            do {
                let container = try appGroupLocalOnly()
                storageMode = .appGroupLocal
                return container
            } catch {
                NSLog("Liminalog: falling back to app-local ModelContainer because app group local ModelContainer failed: \(String(describing: error))")
                do {
                    let container = try localOnly()
                    storageMode = .deviceLocal
                    return container
                } catch {
                    NSLog("Liminalog: falling back to in-memory ModelContainer because app-local ModelContainer failed: \(String(describing: error))")
                    storageMode = .inMemory
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
            DailyCardSnapshot.self,
            DailyScoreSnapshot.self
        ])
    }

    static var localCacheSchema: Schema {
        Schema([
            CalendarEventCache.self,
            FriendSharedPlanRecord.self,
            FriendSharedChapterRecord.self,
            FriendSharedScoreRecord.self,
            FriendSharePublishedItem.self,
            FriendShareZoneSyncState.self
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
            DailyScoreSnapshot.self,
            CalendarEventCache.self,
            FriendSharedPlanRecord.self,
            FriendSharedChapterRecord.self,
            FriendSharedScoreRecord.self,
            FriendSharePublishedItem.self,
            FriendShareZoneSyncState.self
        ])
    }

    static func localOnly() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Local",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        // 注: migrationPlan は渡さない。開発中はV1のモデル構成が変わり続けるため、
        // ステージ0のプランを渡すとハッシュ不一致でロード拒否される（実機で観測）。
        // 正式リリース時のスキーマを固定した時点で LiminalogMigrationPlan を配線し直す。
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func appGroupLocalOnly() throws -> ModelContainer {
        prepareDevelopmentStoresIfNeeded()

        let cloudConfiguration = ModelConfiguration(
            cloudStoreConfigurationName,
            schema: cloudSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )

        let localCacheConfiguration = ModelConfiguration(
            localCacheStoreConfigurationName,
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
            cloudStoreConfigurationName,
            schema: cloudSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        let localCacheConfiguration = ModelConfiguration(
            localCacheStoreConfigurationName,
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

        purgeCloudMirrorZoneIfRequested()

        let supportURL = appGroupURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        let shouldResetStores = developmentStoreResetWasRequested(defaults: defaults)
            || developmentStoreNeedsReset(defaults: defaults, supportURL: supportURL)

        guard shouldResetStores else {
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
            ProcessInfo.processInfo.arguments.contains("-LiminalogResetDevelopmentStore") ||
            ProcessInfo.processInfo.arguments.contains("-LiminalogPurgeCloudMirrorZone")
    }

    /// 開発用: CloudKit私有DBのミラーゾーンを丸ごと削除する（`-LiminalogPurgeCloudMirrorZone`）。
    /// 開発中はリセット→再シードのたびに別UUIDのシード世代がCloudKitへ蓄積し、
    /// インポートのたびに重複が流れ込み続ける。世代の山を一掃してから再シードするための装置。
    /// このフラグはローカルストアのリセットも兼ねる（上の developmentStoreResetWasRequested）。
    private static func purgeCloudMirrorZoneIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-LiminalogPurgeCloudMirrorZone") else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: nil,
            recordZoneIDsToDelete: [zoneID]
        )
        operation.modifyRecordZonesResultBlock = { result in
            switch result {
            case .success:
                NSLog("Liminalog: purged CloudKit mirror zone for development")
            case let .failure(error):
                NSLog("Liminalog: failed to purge CloudKit mirror zone: \(String(describing: error))")
            }
            semaphore.signal()
        }
        CKContainer(identifier: cloudKitContainerID).privateCloudDatabase.add(operation)
        _ = semaphore.wait(timeout: .now() + 30)
    }

    private static func developmentStoreNeedsReset(defaults: UserDefaults, supportURL: URL) -> Bool {
        defaults.integer(forKey: developmentStoreVersionKey) != currentDevelopmentStoreVersion ||
            developmentCloudStoreIsMissingRequiredMarkers(supportURL: supportURL) ||
            developmentLocalCacheStoreIsMissingRequiredMarkers(supportURL: supportURL)
    }

    private static func developmentCloudStoreIsMissingRequiredMarkers(supportURL: URL) -> Bool {
        let cloudStoreURL = supportURL.appendingPathComponent("\(cloudStoreConfigurationName).store")
        guard FileManager.default.fileExists(atPath: cloudStoreURL.path) else { return false }

        return requiredDevelopmentStoreColumns.contains { requirement in
            !developmentStore(
                at: cloudStoreURL,
                hasColumns: requirement.columns,
                inTable: requirement.table
            )
        }
    }

    private static func developmentLocalCacheStoreIsMissingRequiredMarkers(supportURL: URL) -> Bool {
        let localCacheStoreURL = supportURL.appendingPathComponent("\(localCacheStoreConfigurationName).store")
        guard FileManager.default.fileExists(atPath: localCacheStoreURL.path) else { return false }

        return requiredDevelopmentLocalCacheStoreColumns.contains { requirement in
            !developmentStore(
                at: localCacheStoreURL,
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
            "\(cloudStoreConfigurationName).store",
            "Local.store",
            "LocalCache.store",
            "\(localCacheStoreConfigurationName).store"
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

        removeDevelopmentStoreSidecars(in: supportURL)

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

    private static func removeDevelopmentStoreSidecars(in supportURL: URL) {
        #if DEBUG
        let removablePrefixes = [
            "Cloud.store",
            "\(cloudStoreConfigurationName).store",
            "Local.store",
            "LocalCache.store",
            "\(localCacheStoreConfigurationName).store",
            "Cloud_ckAssets",
            "\(cloudStoreConfigurationName)_ckAssets"
        ]

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: supportURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            guard removablePrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                NSLog("Liminalog: failed to remove development store sidecar \(url.lastPathComponent): \(String(describing: error))")
            }
        }
        #endif
    }
}

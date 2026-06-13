import SwiftData

enum LiminalogSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

enum LiminalogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LiminalogSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

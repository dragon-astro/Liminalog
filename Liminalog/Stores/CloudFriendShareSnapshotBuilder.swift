import Foundation

/// 共有データの組み立て（docs/20 §2.1）。
/// - `snapshot(...)`: 共有ルートに載せる軽量ステータス（現在地・スコア・streak）。
/// - `sharedItems(...)`: SharedPlan/SharedChapter 個別レコードに載せる全履歴の可視アイテム。
///   個別レコード方式は CloudKit の1レコード上限に依存しないため、期間ウィンドウは設けない。
enum CloudFriendShareSnapshotBuilder {
    struct SharedItems {
        var plans: [FriendSharedPlanSnapshot] = []
        var activities: [FriendSharedActivitySnapshot] = []
        var scores: [FriendSharedDailyScoreSnapshot] = []
    }

    static func snapshot(
        for friend: Friend,
        ownUsername: String,
        ownDisplayName: String,
        ownProfileBio: String = "",
        ownProfileImageData: Data? = nil,
        ownProfileAccentColorHex: String = "#2F80ED",
        ownProfileBadgeID: String = "starter",
        ownProfileIconFrameID: String = "clear_air",
        ownProfileStreakIconID: String = "flame",
        ownProfileCardStyleID: String = "quiet_sky",
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        acceptedFriendIDs: Set<UUID>,
        now: Date,
        scoreProvider: (FriendScorePeriod) -> Double,
        streakProvider: () -> Int = { 0 },
        cumulativeScoreProvider: () -> Int = { 0 }
    ) -> CloudFriendShareSnapshot {
        let preset = visibilityPreset(for: friend, in: visibilityPresets)
        let canPublish = publishingEnabled(for: preset)

        let activeChapters = chapters.filter { $0.endTime == nil }
        let visibleActiveActivity = FriendSharedActivitySnapshot.snapshots(
            from: canPublish ? activeChapters : [],
            now: now,
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs
        ).first

        return CloudFriendShareSnapshot(
            ownerUsername: ownUsername,
            ownerDisplayName: ownDisplayName,
            targetUserRecordName: friend.userRecordID,
            currentStatusTitle: visibleActiveActivity?.title ?? "",
            currentStatusIcon: visibleActiveActivity?.categoryIconName ?? "circle.dashed",
            currentStatusColorHex: visibleActiveActivity?.categoryColorHex ?? "#8E8E93",
            currentMoodText: visibleActiveActivity?.mood ?? "",
            currentStatusStartedAt: visibleActiveActivity?.startTime,
            profileBio: ownProfileBio.trimmingCharacters(in: .whitespacesAndNewlines),
            profileImageData: ProfileImageShareEncoder.sharedImageData(from: ownProfileImageData),
            profileAccentColorHex: ownProfileAccentColorHex,
            profileBadgeID: ownProfileBadgeID,
            profileIconFrameID: ownProfileIconFrameID,
            profileStreakIconID: ownProfileStreakIconID,
            profileCardStyleID: ownProfileCardStyleID,
            todayScore: canPublish ? scoreProvider(.today) : 0,
            yesterdayScore: canPublish ? scoreProvider(.yesterday) : 0,
            weekScore: canPublish ? scoreProvider(.week) : 0,
            monthScore: canPublish ? scoreProvider(.month) : 0,
            yearScore: canPublish ? scoreProvider(.year) : 0,
            streakCount: canPublish ? streakProvider() : 0,
            cumulativeScore: canPublish ? cumulativeScoreProvider() : 0,
            updatedAt: now
        )
    }

    /// 個別レコードとして公開する全履歴の可視アイテム。可視性プリセットでフィルタ済み。
    static func sharedItems(
        for friend: Friend,
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        planBlocks: [PlanBlock],
        dailyScores: [FriendSharedDailyScoreSnapshot] = [],
        acceptedFriendIDs: Set<UUID>,
        now: Date
    ) -> SharedItems {
        let preset = visibilityPreset(for: friend, in: visibilityPresets)
        guard publishingEnabled(for: preset) else { return SharedItems() }

        let plans = nonOverlappingPlans(FriendSharedPlanSnapshot.snapshots(
            from: planBlocks,
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        ))
        let finishedChapters = chapters.filter { $0.endTime != nil }
        let activities = nonOverlappingActivities(FriendSharedActivitySnapshot.snapshots(
            from: finishedChapters,
            now: now,
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs
        ))
        return SharedItems(plans: plans, activities: activities, scores: dailyScores)
    }

    private static func visibilityPreset(for friend: Friend, in presets: [VisibilityPreset]) -> VisibilityPreset? {
        guard let id = friend.visibilityPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    private static func publishingEnabled(for preset: VisibilityPreset?) -> Bool {
        guard let preset else { return false }
        return preset.publishMode != .none && preset.level != .none
    }

    nonisolated private static func nonOverlappingPlans(_ plans: [FriendSharedPlanSnapshot]) -> [FriendSharedPlanSnapshot] {
        nonOverlapping(
            plans.sorted(by: chronologicalOrder),
            includes: { $0.isAllDay || $0.endTime > $0.startTime },
            overlaps: { !$0.isAllDay && !$1.isAllDay && $0.startTime < $1.endTime && $0.endTime > $1.startTime }
        )
    }

    nonisolated private static func nonOverlappingActivities(_ activities: [FriendSharedActivitySnapshot]) -> [FriendSharedActivitySnapshot] {
        nonOverlapping(
            activities.sorted(by: chronologicalOrder),
            includes: { $0.endTime > $0.startTime },
            overlaps: { $0.startTime < $1.endTime && $0.endTime > $1.startTime }
        )
    }

    nonisolated private static func nonOverlapping<Item>(
        _ items: [Item],
        includes: (Item) -> Bool,
        overlaps: (Item, Item) -> Bool
    ) -> [Item] {
        var result: [Item] = []
        for item in items where includes(item) {
            guard !result.contains(where: { overlaps($0, item) }) else { continue }
            result.append(item)
        }
        return result
    }

    nonisolated private static func chronologicalOrder(_ lhs: FriendSharedPlanSnapshot, _ rhs: FriendSharedPlanSnapshot) -> Bool {
        if lhs.startTime == rhs.startTime {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.startTime < rhs.startTime
    }

    nonisolated private static func chronologicalOrder(_ lhs: FriendSharedActivitySnapshot, _ rhs: FriendSharedActivitySnapshot) -> Bool {
        if lhs.startTime == rhs.startTime {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.startTime < rhs.startTime
    }
}

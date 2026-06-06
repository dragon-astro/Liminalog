import Foundation

enum CloudFriendShareSnapshotBuilder {
    static func snapshot(
        for friend: Friend,
        ownUsername: String,
        ownDisplayName: String,
        visibilityPresets: [VisibilityPreset],
        chapters: [Chapter],
        planBlocks: [PlanBlock],
        acceptedFriendIDs: Set<UUID>,
        now: Date,
        scoreProvider: (FriendScorePeriod) -> Double
    ) -> CloudFriendShareSnapshot {
        let preset = visibilityPreset(for: friend, in: visibilityPresets)
        let canPublish = publishingEnabled(for: preset)
        let activeChapters = chapters.filter { $0.endTime == nil }
        let visiblePlans = FriendSharedPlanSnapshot.snapshots(
            from: canPublish ? planBlocks : [],
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )
        let visibleActivities = FriendSharedActivitySnapshot.snapshots(
            from: canPublish ? chapters : [],
            now: now,
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs
        )
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
            todayScore: canPublish ? scoreProvider(.today) : 0,
            yesterdayScore: canPublish ? scoreProvider(.yesterday) : 0,
            weekScore: canPublish ? scoreProvider(.week) : 0,
            monthScore: canPublish ? scoreProvider(.month) : 0,
            yearScore: canPublish ? scoreProvider(.year) : 0,
            streakCount: 0,
            sharedPlans: visiblePlans,
            sharedActivities: visibleActivities,
            updatedAt: now
        )
    }

    private static func visibilityPreset(for friend: Friend, in presets: [VisibilityPreset]) -> VisibilityPreset? {
        guard let id = friend.visibilityPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    private static func publishingEnabled(for preset: VisibilityPreset?) -> Bool {
        guard let preset else { return false }
        return preset.publishMode != .none && preset.level != .none
    }
}

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
        scoreProvider: (FriendScorePeriod) -> Double,
        streakProvider: () -> Int = { 0 }
    ) -> CloudFriendShareSnapshot {
        let preset = visibilityPreset(for: friend, in: visibilityPresets)
        let canPublish = publishingEnabled(for: preset)

        // 共有は「全期間」ではなく now を中心とした近い期間だけに限定する。
        // 無制限だと記録が増えるほど共有JSONが肥大し、受信側で全画面に読み込まれて
        // メモリ圧迫・カレンダー描画の激重化を招く（数分単位のハングの原因）。
        let windowedChapters = chaptersInShareWindow(chapters, now: now)
        let windowedPlans = plansInShareWindow(planBlocks, now: now)

        let activeChapters = windowedChapters.filter { $0.endTime == nil }
        let visiblePlans = FriendSharedPlanSnapshot.snapshots(
            from: canPublish ? windowedPlans : [],
            visibilityPreset: preset,
            recipientFriendID: friend.id,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )
        let visibleActivities = FriendSharedActivitySnapshot.snapshots(
            from: canPublish ? windowedChapters : [],
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
            streakCount: canPublish ? streakProvider() : 0,
            sharedPlans: visiblePlans,
            sharedActivities: visibleActivities,
            updatedAt: now
        )
    }

    // 共有期間：過去1年〜未来半年。件数上限は CloudKit の1レコード上限(約1MB)に収まる範囲で最大化。
    // ※「全履歴を本当に無制限」は塊JSON方式では不可（サイズ上限・メモリ）。
    //   真の無制限は個別レコード化＋差分同期の改修が必要（Codex引き継ぎ・docs参照）。
    private static let shareWindowPastDays = 365
    private static let shareWindowFutureDays = 180
    private static let shareWindowMaxItems = 2000

    private static func shareWindow(now: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.japanese
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -shareWindowPastDays, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: shareWindowFutureDays, to: today) ?? today
        return (start, end)
    }

    private static func chaptersInShareWindow(_ chapters: [Chapter], now: Date) -> [Chapter] {
        let window = shareWindow(now: now)
        return Array(
            chapters
                .filter { ($0.endTime ?? now) >= window.start && $0.startTime <= window.end }
                .sorted { $0.startTime > $1.startTime }
                .prefix(shareWindowMaxItems)
        )
    }

    private static func plansInShareWindow(_ plans: [PlanBlock], now: Date) -> [PlanBlock] {
        let window = shareWindow(now: now)
        return Array(
            plans
                .filter { $0.endTime >= window.start && $0.startTime <= window.end }
                .sorted { $0.startTime > $1.startTime }
                .prefix(shareWindowMaxItems)
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

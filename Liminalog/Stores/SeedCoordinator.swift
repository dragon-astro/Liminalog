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

    #if DEBUG
    static func seedDebugFriendsIfNeeded(in context: ModelContext, now: Date = Date()) {
        let descriptor = FetchDescriptor<Friend>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let friends = (try? context.fetch(descriptor)) ?? []

        let debugFriends = makeDebugFriends(now: now)
        for debugFriend in debugFriends {
            if let existing = friends.first(where: { $0.userRecordID == debugFriend.userRecordID }) {
                updateDebugFriend(existing, from: debugFriend)
            } else {
                context.insert(debugFriend)
            }
        }
        try? context.save()
    }

    private static func makeDebugFriends(now: Date) -> [Friend] {
        let calendar = Calendar.current
        return [
            makeDebugFriend(
                displayName: "Mika",
                handle: "@mika",
                userRecordID: "debug.mika",
                icon: "leaf.fill",
                color: "#27AE60",
                statusTitle: "勉強",
                statusIcon: "book.closed.fill",
                statusColor: "#2F80ED",
                moodText: "今日はレポート仕上げます！",
                todayScore: 92,
                yesterdayScore: 76,
                weekScore: 84,
                isFavorite: true,
                updatedAt: calendar.date(byAdding: .minute, value: -8, to: now) ?? now,
                now: now
            ),
            makeDebugFriend(
                displayName: "Sora",
                handle: "@sora",
                userRecordID: "debug.sora",
                icon: "moon.stars.fill",
                color: "#6C5CE7",
                statusTitle: "休憩",
                statusIcon: "cup.and.saucer.fill",
                statusColor: "#27AE60",
                moodText: "ちょっと疲れた、休憩中",
                todayScore: 71,
                yesterdayScore: 88,
                weekScore: 79,
                isFavorite: false,
                updatedAt: calendar.date(byAdding: .minute, value: -21, to: now) ?? now,
                now: now
            ),
            makeDebugFriend(
                displayName: "Ren",
                handle: "@ren",
                userRecordID: "debug.ren",
                icon: "bolt.fill",
                color: "#F2994A",
                statusTitle: "仕事",
                statusIcon: "briefcase.fill",
                statusColor: "#6C5CE7",
                moodText: "締切まで集中",
                todayScore: 64,
                yesterdayScore: 58,
                weekScore: 67,
                isFavorite: false,
                updatedAt: calendar.date(byAdding: .minute, value: -37, to: now) ?? now,
                now: now
            ),
            makeDebugFriend(
                displayName: "Yui",
                handle: "@yui",
                userRecordID: "debug.yui",
                icon: "sparkles",
                color: "#EB5757",
                statusTitle: "",
                statusIcon: "circle.dashed",
                statusColor: "#8E8E93",
                moodText: "今日はゆっくりします",
                todayScore: 38,
                yesterdayScore: 94,
                weekScore: 72,
                isFavorite: false,
                updatedAt: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
                now: now
            )
        ]
    }

    private static func makeDebugFriend(
        displayName: String,
        handle: String,
        userRecordID: String,
        icon: String,
        color: String,
        statusTitle: String,
        statusIcon: String,
        statusColor: String,
        moodText: String,
        todayScore: Double,
        yesterdayScore: Double,
        weekScore: Double,
        isFavorite: Bool,
        updatedAt: Date,
        now: Date
    ) -> Friend {
        let friend = Friend(
            displayName: displayName,
            handle: handle,
            status: .accepted,
            inviteCode: "DEBUG-\(displayName.uppercased())",
            accentColorHex: color,
            avatarSystemImage: icon,
            now: now
        )
        friend.userRecordID = userRecordID
        friend.currentStatusTitle = statusTitle
        friend.currentStatusIcon = statusIcon
        friend.currentStatusColorHex = statusColor
        friend.currentMoodText = moodText
        friend.currentStatusUpdatedAt = updatedAt
        friend.lastSeenAt = updatedAt
        friend.todayScore = todayScore
        friend.yesterdayScore = yesterdayScore
        friend.weekScore = weekScore
        friend.isFavorite = isFavorite
        friend.updatedAt = now
        return friend
    }

    private static func updateDebugFriend(_ existing: Friend, from debugFriend: Friend) {
        existing.displayName = debugFriend.displayName
        existing.handle = debugFriend.handle
        existing.avatarSystemImage = debugFriend.avatarSystemImage
        existing.accentColorHex = debugFriend.accentColorHex
        existing.status = debugFriend.status
        existing.currentStatusTitle = debugFriend.currentStatusTitle
        existing.currentStatusIcon = debugFriend.currentStatusIcon
        existing.currentStatusColorHex = debugFriend.currentStatusColorHex
        existing.currentMoodText = debugFriend.currentMoodText
        existing.currentStatusUpdatedAt = debugFriend.currentStatusUpdatedAt
        existing.lastSeenAt = debugFriend.lastSeenAt
        existing.todayScore = debugFriend.todayScore
        existing.yesterdayScore = debugFriend.yesterdayScore
        existing.weekScore = debugFriend.weekScore
        existing.isFavorite = debugFriend.isFavorite
        existing.updatedAt = debugFriend.updatedAt
    }
    #endif

    private static func merge(_ duplicate: UserSettings, into primary: UserSettings) {
        if primary.profileDisplayName.isEmpty {
            primary.profileDisplayName = duplicate.profileDisplayName
        }
        if primary.profileBio.isEmpty {
            primary.profileBio = duplicate.profileBio
        }
        if primary.profileImageData == nil {
            primary.profileImageData = duplicate.profileImageData
        }
        if primary.profileAccentColorHex == "#2F80ED", duplicate.profileAccentColorHex != "#2F80ED" {
            primary.profileAccentColorHex = duplicate.profileAccentColorHex
        }
        if primary.profileBadgeID == "starter", duplicate.profileBadgeID != "starter" {
            primary.profileBadgeID = duplicate.profileBadgeID
        }
        if primary.profileIconFrameID == "halo", duplicate.profileIconFrameID != "halo" {
            primary.profileIconFrameID = duplicate.profileIconFrameID
        }
        if primary.profileStreakIconID == "flame", duplicate.profileStreakIconID != "flame" {
            primary.profileStreakIconID = duplicate.profileStreakIconID
        }
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

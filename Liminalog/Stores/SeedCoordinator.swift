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
        var presets = (try? context.fetch(descriptor)) ?? []
        var didChange = false

        for seed in builtInVisibilityPresetSeeds(now: now) {
            if let existing = presets.first(where: { $0.builtInKey == seed.builtInKey }) {
                if applyBuiltInVisibilityPresetSeed(seed, to: existing, now: now) {
                    didChange = true
                }
            } else {
                context.insert(seed)
                presets.append(seed)
                didChange = true
            }
        }

        let builtInGroups = Dictionary(grouping: presets.filter { $0.builtInKey != nil }) { $0.builtInKey ?? "" }
        for group in builtInGroups.values where group.count > 1 {
            guard let primary = group.sorted(by: { $0.createdAt < $1.createdAt }).first else { continue }
            for duplicate in group where duplicate !== primary {
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

    private static func builtInVisibilityPresetSeeds(now: Date) -> [VisibilityPreset] {
        [
            VisibilityPreset(
                name: "仲良し",
                level: .all,
                builtInKey: "close_friends",
                isBuiltIn: true,
                sortOrder: 0,
                publishMode: .realtime,
                hideMoodAndNote: false,
                hidePhoto: false,
                hideLocation: false,
                freeTimeOnly: false,
                now: now
            ),
            VisibilityPreset(
                name: "知り合い",
                level: .partial,
                builtInKey: "acquaintances",
                isBuiltIn: true,
                sortOrder: 10,
                publishMode: .nextDay,
                hideMoodAndNote: true,
                hidePhoto: true,
                hideLocation: true,
                freeTimeOnly: true,
                now: now
            ),
            VisibilityPreset(
                name: "オフ",
                level: .none,
                builtInKey: "off",
                isBuiltIn: true,
                sortOrder: 20,
                publishMode: .none,
                hideMoodAndNote: true,
                hidePhoto: true,
                hideLocation: true,
                freeTimeOnly: true,
                now: now
            )
        ]
    }

    @discardableResult
    private static func applyBuiltInVisibilityPresetSeed(_ seed: VisibilityPreset, to preset: VisibilityPreset, now: Date) -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<VisibilityPreset, Value>, to value: Value) {
            if preset[keyPath: keyPath] != value {
                preset[keyPath: keyPath] = value
                didChange = true
            }
        }

        update(\.name, to: seed.name)
        update(\.level, to: seed.level)
        update(\.isBuiltIn, to: true)
        update(\.sortOrder, to: seed.sortOrder)
        update(\.publishModeRawValue, to: seed.publishModeRawValue)
        update(\.hideMoodAndNote, to: seed.hideMoodAndNote)
        update(\.hidePhoto, to: seed.hidePhoto)
        update(\.hideLocation, to: seed.hideLocation)
        update(\.excludedCategoryIDs, to: seed.excludedCategoryIDs)
        update(\.freeTimeOnly, to: seed.freeTimeOnly)

        if didChange {
            preset.updatedAt = now
        }
        return didChange
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
                monthScore: 88,
                yearScore: 82,
                streakCount: 12,
                iconFrameID: "halo",
                streakIconID: "spark",
                cardStyleID: "mint",
                sharedPlans: mikaSharedPlans(now: now),
                sharedActivities: mikaSharedActivities(now: now),
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
                monthScore: 73,
                yearScore: 77,
                streakCount: 5,
                iconFrameID: "crown",
                streakIconID: "sun",
                cardStyleID: "glass",
                sharedPlans: soraSharedPlans(now: now),
                sharedActivities: soraSharedActivities(now: now),
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
                monthScore: 69,
                yearScore: 74,
                streakCount: 2,
                iconFrameID: "signal",
                streakIconID: "bolt",
                cardStyleID: "dawn",
                sharedPlans: renSharedPlans(now: now),
                sharedActivities: renSharedActivities(now: now),
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
                monthScore: 81,
                yearScore: 70,
                streakCount: 0,
                iconFrameID: "focus",
                streakIconID: "flame",
                cardStyleID: "clean",
                sharedPlans: yuiSharedPlans(now: now),
                sharedActivities: yuiSharedActivities(now: now),
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
        monthScore: Double,
        yearScore: Double,
        streakCount: Int,
        iconFrameID: String,
        streakIconID: String,
        cardStyleID: String,
        sharedPlans: [FriendSharedPlanSnapshot],
        sharedActivities: [FriendSharedActivitySnapshot],
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
        friend.profileIconFrameID = iconFrameID
        friend.profileStreakIconID = streakIconID
        friend.profileCardStyleID = cardStyleID
        friend.currentStatusTitle = statusTitle
        friend.currentStatusIcon = statusIcon
        friend.currentStatusColorHex = statusColor
        friend.currentMoodText = moodText
        friend.currentStatusUpdatedAt = updatedAt
        friend.lastSeenAt = updatedAt
        friend.todayScore = todayScore
        friend.yesterdayScore = yesterdayScore
        friend.weekScore = weekScore
        friend.monthScore = monthScore
        friend.yearScore = yearScore
        friend.streakCount = streakCount
        friend.setSharedPlans(sharedPlans)
        friend.setSharedActivities(sharedActivities)
        friend.isFavorite = isFavorite
        friend.updatedAt = now
        return friend
    }

    private static func updateDebugFriend(_ existing: Friend, from debugFriend: Friend) {
        existing.displayName = debugFriend.displayName
        existing.handle = debugFriend.handle
        existing.avatarSystemImage = debugFriend.avatarSystemImage
        existing.accentColorHex = debugFriend.accentColorHex
        existing.profileBadgeID = debugFriend.profileBadgeID
        existing.profileIconFrameID = debugFriend.profileIconFrameID
        existing.profileStreakIconID = debugFriend.profileStreakIconID
        existing.profileCardStyleID = debugFriend.profileCardStyleID
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
        existing.monthScore = debugFriend.monthScore
        existing.yearScore = debugFriend.yearScore
        existing.streakCount = debugFriend.streakCount
        existing.sharedPlansJSON = debugFriend.sharedPlansJSON
        existing.sharedActivitiesJSON = debugFriend.sharedActivitiesJSON
        existing.isFavorite = debugFriend.isFavorite
        existing.updatedAt = debugFriend.updatedAt
    }

    private static func mikaSharedPlans(now: Date) -> [FriendSharedPlanSnapshot] {
        [
            sharedPlan(title: "レポート仕上げ", dayOffset: 0, startHour: 20, startMinute: 30, durationMinutes: 90, icon: "book.closed.fill", color: "#2F80ED", now: now),
            sharedPlan(title: "ゼミ準備", dayOffset: 1, startHour: 10, startMinute: 0, durationMinutes: 120, icon: "graduationcap.fill", color: "#6C5CE7", now: now),
            sharedPlan(title: "研究会", dayOffset: 3, startHour: 14, startMinute: 0, durationMinutes: 180, icon: "person.3.fill", color: "#27AE60", now: now),
            sharedPlan(title: "帰省", dayOffset: 6, endDayOffset: 8, allDay: true, important: true, icon: "house.fill", color: "#F2994A", now: now)
        ]
    }

    private static func soraSharedPlans(now: Date) -> [FriendSharedPlanSnapshot] {
        [
            sharedPlan(title: "休憩多めの日", dayOffset: 0, allDay: true, important: true, icon: "cup.and.saucer.fill", color: "#27AE60", now: now),
            sharedPlan(title: "英語", dayOffset: 2, startHour: 19, startMinute: 0, durationMinutes: 60, icon: "text.book.closed.fill", color: "#2F80ED", now: now),
            sharedPlan(title: "ライブ", dayOffset: 5, startHour: 18, startMinute: 30, durationMinutes: 150, icon: "music.mic", color: "#D946EF", now: now)
        ]
    }

    private static func renSharedPlans(now: Date) -> [FriendSharedPlanSnapshot] {
        [
            sharedPlan(title: "締切対応", dayOffset: 0, startHour: 21, startMinute: 0, durationMinutes: 120, icon: "briefcase.fill", color: "#6C5CE7", now: now),
            sharedPlan(title: "出張", dayOffset: 4, endDayOffset: 6, allDay: true, important: true, icon: "airplane", color: "#F2994A", now: now),
            sharedPlan(title: "資料レビュー", dayOffset: 7, startHour: 9, startMinute: 30, durationMinutes: 90, icon: "doc.text.fill", color: "#607D8B", now: now)
        ]
    }

    private static func yuiSharedPlans(now: Date) -> [FriendSharedPlanSnapshot] {
        [
            sharedPlan(title: "回復日", dayOffset: 0, allDay: true, important: true, icon: "sparkles", color: "#EB5757", now: now),
            sharedPlan(title: "カフェ", dayOffset: 1, startHour: 13, startMinute: 0, durationMinutes: 90, icon: "cup.and.saucer.fill", color: "#F2994A", now: now)
        ]
    }

    private static func sharedPlan(
        title: String,
        dayOffset: Int,
        endDayOffset: Int? = nil,
        startHour: Int = 0,
        startMinute: Int = 0,
        durationMinutes: Int = 60,
        allDay: Bool = false,
        important: Bool = true,
        icon: String,
        color: String,
        now: Date
    ) -> FriendSharedPlanSnapshot {
        let calendar = Calendar.japanese
        let baseDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now)
        let start = calendar.date(byAdding: DateComponents(hour: startHour, minute: startMinute), to: baseDay) ?? baseDay
        let end: Date
        if allDay {
            let inclusiveEndOffset = endDayOffset ?? dayOffset
            let endDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: inclusiveEndOffset + 1, to: now) ?? now)
            end = endDay
        } else {
            end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
        }

        return FriendSharedPlanSnapshot(
            title: title,
            startTime: start,
            endTime: end,
            isAllDay: allDay,
            isImportant: important,
            categoryTitle: title,
            categoryIconName: icon,
            categoryColorHex: color,
            updatedAt: now
        )
    }

    private static func mikaSharedActivities(now: Date) -> [FriendSharedActivitySnapshot] {
        [
            sharedActivity(title: "朝の準備", dayOffset: 0, startHour: 7, startMinute: 20, durationMinutes: 40, icon: "sunrise.fill", color: "#F2994A", now: now),
            sharedActivity(title: "勉強", dayOffset: 0, startHour: 9, startMinute: 0, durationMinutes: 150, icon: "book.closed.fill", color: "#2F80ED", note: "レポート構成", now: now),
            sharedActivity(title: "休憩", dayOffset: 0, startHour: 11, startMinute: 30, durationMinutes: 35, icon: "cup.and.saucer.fill", color: "#27AE60", now: now),
            sharedActivity(title: "ゼミ準備", dayOffset: 0, startHour: 13, startMinute: 10, durationMinutes: 130, icon: "graduationcap.fill", color: "#6C5CE7", now: now),
            sharedActivity(title: "移動", dayOffset: 0, startHour: 16, startMinute: 0, durationMinutes: 45, icon: "tram.fill", color: "#607D8B", now: now),
            sharedActivity(title: "勉強", dayOffset: -1, startHour: 19, startMinute: 30, durationMinutes: 110, icon: "book.closed.fill", color: "#2F80ED", now: now)
        ]
    }

    private static func soraSharedActivities(now: Date) -> [FriendSharedActivitySnapshot] {
        [
            sharedActivity(title: "睡眠", dayOffset: 0, startHour: 0, startMinute: 0, durationMinutes: 430, icon: "moon.zzz.fill", color: "#6C5CE7", now: now),
            sharedActivity(title: "休憩", dayOffset: 0, startHour: 10, startMinute: 20, durationMinutes: 80, icon: "cup.and.saucer.fill", color: "#27AE60", now: now),
            sharedActivity(title: "英語", dayOffset: 0, startHour: 14, startMinute: 0, durationMinutes: 75, icon: "text.book.closed.fill", color: "#2F80ED", now: now),
            sharedActivity(title: "音楽", dayOffset: -1, startHour: 21, startMinute: 0, durationMinutes: 120, icon: "music.note", color: "#D946EF", now: now)
        ]
    }

    private static func renSharedActivities(now: Date) -> [FriendSharedActivitySnapshot] {
        [
            sharedActivity(title: "仕事", dayOffset: 0, startHour: 8, startMinute: 45, durationMinutes: 185, icon: "briefcase.fill", color: "#6C5CE7", now: now),
            sharedActivity(title: "資料作成", dayOffset: 0, startHour: 13, startMinute: 0, durationMinutes: 160, icon: "doc.text.fill", color: "#607D8B", now: now),
            sharedActivity(title: "休憩", dayOffset: 0, startHour: 16, startMinute: 15, durationMinutes: 35, icon: "cup.and.saucer.fill", color: "#27AE60", now: now),
            sharedActivity(title: "仕事", dayOffset: -1, startHour: 20, startMinute: 15, durationMinutes: 140, icon: "briefcase.fill", color: "#6C5CE7", now: now)
        ]
    }

    private static func yuiSharedActivities(now: Date) -> [FriendSharedActivitySnapshot] {
        [
            sharedActivity(title: "回復", dayOffset: 0, startHour: 9, startMinute: 30, durationMinutes: 90, icon: "sparkles", color: "#EB5757", now: now),
            sharedActivity(title: "散歩", dayOffset: 0, startHour: 15, startMinute: 0, durationMinutes: 45, icon: "figure.walk", color: "#27AE60", now: now),
            sharedActivity(title: "カフェ", dayOffset: -1, startHour: 13, startMinute: 0, durationMinutes: 75, icon: "cup.and.saucer.fill", color: "#F2994A", now: now)
        ]
    }

    private static func sharedActivity(
        title: String,
        dayOffset: Int,
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        icon: String,
        color: String,
        note: String? = nil,
        now: Date
    ) -> FriendSharedActivitySnapshot {
        let calendar = Calendar.japanese
        let baseDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now)
        let start = calendar.date(byAdding: DateComponents(hour: startHour, minute: startMinute), to: baseDay) ?? baseDay
        let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
        return FriendSharedActivitySnapshot(
            title: title,
            startTime: start,
            endTime: end,
            categoryTitle: title,
            categoryIconName: icon,
            categoryColorHex: color,
            note: note,
            updatedAt: now
        )
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
        if primary.profileCardStyleID == "clean", duplicate.profileCardStyleID != "clean" {
            primary.profileCardStyleID = duplicate.profileCardStyleID
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

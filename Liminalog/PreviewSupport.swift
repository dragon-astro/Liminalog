import Foundation
import SwiftData
import SwiftUI

@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = Schema([Category.self, CategorySet.self, Chapter.self, PlanBlock.self, UnlockItem.self, VisibilityPreset.self, UserSettings.self, Friend.self, FriendCategoryMapping.self, CalendarEventCache.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(in: container.mainContext)
        return container
    }()

    static var store: ChapterStore {
        ChapterStore(modelContext: container.mainContext)
    }

    private static func seed(in context: ModelContext) {
        let categories = [
            Category(name: "勉強", colorHex: "#2F80ED", icon: "book.closed.fill", sortOrder: 0, isDefault: true),
            Category(name: "仕事", colorHex: "#6C5CE7", icon: "briefcase.fill", sortOrder: 1, isDefault: true),
            Category(name: "休憩", colorHex: "#27AE60", icon: "cup.and.saucer.fill", sortOrder: 2, isDefault: true),
            Category(name: "移動", colorHex: "#F2994A", icon: "tram.fill", sortOrder: 3, isDefault: true),
            Category(name: "趣味", colorHex: "#EB5757", icon: "sparkles", sortOrder: 4, isDefault: true),
            Category(name: "睡眠", colorHex: "#9B51E0", icon: "moon.fill", sortOrder: 5, isDefault: true),
        ]

        categories.forEach(context.insert)
        // 平日セット: 6カテゴリを左上から配置、残り2スロットは空き
        let weekdaySlots: [UUID?] = categories.map { Optional($0.id) } + Array(repeating: nil, count: 8 - categories.count)
        // 休日セット: 睡眠・趣味・休憩・勉強・移動 を配置、残り3スロットは空き
        let holidayLayout: [UUID?] = [categories[5].id, categories[4].id, categories[2].id, categories[0].id, categories[3].id, nil, nil, nil]
        context.insert(CategorySet(name: "平日", sortOrder: 0, slots: weekdaySlots))
        context.insert(CategorySet(name: "休日", sortOrder: 1, slots: holidayLayout))

        let settings = UserSettings()
        settings.profileDisplayName = "Ryu"
        settings.profileBio = "切り替わる瞬間を記録中"
        context.insert(settings)
        UnlockCatalog.items
            .map { UnlockItem(seed: $0) }
            .forEach(context.insert)

        let friends = [
            Friend(displayName: "Mika", handle: "@mika", status: .accepted, accentColorHex: "#27AE60", avatarSystemImage: "leaf.fill"),
            Friend(displayName: "Sora", handle: "@sora", status: .accepted, accentColorHex: "#6C5CE7", avatarSystemImage: "moon.stars.fill"),
            Friend(displayName: "Ren", handle: "@ren", status: .pendingIncoming, inviteCode: "REN202605", accentColorHex: "#F2994A", avatarSystemImage: "bolt.fill")
        ]
        friends[0].currentStatusTitle = "勉強"
        friends[0].currentStatusIcon = "book.closed.fill"
        friends[0].currentStatusColorHex = "#2F80ED"
        friends[0].currentMoodText = "今日はレポート仕上げます！"
        friends[0].todayScore = 86
        friends[0].yesterdayScore = 74
        friends[0].weekScore = 81
        friends[0].isFavorite = true
        friends[0].lastSeenAt = Date()
        friends[1].currentStatusTitle = "休憩"
        friends[1].currentStatusIcon = "cup.and.saucer.fill"
        friends[1].currentStatusColorHex = "#27AE60"
        friends[1].currentMoodText = "ちょっと疲れた、休憩中"
        friends[1].todayScore = 68
        friends[1].yesterdayScore = 91
        friends[1].weekScore = 77
        friends[1].lastSeenAt = Date()
        friends.forEach(context.insert)

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let samples: [(Int, Int, Category, String?, String?, String?, Bool)] = [
            (7, 90, categories[5], nil, "😴", nil, false),
            (9, 75, categories[0], "英語の復習", "💪", "図書館", true),
            (11, 45, categories[3], nil, nil, "電車", true),
            (13, 120, categories[1], "UIを整理", "🔥", nil, true),
            (16, 30, categories[2], "コーヒー", "☕️", "カフェ", false),
        ]

        for (hour, minutes, category, note, mood, location, isPublic) in samples {
            guard
                let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }

            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            chapter.note = note
            chapter.mood = mood
            chapter.locationName = location
            chapter.isPublic = isPublic
            context.insert(chapter)
        }

        let plannedSamples: [(Int, Int, Int, Category, String)] = [
            (0, 0, 420, categories[5], "睡眠"),
            (7, 0, 60, categories[2], "朝の準備"),
            (8, 0, 60, categories[3], "移動"),
            (9, 0, 120, categories[0], "英語と課題"),
            (11, 0, 45, categories[3], "移動"),
            (11, 45, 75, categories[2], "昼休み"),
            (13, 0, 180, categories[1], "制作作業"),
            (16, 0, 30, categories[2], "休憩"),
            (16, 30, 90, categories[0], "復習"),
            (18, 0, 60, categories[3], "帰宅"),
            (19, 0, 150, categories[4], "自由時間"),
            (21, 30, 60, categories[2], "夜の休憩"),
            (22, 30, 90, categories[5], "睡眠"),
        ]

        for (hour, startMinute, durationMinutes, category, title) in plannedSamples {
            guard
                let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
                let adjustedStart = calendar.date(byAdding: .minute, value: startMinute, to: start),
                let end = calendar.date(byAdding: .minute, value: durationMinutes, to: adjustedStart)
            else { continue }
            context.insert(PlanBlock(category: category, title: title, startTime: adjustedStart, endTime: end))
        }

        if let activeStart = calendar.date(byAdding: .hour, value: 18, to: startOfDay) {
            let active = Chapter(category: categories[4], startTime: activeStart)
            active.note = "アプリの試作"
            active.mood = "🤩"
            context.insert(active)
        }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? startOfDay
        let mockSchedules: [(Int, Int, Int, Category, String?, String?, String?, Bool)] = [
            (2, 8, 45, categories[3], "通勤", nil, "電車", true),
            (2, 10, 90, categories[1], "定例ミーティング", "📝", "オフィス", true),
            (2, 13, 60, categories[0], "資料読み込み", nil, nil, false),
            (2, 16, 45, categories[2], "散歩", "🌿", "公園", true),
            (2, 20, 75, categories[4], "映画", "🎬", nil, true),
            (5, 9, 120, categories[1], "企画レビュー", "🔥", "会議室A", true),
            (5, 14, 90, categories[0], "SwiftUI実験", "💡", nil, true),
            (8, 7, 60, categories[2], "朝カフェ", "☕️", "駅前", false),
            (8, 19, 150, categories[4], "友達とごはん", "🍜", "渋谷", true),
            (11, 10, 240, categories[1], "集中作業", "💻", nil, false),
            (14, 9, 45, categories[3], "移動", nil, "新幹線", true),
            (14, 11, 180, categories[0], "読書会", "📚", "図書館", true),
            (14, 18, 60, categories[2], "休憩", nil, nil, false),
            (18, 6, 120, categories[5], "二度寝", "😴", nil, false),
            (18, 12, 75, categories[1], "ランチMTG", nil, "カフェ", true),
            (21, 8, 30, categories[3], "移動", nil, nil, true),
            (21, 9, 180, categories[1], "実装", "🔥", nil, false),
            (21, 13, 60, categories[2], "昼休み", "🍱", nil, true),
            (21, 15, 120, categories[0], "設計メモ", "✍️", nil, true),
            (21, 19, 90, categories[4], "音楽", "🎧", nil, true),
            (24, 10, 90, categories[0], "日本語カレンダー確認", "✅", nil, true),
            (27, 13, 180, categories[1], "週次まとめ", "📊", "自宅", false),
            (30, 9, 60, categories[2], "モーニング", nil, "喫茶店", true),
            (30, 20, 120, categories[4], "ゲーム", "🎮", nil, true),
        ]

        for (dayOffset, hour, minutes, category, note, mood, location, isPublic) in mockSchedules {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: monthStart),
                let start = calendar.date(byAdding: .hour, value: hour, to: day),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }

            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            chapter.note = note
            chapter.mood = mood
            chapter.locationName = location
            chapter.isPublic = isPublic
            context.insert(chapter)
        }

        let planOffsets: [(Int, Int, Int, Category, String)] = [
            (2, 9, 90, categories[1], "定例ミーティング"),
            (2, 13, 120, categories[0], "資料読み込み"),
            (5, 9, 120, categories[1], "企画レビュー"),
            (14, 11, 180, categories[0], "読書会"),
            (21, 9, 180, categories[1], "実装"),
            (21, 15, 120, categories[0], "設計メモ"),
            (24, 10, 90, categories[0], "カレンダー確認"),
        ]

        for (dayOffset, hour, minutes, category, title) in planOffsets {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: monthStart),
                let start = calendar.date(byAdding: .hour, value: hour, to: day),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }
            context.insert(PlanBlock(category: category, title: title, startTime: start, endTime: end))
        }

        let importantPlanOffsets: [(Int, Int, Category, String)] = [
            (3, 1, categories[0], "レポート提出"),
            (8, 1, categories[1], "ゼミ発表"),
            (12, 4, categories[4], "合宿"),
            (24, 1, categories[2], "手続き")
        ]

        for (dayOffset, dayCount, category, title) in importantPlanOffsets {
            guard
                let start = calendar.date(byAdding: .day, value: dayOffset, to: monthStart),
                let end = calendar.date(byAdding: .day, value: dayCount, to: start)
            else { continue }
            context.insert(PlanBlock(category: category, title: title, startTime: start, endTime: end, isAllDay: true))
        }

        try? context.save()
    }
}

extension View {
    @MainActor
    func liminalogPreviewEnvironment() -> some View {
        modelContainer(PreviewSupport.container)
            .environment(PreviewSupport.store)
    }
}

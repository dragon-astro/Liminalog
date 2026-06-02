import AppIntents

struct OpenTodayShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "今日を開く"
    static let description = IntentDescription("Liminalogの今日タブを開きます。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        LiminalogShortcutRoute.request(.today)
        return .result()
    }
}

struct OpenCalendarShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "カレンダーを開く"
    static let description = IntentDescription("Liminalogのカレンダーを開きます。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        LiminalogShortcutRoute.request(.calendar)
        return .result()
    }
}

struct OpenDashboardShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "統計を開く"
    static let description = IntentDescription("Liminalogの統計を開きます。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        LiminalogShortcutRoute.request(.dashboard)
        return .result()
    }
}

struct OpenProfileShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "プロフィールを開く"
    static let description = IntentDescription("Liminalogのプロフィールを開きます。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        LiminalogShortcutRoute.request(.profile)
        return .result()
    }
}

struct LiminalogAppShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayShortcutIntent(),
            phrases: [
                "\(.applicationName)で今日を開く",
                "\(.applicationName)の今日"
            ],
            shortTitle: "今日",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: OpenCalendarShortcutIntent(),
            phrases: [
                "\(.applicationName)でカレンダーを開く",
                "\(.applicationName)のカレンダー"
            ],
            shortTitle: "カレンダー",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenDashboardShortcutIntent(),
            phrases: [
                "\(.applicationName)で統計を開く",
                "\(.applicationName)の統計"
            ],
            shortTitle: "統計",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: OpenProfileShortcutIntent(),
            phrases: [
                "\(.applicationName)でプロフィールを開く",
                "\(.applicationName)のプロフィール"
            ],
            shortTitle: "プロフィール",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: EndChapterIntent(),
            phrases: [
                "\(.applicationName)で記録を終了",
                "\(.applicationName)の記録を止める"
            ],
            shortTitle: "記録終了",
            systemImageName: "stop.circle.fill"
        )
    }
}

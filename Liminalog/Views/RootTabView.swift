import SwiftUI
import SwiftData

private enum RootTab: Hashable {
    case today
    case calendar
    case dashboard
    case friends
    case profile
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var appStores: AppStores?
    @State private var selectedTab: RootTab
    @State private var pendingFriendInviteURL: URL?

    init() {
        _selectedTab = State(initialValue: Self.initialTab())
    }

    var body: some View {
        Group {
            if let appStores {
                let store = appStores.chapterStore
                TabView(selection: $selectedTab) {
                    Tab("今日", systemImage: "clock.fill", value: RootTab.today) {
                        HomeView()
                    }
                    Tab("カレンダー", systemImage: "calendar", value: RootTab.calendar) {
                        CalendarView()
                    }
                    Tab("統計", systemImage: "chart.bar.fill", value: RootTab.dashboard) {
                        DashboardView()
                    }
                    Tab("友達", systemImage: "person.2.fill", value: RootTab.friends) {
                        FriendsView(pendingInviteURL: $pendingFriendInviteURL)
                    }
                    Tab("プロフィール", systemImage: "person.crop.circle", value: RootTab.profile) {
                        ProfileView()
                    }
                }
                .environment(store)
            } else {
                ProgressView()
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .liminalAppChrome()
        .task {
            guard appStores == nil else { return }
            let initializedStores = AppStores(modelContext: modelContext)
            let initializedStore = initializedStores.bootstrap()
            #if DEBUG
            let seedRequest = PreviewSupport.runtimeSeedRequest()
            if seedRequest.shouldSeedPreviewPlans {
                initializedStore.seedPreviewPlansIfNeeded()
            }
            if seedRequest.shouldSeedDevData {
                initializedStore.seedDevSampleChaptersIfNeeded()
            }
            #endif
            appStores = initializedStores
            await initializedStores.streakNotificationStore.refreshStreakBreakWarning()
            let didConsumeShortcutRoute = consumePendingShortcutRoute()
            #if DEBUG
            if !didConsumeShortcutRoute {
                selectedTab = Self.initialTab()
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            consumePendingShortcutRoute()
        }
        .onOpenURL { url in
            guard FriendInvitePayload(url: url) != nil else { return }
            pendingFriendInviteURL = url
            selectedTab = .friends
        }
    }

    @discardableResult
    private func consumePendingShortcutRoute() -> Bool {
        guard let route = LiminalogShortcutRoute.consumePendingRoute() else { return false }
        selectedTab = RootTab(route)
        return true
    }

    private static func initialTab() -> RootTab {
        #if DEBUG
        if let environmentValue = ProcessInfo.processInfo.environment["LiminalogInitialRootTab"] {
            return tab(from: environmentValue)
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-LiminalogInitialRootTab"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return .today
        }

        return tab(from: arguments[arguments.index(after: flagIndex)])
        #else
        return .today
        #endif
    }

    private static func tab(from rawValue: String) -> RootTab {
        switch rawValue.lowercased() {
        case "calendar":
            return .calendar
        case "dashboard":
            return .dashboard
        case "friends":
            return .friends
        case "profile":
            return .profile
        default:
            return .today
        }
    }
}

private extension RootTab {
    init(_ shortcutRoute: LiminalogShortcutRoute) {
        switch shortcutRoute {
        case .today:
            self = .today
        case .calendar:
            self = .calendar
        case .dashboard:
            self = .dashboard
        case .profile:
            self = .profile
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

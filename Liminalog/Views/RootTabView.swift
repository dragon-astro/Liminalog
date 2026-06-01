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
            #if DEBUG
            selectedTab = Self.initialTab()
            #endif
        }
        .onOpenURL { url in
            guard FriendInvitePayload(url: url) != nil else { return }
            pendingFriendInviteURL = url
            selectedTab = .friends
        }
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

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

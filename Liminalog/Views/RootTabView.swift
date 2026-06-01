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
    @State private var selectedTab: RootTab = .today
    @State private var pendingFriendInviteURL: URL?

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
            // Preview/デモ用 seed は明示フラグがあるときだけ投入する。
            // 実機 DEBUG で通常データへ勝手に混ざらないようにする。
            let shouldSeedDevData = UserDefaults.standard.bool(forKey: "LiminalogSeedDevData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedDevData")
            let shouldSeedPreviewPlans = UserDefaults.standard.bool(forKey: "LiminalogSeedPreviewData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedPreviewData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedPreviewData YES")
                || shouldSeedDevData
            if shouldSeedPreviewPlans {
                initializedStore.seedPreviewPlansIfNeeded()
            }
            if shouldSeedDevData {
                initializedStore.seedDevSampleChaptersIfNeeded()
            }
            #endif
            appStores = initializedStores
        }
        .onOpenURL { url in
            guard FriendInvitePayload(url: url) != nil else { return }
            pendingFriendInviteURL = url
            selectedTab = .friends
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

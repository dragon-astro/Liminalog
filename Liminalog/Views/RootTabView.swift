import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appStores: AppStores?

    var body: some View {
        Group {
            if let appStores {
                let store = appStores.chapterStore
                TabView {
                    Tab("今日", systemImage: "clock.fill") {
                        HomeView()
                    }
                    Tab("カレンダー", systemImage: "calendar") {
                        CalendarView()
                    }
                    Tab("統計", systemImage: "chart.bar.fill") {
                        DashboardView()
                    }
                    Tab("友達", systemImage: "person.2.fill") {
                        FriendsView()
                    }
                    Tab("プロフィール", systemImage: "person.crop.circle") {
                        ProfileView()
                    }
                }
                .environment(store)
            } else {
                ProgressView()
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .task {
            guard appStores == nil else { return }
            let initializedStores = AppStores(modelContext: modelContext)
            let initializedStore = initializedStores.bootstrap()
            #if DEBUG
            // Preview/デモ用 seed は明示フラグがあるときだけ投入する。
            // 実機 DEBUG で通常データへ勝手に混ざらないようにする。
            let shouldSeedPreviewPlans = UserDefaults.standard.bool(forKey: "LiminalogSeedPreviewData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedPreviewData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedPreviewData YES")
            if shouldSeedPreviewPlans {
                initializedStore.seedPreviewPlansIfNeeded()
            }
            let shouldSeedDevData = UserDefaults.standard.bool(forKey: "LiminalogSeedDevData")
                || ProcessInfo.processInfo.arguments.contains("-LiminalogSeedDevData")
            if shouldSeedDevData {
                initializedStore.seedDevSampleChaptersIfNeeded()
            }
            #endif
            appStores = initializedStores
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

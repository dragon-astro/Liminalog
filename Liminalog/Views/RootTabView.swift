import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: ChapterStore?

    var body: some View {
        Group {
            if let store {
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
            guard store == nil else { return }
            let initializedStore = ChapterStore(modelContext: modelContext)
            SeedCoordinator.ensureUserSettings(in: modelContext)
            SeedCoordinator.consolidateBuiltInVisibilityPresets(in: modelContext)
            initializedStore.pruneShortChapters()
            initializedStore.seedDefaultCategorySetsIfNeeded()
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
            store = initializedStore
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

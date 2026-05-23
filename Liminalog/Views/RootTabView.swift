import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: ChapterStore?

    var body: some View {
        Group {
            if let store {
                TabView {
                    Tab("ホーム", systemImage: "house.fill") {
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
        .task {
            guard store == nil else { return }
            let initializedStore = ChapterStore(modelContext: modelContext)
            initializedStore.seedDefaultCategorySetsIfNeeded()
            #if DEBUG
            initializedStore.seedPreviewPlansIfNeeded()
            #endif
            store = initializedStore
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

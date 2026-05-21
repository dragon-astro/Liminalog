import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("今日", systemImage: "house.fill") {
                HomeView()
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
        .environment(ChapterStore(modelContext: modelContext))
    }
}

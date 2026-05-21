import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "統計",
                systemImage: "chart.bar.fill",
                description: Text("Phase 2 で実装予定")
            )
            .navigationTitle("統計")
        }
    }
}

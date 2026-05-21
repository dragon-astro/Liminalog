import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "プロフィール",
                systemImage: "person.crop.circle",
                description: Text("Phase 3 で実装予定")
            )
            .navigationTitle("プロフィール")
        }
    }
}

import SwiftUI

struct FriendsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "友達",
                systemImage: "person.2.fill",
                description: Text("Phase 3 で実装予定")
            )
            .navigationTitle("友達")
        }
    }
}

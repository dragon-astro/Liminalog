import SwiftUI

struct FriendsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContentUnavailableView(
                        "友達機能は準備中",
                        systemImage: "person.2.fill",
                        description: Text("まずは自分の記録だけで使えるようにしています")
                    )
                    .listRowBackground(Color.clear)
                }

                Section("Phase 3 予定") {
                    Label("承認制の友達追加", systemImage: "person.badge.plus")
                    Label("友達の現在ステータス", systemImage: "dot.radiowaves.left.and.right")
                    Label("タイムライン比較", systemImage: "rectangle.split.2x1")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview("Friends") {
    FriendsView()
        .liminalogPreviewEnvironment()
}

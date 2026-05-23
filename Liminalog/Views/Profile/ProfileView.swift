import SwiftUI

struct ProfileView: View {
    @Environment(ChapterStore.self) private var store
    @State private var displayName = "Ryu"
    @State private var bio = "切り替わる瞬間を記録中"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.linearGradient(colors: [.blue, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                            Text(String(displayName.prefix(1)))
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            TextField("名前", text: $displayName)
                                .font(.title3.bold())
                            TextField("自己紹介", text: $bio, axis: .vertical)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("サマリー") {
                    ProfileMetricRow(title: "今日のスコア", value: "\(Int(store.scoreSummary(on: Date()).totalScore.rounded())) pt")
                    ProfileMetricRow(title: "ストリーク", value: "\(store.streakCount())日")
                    ProfileMetricRow(title: "累計スコア", value: "\(store.totalScore()) pt")
                    ProfileMetricRow(title: "総チャプター", value: "\(store.recentChapters(limit: 1_000).count)")
                    ProfileMetricRow(title: "今日の記録", value: "\(store.todaysChapters().count)")
                    ProfileMetricRow(title: "カテゴリ", value: "\(store.allCategories().count)")
                }

                Section("設定") {
                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Label("カテゴリ管理", systemImage: "slider.horizontal.3")
                    }

                    Label("公開設定プリセット", systemImage: "eye")
                        .foregroundStyle(.secondary)
                    Label("ウィジェット設定", systemImage: "square.grid.2x2")
                        .foregroundStyle(.secondary)
                    Label("カレンダー連携", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("プロフィール")
        }
    }
}

struct ProfileMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}

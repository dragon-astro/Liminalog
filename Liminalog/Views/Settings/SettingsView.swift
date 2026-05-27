import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("管理") {
                NavigationLink {
                    CategorySettingsView()
                } label: {
                    Label("カテゴリ管理", systemImage: "square.grid.2x2")
                }
            }

            Section {
                NavigationLink {
                    CalendarSettingsContent()
                } label: {
                    Label("カレンダー表示", systemImage: "calendar")
                }

                LabeledContent {
                    Text("0:00 - 24:00")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("1日の範囲", systemImage: "clock")
                }
            } header: {
                Text("表示")
            } footer: {
                Text("1日の範囲はスコア公平性のため固定です。変更機能は将来検討に回しています。")
            }

            Section {
                Label("公開プリセット", systemImage: "eye")
                    .foregroundStyle(.secondary)
                Label("友達への見え方", systemImage: "person.2")
                    .foregroundStyle(.secondary)
            } header: {
                Text("公開")
            } footer: {
                Text("友達機能と公開範囲の詳細は Phase 3 で実装します。")
            }

            Section("アプリ情報") {
                LabeledContent("バージョン", value: versionText)
                Label("ヘルプ", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
            .liminalogPreviewEnvironment()
    }
}

import SwiftUI

struct SettingsView: View {
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

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
                    ThemePickerView()
                } label: {
                    Label("テーマ", systemImage: "paintpalette")
                }

                NavigationLink {
                    CalendarSettingsContent()
                } label: {
                    Label("カレンダー表示", systemImage: "calendar")
                }

                LabeledContent {
                    Text("0:00 - 24:00")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } label: {
                    Label("1日の範囲", systemImage: "clock")
                }
            } header: {
                Text("表示")
            } footer: {
                Text("1日の範囲はスコア公平性のため固定です。変更機能は将来検討に回しています。")
            }

            Section {
                LabeledContent {
                    Text("カテゴリ管理")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } label: {
                    Label("公開相手", systemImage: "person.badge.plus")
                }

                NavigationLink {
                    VisibilityPresetSettingsView()
                } label: {
                    Label("友達への見え方", systemImage: "eye")
                }
            } header: {
                Text("公開")
            } footer: {
                Text("カテゴリごとのデフォルト公開相手はカテゴリ管理から、友達ごとのプリセット割り当ては友達詳細から変更できます。")
            }

            #if DEBUG
            Section {
                Toggle(isOn: $allowsLockedDecorationTesting) {
                    Label("未解放の装備を試す", systemImage: "wand.and.stars")
                }

                NavigationLink {
                    UnlockGalleryView(initialMetrics: UnlockMetrics())
                } label: {
                    Label("コレクションで試す", systemImage: "sparkles")
                }

                NavigationLink {
                    ThemePickerView()
                } label: {
                    Label("テーマを試す", systemImage: "paintbrush.pointed")
                }
            } header: {
                Text("デバッグ")
            } footer: {
                Text("DEBUGビルド限定です。実績データや解放状態は変更せず、表示と選択だけ未解放アイテムを試せます。OFFにすると未解放テーマや装備は通常の解放判定に戻ります。")
            }
            #endif

            Section("アプリ情報") {
                LabeledContent("バージョン", value: versionText)
                Label("ヘルプ", systemImage: "questionmark.circle")
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
            .liminalogPreviewEnvironment()
    }
}

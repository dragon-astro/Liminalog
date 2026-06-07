import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    @AppStorage(PreviewSupport.devDataFlagKey) private var debugDevDataEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [UserSettings]
    @State private var isResettingCloudUserID = false
    @State private var debugStatusText: String?
    @State private var showCloudUserIDResetConfirmation = false
    #endif

    /// お問い合わせ先（必要に応じて差し替え）。
    private let supportEmailAddress = "yuhapenguin@gmail.com"

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var supportMailURL: URL? {
        let subject = "Liminalog お問い合わせ（v\(versionText)）"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(supportEmailAddress)?subject=\(encoded)")
    }

    var body: some View {
        List {
            iCloudSyncSection()

            NotificationSettingsSection()

            Section {
                NavigationLink {
                    CategorySettingsView()
                } label: {
                    Label("カテゴリ管理", systemImage: "square.grid.2x2")
                }

                NavigationLink {
                    CalendarSettingsContent()
                } label: {
                    Label("カレンダー表示", systemImage: "calendar")
                }
            } header: {
                Text("記録")
            } footer: {
                Text("1日の範囲はスコアの公平性のため 0:00–24:00 に固定しています。")
            }

            Section {
                NavigationLink {
                    VisibilityPresetSettingsView()
                } label: {
                    Label("友達への見え方", systemImage: "eye")
                }
            } header: {
                Text("プライバシー")
            } footer: {
                Text("カテゴリごとの既定の公開相手はカテゴリ管理から、友達ごとのプリセット割り当ては友達詳細から変更できます。")
            }

            Section("外観") {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    Label("テーマ", systemImage: "paintpalette")
                }
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

                Toggle(isOn: $debugDevDataEnabled) {
                    Label("ダミーデータを表示", systemImage: "shippingbox")
                }
                .onChange(of: debugDevDataEnabled) { _, isEnabled in
                    applyDebugSeedToggle(isEnabled)
                }

                Button(role: .destructive) {
                    showCloudUserIDResetConfirmation = true
                } label: {
                    if isResettingCloudUserID {
                        Label("ユーザーIDをリセット中", systemImage: "icloud.and.arrow.down")
                    } else {
                        Label("CloudKitユーザーIDをリセット", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
                .disabled(isResettingCloudUserID)

                if let debugStatusText {
                    Text(debugStatusText)
                        .font(.footnote)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            } header: {
                Text("デバッグ")
            } footer: {
                Text("DEBUGビルド限定です。ダミーデータはデモ由来の予定と実績だけを追加・削除します。ユーザーIDリセットは開発中のCloudKit登録を消して、同じApple IDでID作成をやり直すための操作です。")
            }
            .confirmationDialog("CloudKitユーザーIDをリセットしますか？", isPresented: $showCloudUserIDResetConfirmation, titleVisibility: .visible) {
                Button("リセットする", role: .destructive) {
                    resetCloudUserIDForDebug()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("開発環境のCloudKit登録と端末内のユーザーID情報を消します。友達共有の実機テスト用です。")
            }
            #endif

            Section("アプリ情報") {
                LabeledContent("バージョン", value: versionText)

                if let supportMailURL {
                    Link(destination: supportMailURL) {
                        Label("お問い合わせ", systemImage: "envelope")
                    }
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    #if DEBUG
    private func applyDebugSeedToggle(_ isEnabled: Bool) {
        if isEnabled {
            let didSeedPlans = PreviewSupport.seedPreviewPlansIfNeeded(in: modelContext)
            let didSeedChapters = PreviewSupport.seedDevSampleChaptersIfNeeded(in: modelContext)
            debugStatusText = (didSeedPlans || didSeedChapters)
                ? "ダミーデータを追加しました。"
                : "ダミーデータはすでに最新です。"
        } else {
            let didRemove = PreviewSupport.removeRuntimeSeedData(in: modelContext)
            debugStatusText = didRemove
                ? "ダミーデータを削除しました。"
                : "削除できるダミーデータはありません。"
        }
    }

    private func resetCloudUserIDForDebug() {
        let settings = currentSettings()
        guard !isResettingCloudUserID else { return }
        isResettingCloudUserID = true
        debugStatusText = "CloudKitユーザーIDをリセットしています…"

        Task { @MainActor in
            do {
                let username = settings?.cloudUsernameNormalized.isEmpty == false
                    ? settings?.cloudUsernameNormalized
                    : settings?.cloudUsername
                try await CloudKitSocialStore().resetOwnProfileForDevelopment(username: username)
                if let settings {
                    settings.cloudUsername = ""
                    settings.cloudUsernameNormalized = ""
                    settings.cloudUserRecordName = ""
                    settings.cloudUsernameRegisteredAt = nil
                    settings.updatedAt = Date()
                    try modelContext.save()
                }
                debugStatusText = "CloudKitユーザーIDをリセットしました。"
            } catch {
                debugStatusText = "ユーザーIDリセットに失敗しました: \(error.localizedDescription)"
            }
            isResettingCloudUserID = false
        }
    }

    private func currentSettings() -> UserSettings? {
        settings.first { $0.settingsKey == "default" } ?? settings.first
    }
    #endif
}

// MARK: - iCloud 同期

private struct iCloudSyncSection: View {
    @StateObject private var coordinator = CloudKitSyncCoordinator()

    var body: some View {
        Section {
            LabeledContent {
                Text(statusText)
                    .foregroundStyle(statusColor)
            } label: {
                Label("iCloud同期", systemImage: "icloud")
            }
        } header: {
            Text("同期")
        } footer: {
            Text(footerText)
        }
        .task {
            await coordinator.refreshAccountStatus()
        }
    }

    private var statusText: String {
        switch coordinator.accountState {
        case .unknown:
            return "確認中…"
        case .available:
            return "利用可能"
        case .noAccount:
            return "未サインイン"
        case .restricted:
            return "制限あり"
        case .couldNotDetermine:
            return "確認できません"
        case .temporarilyUnavailable:
            return "一時的に利用不可"
        case .failed:
            return "エラー"
        }
    }

    private var statusColor: Color {
        coordinator.accountState.isAvailable ? LiminalTheme.secondaryText : LiminalTheme.reward
    }

    private var footerText: String {
        coordinator.accountState.userMessage
            ?? "記録は端末に保存され、iCloud経由で同期・バックアップされます。"
    }
}

// MARK: - 通知

private struct NotificationSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(StreakNotificationStore.streakReminderEnabledKey) private var streakReminderEnabled = false
    @State private var showPermissionDeniedAlert = false

    var body: some View {
        Section {
            Toggle(isOn: $streakReminderEnabled) {
                Label("ストリークが途切れそうな日に通知", systemImage: "flame")
            }
            .onChange(of: streakReminderEnabled) { _, newValue in
                applyStreakReminder(enabled: newValue)
            }
        } header: {
            Text("通知")
        } footer: {
            Text("その日のスコアが伸びずストリークが途切れそうな夜に、1件だけそっと知らせます。")
        }
        .alert("通知が許可されていません", isPresented: $showPermissionDeniedAlert) {
            Button("設定を開く") { openSystemSettings() }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("iOSの設定 > Liminalog > 通知 を許可すると、ストリークの通知を受け取れます。")
        }
    }

    private func applyStreakReminder(enabled: Bool) {
        let context = modelContext
        Task { @MainActor in
            let store = StreakNotificationStore(modelContext: context)
            if enabled {
                let granted = await store.requestAuthorization()
                if !granted {
                    streakReminderEnabled = false
                    showPermissionDeniedAlert = true
                    return
                }
            }
            await store.refreshStreakBreakWarning()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
            .liminalogPreviewEnvironment()
    }
}

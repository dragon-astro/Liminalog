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
    private let supportEmailAddress = "yuhlab.dev@gmail.com"

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

                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    Label("ウィジェット", systemImage: "rectangle.grid.2x2")
                }
            } header: {
                Text("記録")
            } footer: {
                Text("1日の範囲はスコアの公平性のため 0:00–24:00 に固定しています。")
            }

            Section {
                NavigationLink {
                    FriendSetSettingsView()
                } label: {
                    Label("友達セット", systemImage: "person.2")
                }

                NavigationLink {
                    VisibilityPresetSettingsView()
                } label: {
                    Label("友達への見え方", systemImage: "eye")
                }

                NavigationLink {
                    BlockedFriendsView()
                } label: {
                    Label("ブロックリスト", systemImage: "nosign")
                }
            } header: {
                Text("プライバシー")
            } footer: {
                Text("友達セットはカテゴリごとの公開相手に使えます。友達ごとの見え方は友達詳細から、ブロックはブロックリストから変更できます。")
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

                NavigationLink {
                    PrivacyPolicyView(supportEmailAddress: supportEmailAddress)
                } label: {
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                }

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

// MARK: - プライバシーポリシー

private struct PrivacyPolicyView: View {
    let supportEmailAddress: String

    private let effectiveDate = "2026年6月7日"

    var body: some View {
        List {
            Section {
                policyParagraph("Liminalogは、日々の記録、習慣、予定、プロフィール、友達共有をユーザー自身が管理するためのアプリです。記録内容はユーザーのプライバシーに深く関わるため、必要な範囲に限って保存・利用します。")
                LabeledContent("施行日", value: effectiveDate)
            }

            Section("保存する情報") {
                policyParagraph("アプリは、記録した時間、カテゴリ、予定、メモ、場所名、気分、プロフィール画像、表示名、ユーザーID、公開設定、友達関係、装飾やテーマなどの設定を保存します。")
                policyParagraph("問い合わせを送る場合、メールアドレス、問い合わせ内容、端末やアプリのバージョン情報がサポート対応に使われることがあります。")
            }

            Section("利用目的") {
                bullet("記録・統計・カレンダー・ウィジェットなど、アプリ機能を提供するため")
                bullet("iCloudを使った同期、バックアップ、友達共有を行うため")
                bullet("ユーザーID検索、友達申請、相互承認した友達との共有範囲を管理するため")
                bullet("不具合調査、問い合わせ対応、サービス改善のため")
            }

            Section("iCloudと友達共有") {
                policyParagraph("記録や設定は端末内およびiCloud/CloudKitに保存されます。iCloudにサインインしていない場合、同期や友達共有の一部機能は利用できないことがあります。")
                policyParagraph("友達共有は、ユーザーID検索と相互承認が成立した相手に対してのみ行われます。共有される内容は、ユーザーが設定した公開範囲に従います。")
                policyParagraph("友達解除またはブロックを行うと、その相手との共有は停止されます。削除やブロック後、同期が完了すると相手側で共有内容は表示されなくなります。")
                policyParagraph("不適切なプロフィールや共有内容、迷惑行為がある場合は、友達プロフィールの通報メニューまたは問い合わせ先から連絡できます。")
            }

            Section("開発者が確認できる範囲") {
                policyParagraph("CloudKitのPrivate DatabaseやShared Databaseに保存されたユーザー本人の記録内容は、原則として開発者ポータルから直接閲覧できません。")
                policyParagraph("ユーザーID検索や友達申請などに必要な公開領域の情報、問い合わせでユーザーが送信した内容、App Store Connectなどで提供される診断情報は確認できる場合があります。")
            }

            Section("第三者提供") {
                policyParagraph("ユーザーの記録内容を広告目的で販売したり、第三者に提供したりすることはありません。法令に基づく場合、ユーザーの同意がある場合、またはアプリ機能の提供に必要な範囲を除き、個人情報を第三者に提供しません。")
            }

            Section("削除と同意の撤回") {
                policyParagraph("ユーザーは、アプリ内の削除操作、友達解除、ブロック、公開設定の変更、iCloud設定の変更により、保存・共有される情報を管理できます。")
                policyParagraph("データ削除やプライバシーに関する相談が必要な場合は、問い合わせ先まで連絡してください。")
            }

            Section("問い合わせ") {
                Text(supportEmailAddress)
                    .textSelection(.enabled)
                policyParagraph("プライバシーポリシーの内容は、機能追加や法令変更に応じて更新されることがあります。重要な変更がある場合は、アプリ内またはApp Store上で案内します。")
            }
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policyParagraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(LiminalTheme.text)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("・")
                .foregroundStyle(LiminalTheme.secondaryText)
            Text(text)
                .foregroundStyle(LiminalTheme.text)
        }
        .font(.body)
    }
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

import SwiftData
import SwiftUI

/// ブロック中の相手を一覧し、解除できる画面。
/// 一覧は CloudKit の自分の同意レコード（status=.blocked）から取得する。
/// そのため「申請取り下げで詰んだ（ローカルには友達が残っていない）」ケースも解除できる。
/// 解除＝CloudKitの自分の同意レコードを削除（再申請可能に戻す）＋ローカルに残るFriendも削除。
struct BlockedFriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allFriends: [Friend]

    @State private var blocked: [CloudFriendConsent] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var unblockingTargets: Set<String> = []
    @State private var actionError: String?

    private let store = CloudKitSocialStore()

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("読み込み中…")
                            .foregroundStyle(LiminalTheme.secondaryText)
                    }
                }
            } else if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            } else if blocked.isEmpty {
                Section {
                    Text("ブロック中の相手はいません。")
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            } else {
                Section {
                    ForEach(blocked, id: \.targetUserRecordName) { consent in
                        row(for: consent)
                    }
                } footer: {
                    Text("解除すると、その相手にもう一度友達申請できるようになります。")
                }
            }
        }
        .navigationTitle("ブロックリスト")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("ブロックを解除できませんでした", isPresented: actionErrorPresented) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func row(for consent: CloudFriendConsent) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: consent))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(consent.targetUsername)")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                unblock(consent)
            } label: {
                if unblockingTargets.contains(consent.targetUserRecordName) {
                    ProgressView()
                } else {
                    Text("解除")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.bordered)
            .disabled(unblockingTargets.contains(consent.targetUserRecordName))
        }
    }

    private func displayName(for consent: CloudFriendConsent) -> String {
        if let friend = localFriend(for: consent.targetUserRecordName),
           !friend.displayName.isEmpty {
            return friend.displayName
        }
        return consent.targetUsername.isEmpty ? "名称未設定" : consent.targetUsername
    }

    private func localFriend(for targetUserRecordName: String) -> Friend? {
        allFriends.first { $0.userRecordID == targetUserRecordName }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            blocked = try await store.blockedConsents()
        } catch {
            blocked = []
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(_ consent: CloudFriendConsent) {
        let target = consent.targetUserRecordName
        guard !target.isEmpty, !unblockingTargets.contains(target) else { return }
        unblockingTargets.insert(target)
        Task { @MainActor in
            do {
                try await store.withdrawOwnConsent(targetUserRecordName: target)
                if let friend = localFriend(for: target) {
                    modelContext.delete(friend)
                    try? modelContext.save()
                }
                blocked.removeAll { $0.targetUserRecordName == target }
            } catch {
                actionError = error.localizedDescription
            }
            unblockingTargets.remove(target)
        }
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding {
            actionError != nil
        } set: { isPresented in
            if !isPresented { actionError = nil }
        }
    }
}

#Preview("Blocked Friends") {
    NavigationStack {
        BlockedFriendsView()
            .liminalogPreviewEnvironment()
    }
}

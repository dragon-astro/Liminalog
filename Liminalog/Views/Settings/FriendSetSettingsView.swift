import SwiftData
import SwiftUI
import UIKit

struct FriendSetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showAddSheet = false
    @State private var editingSet: FriendSet?
    @State private var operationError: String?

    private var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    private var friendByID: [UUID: Friend] {
        Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
    }

    var body: some View {
        List {
            Section {
                if friendSets.isEmpty {
                    FriendSetEmptyRow(
                        text: "友達セットを作ると、カテゴリごとの公開相手をまとめて選べます。",
                        systemImage: "person.2"
                    )
                }

                ForEach(friendSets) { set in
                    Button {
                        editingSet = set
                    } label: {
                        FriendSetSettingsRow(
                            friendSet: set,
                            members: members(in: set)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSets)
                .onMove(perform: moveSets)
            } header: {
                sectionHeader(title: "友達セット") {
                    showAddSheet = true
                }
            } footer: {
                Text("ここで作ったセットは、カテゴリ管理のデフォルト公開相手で使えます。")
            }

            Section {
                if acceptedFriends.isEmpty {
                    FriendSetEmptyRow(
                        text: "承認済みの友達が増えると、セットに追加できます。",
                        systemImage: "person.badge.plus"
                    )
                } else {
                    Text("\(acceptedFriends.count)人の友達をセットに割り当てられます。")
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            } header: {
                Text("対象")
            }
        }
        .navigationTitle("友達セット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            FriendSetEditSheet(friendSet: nil)
        }
        .sheet(item: $editingSet) { set in
            FriendSetEditSheet(friendSet: set)
        }
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK") {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

    private func sectionHeader(title: String, addAction: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: addAction) {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("\(title)を追加")
        }
    }

    private func members(in set: FriendSet) -> [Friend] {
        set.memberFriendIDs.compactMap { friendByID[$0] }
    }

    private func deleteSets(_ indexSet: IndexSet) {
        let deletingSets = indexSet.compactMap { index in
            friendSets.indices.contains(index) ? friendSets[index] : nil
        }
        guard !deletingSets.isEmpty else { return }

        let deletingIDs = Set(deletingSets.map(\.id))
        for category in categories where !category.defaultAudienceFriendSetIDs.isEmpty {
            let nextIDs = category.defaultAudienceFriendSetIDs.filter { !deletingIDs.contains($0) }
            if nextIDs != category.defaultAudienceFriendSetIDs {
                category.defaultAudienceFriendSetIDs = nextIDs
            }
        }

        for set in deletingSets {
            modelContext.delete(set)
        }

        saveChanges("友達セットを削除できませんでした。時間をおいてもう一度試してください。")
    }

    private func moveSets(from source: IndexSet, to destination: Int) {
        var reordered = friendSets
        reordered.move(fromOffsets: source, toOffset: destination)

        let now = Date()
        for (index, set) in reordered.enumerated() {
            set.sortOrder = index
            set.updatedAt = now
        }

        saveChanges("友達セットの並び順を保存できませんでした。時間をおいてもう一度試してください。")
    }

    private func saveChanges(_ message: String) {
        do {
            try modelContext.save()
        } catch {
            operationError = message
        }
    }
}

private struct FriendSetSettingsRow: View {
    let friendSet: FriendSet
    let members: [Friend]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(friendSet.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Text("\(members.count)人")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.tertiaryText)
            }

            if members.isEmpty {
                Label("メンバー未設定", systemImage: "person.crop.circle.badge.plus")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            } else {
                HStack(spacing: 6) {
                    ForEach(members.prefix(5)) { friend in
                        FriendSetMemberBadge(friend: friend)
                    }
                    if members.count > 5 {
                        Text("+\(members.count - 5)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Capsule().fill(LiminalTheme.elevated.opacity(0.75)))
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct FriendSetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameFieldFocused: Bool

    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]

    let friendSet: FriendSet?

    @State private var name = ""
    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var saveError: String?

    private var isNew: Bool { friendSet == nil }

    private var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: 仲良し", text: $name)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }
                }

                Section {
                    if acceptedFriends.isEmpty {
                        FriendSetEmptyRow(
                            text: "承認済みの友達はまだいません。名前だけ保存して、あとからメンバーを追加できます。",
                            systemImage: "person.badge.plus"
                        )
                    } else {
                        ForEach(acceptedFriends) { friend in
                            Button {
                                toggle(friend.id)
                            } label: {
                                HStack(spacing: 12) {
                                    FriendSetAvatar(friend: friend, size: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName.isEmpty ? "名称未設定" : friend.displayName)
                                            .foregroundStyle(LiminalTheme.text)
                                        if !friend.handle.isEmpty {
                                            Text("@\(friend.handle)")
                                                .font(.caption)
                                                .foregroundStyle(LiminalTheme.secondaryText)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: selectedMemberIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedMemberIDs.contains(friend.id) ? LiminalTheme.accent : LiminalTheme.tertiaryText)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("メンバー")
                } footer: {
                    Text("セットを変更すると、今後このセットを使う公開相手に反映されます。既に作成済みの予定や記録の個別公開相手は変更しません。")
                }
            }
            .navigationTitle(isNew ? "友達セットを追加" : "友達セットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { nameFieldFocused = false }
                }
            }
            .onAppear { loadInitialState() }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK") {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented {
                saveError = nil
            }
        }
    }

    private func loadInitialState() {
        guard let friendSet else { return }
        name = friendSet.name
        selectedMemberIDs = Set(friendSet.memberFriendIDs)
    }

    private func toggle(_ id: UUID) {
        if selectedMemberIDs.contains(id) {
            selectedMemberIDs.remove(id)
        } else {
            selectedMemberIDs.insert(id)
        }
    }

    private func save() {
        let now = Date()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberIDs = acceptedFriends
            .map(\.id)
            .filter { selectedMemberIDs.contains($0) }

        if let friendSet {
            friendSet.name = trimmed
            friendSet.memberFriendIDs = memberIDs
            friendSet.updatedAt = now
        } else {
            let nextSortOrder = (friendSets.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(
                FriendSet(
                    name: trimmed,
                    memberFriendIDs: memberIDs,
                    sortOrder: nextSortOrder,
                    now: now
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "友達セットを保存できませんでした。時間をおいてもう一度試してください。"
        }
    }
}

private struct FriendSetMemberBadge: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 4) {
            FriendSetAvatar(friend: friend, size: 22)
            Text(friend.displayName.isEmpty ? "名称未設定" : friend.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
        }
        .padding(.trailing, 7)
        .background(Capsule().fill(Color(hex: friend.accentColorHex).opacity(0.12)))
    }
}

private struct FriendSetAvatar: View {
    let friend: Friend
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: friend.accentColorHex).opacity(0.16))

            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: friend.avatarSystemImage)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(Color(hex: friend.accentColorHex))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(Color(hex: friend.accentColorHex).opacity(0.28), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var profileImage: UIImage? {
        guard let data = friend.profileImageData else { return nil }
        return UIImage(data: data)
    }
}

private struct FriendSetEmptyRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(LiminalTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

#Preview("Friend Set Settings") {
    NavigationStack {
        FriendSetSettingsView()
    }
    .liminalogPreviewEnvironment()
}

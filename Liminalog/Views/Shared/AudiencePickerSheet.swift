import SwiftData
import SwiftUI

struct CategoryAudiencePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

    let category: Category?
    @Binding var friendSetIDs: [UUID]
    @Binding var includedFriendIDs: [UUID]
    @Binding var excludedFriendIDs: [UUID]
    @State private var expandedFriendSetIDs: Set<UUID> = []
    @State private var appliesToPastPlans = false
    @State private var showingPastPlanConfirmation = false
    @State private var pastPlanApplyError: String?
    @State private var searchText = ""

    private var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    private var acceptedFriendIDs: Set<UUID> {
        Set(acceptedFriends.map(\.id))
    }

    private var filteredFriendSets: [FriendSet] {
        filter(friendSets)
    }

    private var filteredAcceptedFriends: [Friend] {
        filter(acceptedFriends)
    }

    private var resolvedIDs: Set<UUID> {
        Set(AudienceResolver.resolve(
            friendSetIDs: friendSetIDs,
            includedFriendIDs: includedFriendIDs,
            excludedFriendIDs: excludedFriendIDs,
            friendSets: friendSets,
            friends: friends
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("友達セット") {
                    if friendSets.isEmpty {
                        Text("友達セットはまだありません")
                            .foregroundStyle(LiminalTheme.secondaryText)
                    } else if filteredFriendSets.isEmpty {
                        AudienceEmptySearchRow()
                    } else {
                        ForEach(filteredFriendSets) { set in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.name)
                                            .foregroundStyle(LiminalTheme.text)
                                        Text("\(members(in: set).count)人")
                                            .font(.caption)
                                            .foregroundStyle(LiminalTheme.secondaryText)
                                    }

                                    Spacer()

                                    Button {
                                        toggleExpandedSet(set.id)
                                    } label: {
                                        Image(systemName: expandedFriendSetIDs.contains(set.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(LiminalTheme.secondaryText)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(expandedFriendSetIDs.contains(set.id) ? "友達セットを閉じる" : "友達セットを開く")

                                    Button {
                                        toggleSet(set.id)
                                    } label: {
                                        RoundAudienceCheckmark(
                                            state: friendSetIDs.contains(set.id) ? .selected : .empty
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if expandedFriendSetIDs.contains(set.id) {
                                    FriendSetMemberPreview(
                                        members: members(in: set)
                                    )
                                }
                            }
                        }
                    }
                }

                Section {
                    if acceptedFriends.isEmpty {
                        Text("承認済みの友達はまだいません")
                            .foregroundStyle(LiminalTheme.secondaryText)
                    } else if filteredAcceptedFriends.isEmpty {
                        AudienceEmptySearchRow()
                    } else {
                        ForEach(filteredAcceptedFriends) { friend in
                            Button {
                                cycle(friend)
                            } label: {
                                HStack(spacing: 12) {
                                    FriendAudienceLabel(friend: friend)
                                    Spacer()
                                    RoundAudienceCheckmark(state: checkState(for: friend))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("個別の友達")
                } footer: {
                    Text("友達セットのメンバーは保存時点ではなく、新規チャプター/予定を作る時点の最新メンバーで展開されます。")
                }

            }
            .safeAreaInset(edge: .bottom) {
                if category != nil {
                    pastPlanApplyFooter
                }
            }
            .navigationTitle("デフォルト公開相手")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "友達やセットを検索")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { complete() }
                }
            }
            .alert("過去の予定に反映しますか？", isPresented: $showingPastPlanConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("反映して完了", role: .destructive) {
                    applyAudienceToPastPlans()
                }
            } message: {
                Text("このカテゴリの過去の予定 \(pastPlanCount)件について、個別に設定していた公開相手も現在のデフォルト公開相手で上書きします。")
            }
            .alert("反映できませんでした", isPresented: pastPlanApplyErrorPresented) {
                Button("OK", role: .cancel) {
                    pastPlanApplyError = nil
                }
            } message: {
                Text(pastPlanApplyError ?? "")
            }
        }
    }

    private var pastPlanApplyFooter: some View {
        Button {
            appliesToPastPlans.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("過去のすべての予定にも反映")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Text(pastPlanCount == 0 ? "対象の過去予定はありません" : "\(pastPlanCount)件の過去予定を完了時に確認して上書きします")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                Spacer()
                RoundAudienceCheckmark(state: appliesToPastPlans ? .selected : .empty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(LiminalTheme.surface)
            .opacity(pastPlanCount == 0 ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(pastPlanCount == 0)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var pastPlanCount: Int {
        pastPlansInCategory.count
    }

    private var pastPlansInCategory: [PlanBlock] {
        guard let category else { return [] }
        let now = Date()
        return (category.plans ?? [])
            .filter { $0.endTime <= now }
            .sorted { $0.startTime < $1.startTime }
    }

    private var pastPlanApplyErrorPresented: Binding<Bool> {
        Binding {
            pastPlanApplyError != nil
        } set: { isPresented in
            if !isPresented {
                pastPlanApplyError = nil
            }
        }
    }

    private func complete() {
        if appliesToPastPlans, pastPlanCount > 0 {
            showingPastPlanConfirmation = true
        } else {
            dismiss()
        }
    }

    private func applyAudienceToPastPlans() {
        let now = Date()
        let audienceFriendIDs = Array(resolvedIDs).sorted { $0.uuidString < $1.uuidString }

        for plan in pastPlansInCategory {
            plan.audienceFriendIDs = audienceFriendIDs
            plan.audienceSource = .categoryDefaultSnapshot
            plan.hasAudienceSnapshot = AudienceSnapshotPolicy.shouldSaveSnapshot(
                isPublic: plan.isPublic,
                audienceSource: .categoryDefaultSnapshot,
                audienceFriendIDs: audienceFriendIDs
            )
            plan.updatedAt = now
        }

        do {
            try modelContext.save()
            CloudFriendShareRefreshCoordinator.requestRefresh(reason: "past plan audience changed")
            dismiss()
        } catch {
            NSLog("Liminalog: failed to apply audience to past plans: \(String(describing: error))")
            modelContext.rollback()
            pastPlanApplyError = error.localizedDescription
        }
    }

    private func toggleSet(_ id: UUID) {
        if friendSetIDs.contains(id) {
            friendSetIDs.removeAll { $0 == id }
        } else {
            appendUnique(id, to: &friendSetIDs)
        }
    }

    private func toggleExpandedSet(_ id: UUID) {
        if expandedFriendSetIDs.contains(id) {
            expandedFriendSetIDs.remove(id)
        } else {
            expandedFriendSetIDs.insert(id)
        }
    }

    private func members(in set: FriendSet) -> [Friend] {
        set.memberFriendIDs.compactMap { id in
            guard acceptedFriendIDs.contains(id) else { return nil }
            return friends.first { $0.id == id }
        }
    }

    private func filter(_ sets: [FriendSet]) -> [FriendSet] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return sets }
        return sets.filter { set in
            set.name.localizedCaseInsensitiveContains(query) ||
                members(in: set).contains { matches($0, query: query) }
        }
    }

    private func filter(_ friends: [Friend]) -> [Friend] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return friends }
        return friends.filter { matches($0, query: query) }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ friend: Friend, query: String) -> Bool {
        friend.displayName.localizedCaseInsensitiveContains(query) ||
            friend.handle.localizedCaseInsensitiveContains(query)
    }

    private func cycle(_ friend: Friend) {
        if excludedFriendIDs.contains(friend.id) {
            excludedFriendIDs.removeAll { $0 == friend.id }
            appendUnique(friend.id, to: &includedFriendIDs)
        } else if includedFriendIDs.contains(friend.id) {
            includedFriendIDs.removeAll { $0 == friend.id }
        } else if resolvedIDs.contains(friend.id) {
            appendUnique(friend.id, to: &excludedFriendIDs)
        } else {
            appendUnique(friend.id, to: &includedFriendIDs)
        }
    }

    private func checkState(for friend: Friend) -> RoundAudienceCheckmark.State {
        if excludedFriendIDs.contains(friend.id) { return .excluded }
        if includedFriendIDs.contains(friend.id) || resolvedIDs.contains(friend.id) { return .selected }
        return .empty
    }
}

struct AudienceSnapshotPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

    @Binding var audienceFriendIDs: [UUID]
    @State private var expandedFriendSetIDs: Set<UUID> = []
    @State private var searchText = ""

    private var acceptedFriends: [Friend] {
        friends.filter { $0.status == .accepted }
    }

    private var filteredFriendSets: [FriendSet] {
        filter(friendSets)
    }

    private var filteredAcceptedFriends: [Friend] {
        filter(acceptedFriends)
    }

    private var acceptedFriendIDs: Set<UUID> {
        Set(acceptedFriends.map(\.id))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("友達セット") {
                    if friendSets.isEmpty {
                        Text("友達セットはまだありません")
                            .foregroundStyle(LiminalTheme.secondaryText)
                    } else if filteredFriendSets.isEmpty {
                        AudienceEmptySearchRow()
                    } else {
                        ForEach(filteredFriendSets) { set in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.name)
                                            .foregroundStyle(LiminalTheme.text)
                                        Text("\(members(in: set).count)人")
                                            .font(.caption)
                                            .foregroundStyle(LiminalTheme.secondaryText)
                                    }

                                    Spacer()

                                    Button {
                                        toggleExpandedSet(set.id)
                                    } label: {
                                        Image(systemName: expandedFriendSetIDs.contains(set.id) ? "chevron.down" : "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(LiminalTheme.secondaryText)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(expandedFriendSetIDs.contains(set.id) ? "友達セットを閉じる" : "友達セットを開く")

                                    Button {
                                        toggleSet(set)
                                    } label: {
                                        RoundAudienceCheckmark(state: checkState(for: set))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(members(in: set).isEmpty)
                                }

                                if expandedFriendSetIDs.contains(set.id) {
                                    FriendSetMemberPreview(members: members(in: set))
                                }
                            }
                        }
                    }
                }

                Section {
                    if acceptedFriends.isEmpty {
                        Text("承認済みの友達はまだいません")
                            .foregroundStyle(LiminalTheme.secondaryText)
                    } else if filteredAcceptedFriends.isEmpty {
                        AudienceEmptySearchRow()
                    } else {
                        ForEach(filteredAcceptedFriends) { friend in
                            Button {
                                toggleFriend(friend.id)
                            } label: {
                                HStack(spacing: 12) {
                                    FriendAudienceLabel(friend: friend)
                                    Spacer()
                                    RoundAudienceCheckmark(state: audienceFriendIDs.contains(friend.id) ? .selected : .empty)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("個別の友達")
                } footer: {
                    Text("友達セットを選ぶと、現在のメンバーをこのチャプター/予定の公開相手として保存します。")
                }
            }
            .navigationTitle("公開相手")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "友達やセットを検索")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func members(in set: FriendSet) -> [Friend] {
        set.memberFriendIDs.compactMap { id in
            guard acceptedFriendIDs.contains(id) else { return nil }
            return friends.first { $0.id == id }
        }
    }

    private func filter(_ sets: [FriendSet]) -> [FriendSet] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return sets }
        return sets.filter { set in
            set.name.localizedCaseInsensitiveContains(query) ||
                members(in: set).contains { matches($0, query: query) }
        }
    }

    private func filter(_ friends: [Friend]) -> [Friend] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return friends }
        return friends.filter { matches($0, query: query) }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ friend: Friend, query: String) -> Bool {
        friend.displayName.localizedCaseInsensitiveContains(query) ||
            friend.handle.localizedCaseInsensitiveContains(query)
    }

    private func checkState(for set: FriendSet) -> RoundAudienceCheckmark.State {
        let memberIDs = members(in: set).map(\.id)
        guard !memberIDs.isEmpty else { return .empty }
        let selectedCount = memberIDs.filter { audienceFriendIDs.contains($0) }.count
        if selectedCount == memberIDs.count { return .selected }
        if selectedCount > 0 { return .mixed }
        return .empty
    }

    private func toggleSet(_ set: FriendSet) {
        let memberIDs = members(in: set).map(\.id)
        guard !memberIDs.isEmpty else { return }
        let isFullySelected = memberIDs.allSatisfy { audienceFriendIDs.contains($0) }
        if isFullySelected {
            audienceFriendIDs.removeAll { memberIDs.contains($0) }
        } else {
            for id in memberIDs {
                appendUnique(id, to: &audienceFriendIDs)
            }
        }
    }

    private func toggleExpandedSet(_ id: UUID) {
        if expandedFriendSetIDs.contains(id) {
            expandedFriendSetIDs.remove(id)
        } else {
            expandedFriendSetIDs.insert(id)
        }
    }

    private func toggleFriend(_ id: UUID) {
        if audienceFriendIDs.contains(id) {
            audienceFriendIDs.removeAll { $0 == id }
        } else {
            appendUnique(id, to: &audienceFriendIDs)
        }
    }
}

struct AudienceSummaryRow: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                Text(count == 0 ? "公開相手なし" : "\(count)人")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.tertiaryText)
        }
    }
}

private struct AudienceEmptySearchRow: View {
    var body: some View {
        Label("該当する相手はありません", systemImage: "magnifyingglass")
            .font(.subheadline)
            .foregroundStyle(LiminalTheme.secondaryText)
    }
}

private struct FriendAudienceLabel: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: friend.avatarSystemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.cachedDisplayHex(friend.accentColorHex))
                .frame(width: 30, height: 30)
                .background(Color.cachedDisplayHex(friend.accentColorHex).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .foregroundStyle(LiminalTheme.text)
                if !friend.handle.isEmpty {
                    Text(friend.handle)
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
    }
}

private struct FriendSetMemberPreview: View {
    let members: [Friend]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if members.isEmpty {
                Text("メンバーなし")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .padding(.leading, 42)
            } else {
                ForEach(members) { friend in
                    HStack(spacing: 10) {
                        Image(systemName: friend.avatarSystemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.cachedDisplayHex(friend.accentColorHex))
                            .frame(width: 24, height: 24)
                            .background(Color.cachedDisplayHex(friend.accentColorHex).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                            if !friend.handle.isEmpty {
                                Text(friend.handle)
                                    .font(.caption2)
                                    .foregroundStyle(LiminalTheme.secondaryText)
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, 42)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct RoundAudienceCheckmark: View {
    enum State {
        case empty
        case selected
        case mixed
        case excluded
    }

    let state: State

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1.5)
                )

            if let symbolName {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var fillColor: Color {
        switch state {
        case .empty:
            return Color.clear
        case .selected, .mixed:
            return LiminalTheme.accent
        case .excluded:
            return .red
        }
    }

    private var strokeColor: Color {
        switch state {
        case .empty:
            return .secondary.opacity(0.5)
        case .selected, .mixed:
            return LiminalTheme.accent
        case .excluded:
            return .red
        }
    }

    private var symbolName: String? {
        switch state {
        case .empty:
            return nil
        case .selected:
            return "checkmark"
        case .mixed:
            return "minus"
        case .excluded:
            return "xmark"
        }
    }
}

private func appendUnique(_ id: UUID, to values: inout [UUID]) {
    guard !values.contains(id) else { return }
    values.append(id)
}

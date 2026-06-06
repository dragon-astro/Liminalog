import SwiftData
import SwiftUI

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding private var pendingInviteURL: URL?

    @Query(sort: \Friend.createdAt) private var friends: [Friend]
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \VisibilityPreset.sortOrder) private var visibilityPresets: [VisibilityPreset]
    @Query private var activeChapters: [Chapter]
    @Query(sort: \Chapter.startTime) private var chapters: [Chapter]
    @Query(sort: \PlanBlock.startTime) private var planBlocks: [PlanBlock]

    @State private var clock = TickClock(interval: 60)
    @State private var rankingDetailPeriod: FriendScorePeriod = .day
    @State private var rankingAnchorDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var isShowingAddFriend = false
    @State private var isShowingProfileShare = false
    @State private var isShowingRankingDetail = false
    @State private var inviteInitialText = ""
    @State private var selectedFriend: Friend?
    @State private var saveError: String?
    @State private var desiredUserID = ""
    @State private var friendSearchUserID = ""
    @State private var cloudStatusText: String?
    @State private var cloudErrorText: String?
    @State private var isRegisteringCloudProfile = false
    @State private var isSendingCloudFriendRequest = false
    @State private var isRefreshingCloudRequests = false
    @State private var didLoadIncomingCloudRequests = false
    @State private var didRegisterCloudKitPushes = false
    @State private var subscribedFriendConsentUserRecordName: String?
    @State private var didSubscribeFriendShares = false

    private let cloudSocialStore = CloudKitSocialStore()
    private let cloudShareStore = CloudFriendShareStore()

    init(pendingInviteURL: Binding<URL?> = .constant(nil)) {
        self._pendingInviteURL = pendingInviteURL
        self._activeChapters = Query(
            filter: #Predicate<Chapter> { $0.endTime == nil },
            sort: [SortDescriptor(\.startTime, order: .reverse)]
        )
    }

    private var settings: UserSettings? {
        settingsList.first
    }

    private var ownDisplayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : name
    }

    private var ownIconFrame: ProfileIconFrameStyle {
        ProfileIconFrameCatalog.item(for: settings?.profileIconFrameID)
    }

    private var ownVisualAccentColor: Color {
        ownIconFrame.primaryColor
    }

    private var ownCardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: settings?.profileCardStyleID)
    }

    private var ownInvitePayload: FriendInvitePayload {
        FriendInvitePayload(
            code: FriendInvitePayload.code(from: settings?.id ?? UUID()),
            displayName: ownDisplayName
        )
    }

    private var acceptedFriends: [Friend] {
        friends
            .filter { $0.status == .accepted }
            .sorted {
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite && !$1.isFavorite
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var pendingIncomingFriends: [Friend] {
        friends
            .filter { $0.status == .pendingIncoming }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var pendingOutgoingFriends: [Friend] {
        friends
            .filter { $0.status == .pendingOutgoing }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeChapter: Chapter? {
        activeChapters.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cloudIdentitySection

                    if !pendingIncomingFriends.isEmpty {
                        requestsSection
                    }

                    if acceptedFriends.isEmpty {
                        emptyState
                    } else {
                        rankingSection
                        friendsListSection
                    }

                    if !pendingOutgoingFriends.isEmpty {
                        outgoingSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(LiminalTheme.canvasGradient)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedFriend) { friend in
                FriendDetailView(
                    friend: friend,
                    onSharingSettingsChanged: { publishAcceptedShareIfPossible(to: $0) }
                )
            }
            .sheet(isPresented: $isShowingAddFriend, onDismiss: {
                inviteInitialText = ""
                pendingInviteURL = nil
            }) {
                FriendAddSheet(
                    initialText: inviteInitialText,
                    onSubmitInvite: addFriendFromInvite
                )
            }
            .sheet(isPresented: $isShowingProfileShare) {
                ProfileShareSheet(payload: ownInvitePayload)
            }
            .sheet(isPresented: $isShowingRankingDetail) {
                FriendRankingListSheet(
                    period: $rankingDetailPeriod,
                    anchorDate: $rankingAnchorDate,
                    entries: rankingEntries(for: rankingDetailPeriod, anchorDate: rankingAnchorDate),
                    onSelectFriend: { friend in
                        selectedFriend = friend
                    }
                )
            }
            .task {
                ensureUserSettings()
                if desiredUserID.isEmpty {
                    desiredUserID = settings?.cloudUsernameNormalized ?? ""
                }
                handlePendingInviteURL()
                registerForCloudKitPushesIfPossible()
                ensureFriendConsentSubscriptionIfPossible()
                ensureFriendShareSubscriptionIfPossible()
                refreshCloudRequestsIfPossible()
                clock.start()
            }
            .onDisappear {
                clock.stop()
            }
            .onChange(of: pendingInviteURL) { _, _ in
                handlePendingInviteURL()
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudKitFriendEventBridge.friendConsentDidChange)) { _ in
                refreshCloudRequests(force: false)
            }
            .alert("友達の変更を保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var cloudIdentitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ユーザーID")
                        .font(.headline.weight(.bold))
                    Text(cloudIdentityDescription)
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isRefreshingCloudRequests {
                    ProgressView()
                        .controlSize(.small)
                } else if hasCloudUsername {
                    Button {
                        refreshCloudRequests(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("友達申請を更新")
                }
            }

            if hasCloudUsername {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("@\(settings?.cloudUsernameNormalized ?? "")")
                            .font(.headline.monospaced().weight(.bold))
                            .foregroundStyle(LiminalTheme.accent)
                        Spacer()
                        Text("変更不可")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LiminalTheme.secondaryText)
                    }

                    HStack(spacing: 10) {
                        TextField("友達のユーザーID", text: $friendSearchUserID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(LiminalTheme.elevated)
                            )

                        Button {
                            sendCloudFriendRequest()
                        } label: {
                            if isSendingCloudFriendRequest {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.badge.plus")
                                    .font(.headline.weight(.bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingCloudFriendRequest || UserIDNormalizer.normalizedValue(friendSearchUserID) == nil)
                        .accessibilityLabel("ユーザーIDで友達申請")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("3文字以上のユーザーID", text: $desiredUserID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LiminalTheme.elevated)
                        )

                    Button {
                        registerCloudUsername()
                    } label: {
                        if isRegisteringCloudProfile {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Label("このIDで確定", systemImage: "checkmark.seal.fill")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRegisteringCloudProfile || UserIDNormalizer.normalizedValue(desiredUserID) == nil)
                }
            }

            if let cloudStatusText {
                Text(cloudStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            if let cloudErrorText {
                Text(cloudErrorText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LiminalTheme.surface)
        )
        .onChange(of: desiredUserID) { _, _ in
            cloudErrorText = nil
            cloudStatusText = nil
        }
        .onChange(of: friendSearchUserID) { _, _ in
            cloudErrorText = nil
            cloudStatusText = nil
        }
    }

    private var hasCloudUsername: Bool {
        !(settings?.cloudUsernameNormalized.isEmpty ?? true)
    }

    private var cloudIdentityDescription: String {
        if hasCloudUsername {
            return "IDで検索して申請し、相互同意になった相手だけ公開設定に従って共有します。"
        }
        return "一度決めたIDは変更できません。友達はこのIDで検索できます。"
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "リクエスト", count: pendingIncomingFriends.count)

            VStack(spacing: 10) {
                ForEach(pendingIncomingFriends) { friend in
                    FriendRequestRow(
                        friend: friend,
                        onAccept: { accept(friend) },
                        onDelete: { delete(friend) }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(ownVisualAccentColor.opacity(0.16))
                        .frame(width: 56, height: 56)
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ownVisualAccentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("プロフィールをシェア")
                        .font(.headline.weight(.bold))
                    Text("リンクかQRでつながる")
                        .font(.subheadline)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }

            Button {
                isShowingProfileShare = true
            } label: {
                Label("プロフィールを共有", systemImage: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LiminalTheme.accent)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                inviteInitialText = ""
                isShowingAddFriend = true
            } label: {
                Label("招待を受け取った", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LiminalTheme.surface)
        )
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "昨日のランキング", count: yesterdayRankingEntries.count)
                Spacer()
                Button {
                    rankingDetailPeriod = .day
                    rankingAnchorDate = Calendar.current.date(byAdding: .day, value: -1, to: clock.now) ?? clock.now
                    isShowingRankingDetail = true
                } label: {
                    HStack(spacing: 5) {
                        Text("もっと見る")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.black))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LiminalTheme.elevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ランキングをもっと見る")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(yesterdayRankingEntries) { entry in
                        Button {
                            if let friend = entry.friend {
                                selectedFriend = friend
                            }
                        } label: {
                            RankingCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(entry.friend != nil)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "今の友達", count: acceptedFriends.count)

            VStack(spacing: 10) {
                ForEach(acceptedFriends) { friend in
                    Button {
                        selectedFriend = friend
                    } label: {
                        FriendRow(friend: friend)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var outgoingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "招待中", count: pendingOutgoingFriends.count)

            VStack(spacing: 10) {
                ForEach(pendingOutgoingFriends) { friend in
                    FriendPendingRow(friend: friend, onDelete: { delete(friend) })
                }
            }
        }
    }

    private var yesterdayRankingEntries: [FriendRankingEntry] {
        rankingEntries(for: .yesterday)
    }

    private func rankingEntries(for period: FriendScorePeriod, anchorDate: Date? = nil) -> [FriendRankingEntry] {
        let selfEntry = FriendRankingEntry(
            id: "me",
            rank: 0,
            name: ownDisplayName,
            imageName: activeChapter?.category?.icon ?? "person.fill",
            tint: ownVisualAccentColor,
            score: selfScore(for: period, anchorDate: anchorDate),
            status: "自分",
            iconFrame: ownIconFrame,
            isMe: true,
            friend: nil
        )

        let friendEntries = acceptedFriends.map { friend in
            FriendRankingEntry(
                id: friend.id.uuidString,
                rank: 0,
                name: friend.displayName,
                imageName: friend.avatarSystemImage,
                tint: Color(hex: friend.accentColorHex),
                score: friend.score(for: period),
                status: friend.currentStatusTitle.isEmpty ? "オフライン" : friend.currentStatusTitle,
                iconFrame: friend.iconFrameStyle,
                isMe: false,
                friend: friend
            )
        }

        let entries = [selfEntry] + friendEntries
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let placements = FriendRankingEngine.placements(
            for: entries.map { entry in
                FriendRankingCandidate(
                    id: entry.id,
                    sortKey: FriendRankingSortKey(
                        stableID: entry.id,
                        score: entry.score,
                        displayName: entry.name,
                        handle: entry.friend?.handle ?? "",
                        isCurrentUser: entry.isMe
                    )
                )
            }
        )

        return placements.compactMap { placement in
            entriesByID[placement.id]?.withRank(placement.rank)
        }
    }

    private func selfScore(for period: FriendScorePeriod, anchorDate: Date?) -> Double {
        switch period {
        case .day:
            return ScoreSnapshotLoader.summary(on: anchorDate ?? clock.now, modelContext: modelContext, now: clock.now).totalScore
        case .today:
            return ScoreSnapshotLoader.summary(on: clock.now, modelContext: modelContext, now: clock.now).totalScore
        case .yesterday:
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: clock.now) else {
                return 0
            }
            return ScoreSnapshotLoader.summary(on: yesterday, modelContext: modelContext, now: clock.now).totalScore
        case .week:
            return averageSelfScore(in: dateInterval(.weekOfYear, containing: anchorDate ?? clock.now))
        case .month:
            return averageSelfScore(in: dateInterval(.month, containing: anchorDate ?? clock.now))
        case .year:
            return averageSelfScore(in: dateInterval(.year, containing: anchorDate ?? clock.now))
        }
    }

    private func averageSelfScore(in interval: DateInterval) -> Double {
        ScoreSnapshotLoader.averageScore(in: interval, modelContext: modelContext, now: clock.now)
    }

    private func dateInterval(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return Calendar.japanese.dateInterval(of: component, for: date) ?? DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
    }

    private func addFriendFromInvite(_ payload: FriendInvitePayload) -> FriendInviteSubmitResult {
        guard payload.code != ownInvitePayload.code else {
            return .failure("自分の招待です")
        }

        if let existing = friends.first(where: { FriendInvitePayload.normalizedCode($0.inviteCode) == payload.code }) {
            if existing.status == .blocked {
                return .failure("ブロック中です")
            }
            selectedFriend = existing
            return .success
        }

        let now = Date()
        let friend = Friend(
            displayName: payload.displayName,
            handle: "@\(payload.code.lowercased())",
            status: .pendingIncoming,
            inviteCode: payload.code,
            shareURL: payload.url.absoluteString,
            now: now
        )
        friend.visibilityPresetID = defaultVisibilityPresetID
        modelContext.insert(friend)
        guard save() else {
            return .failure("保存できませんでした")
        }
        return .success
    }

    private func accept(_ friend: Friend) {
        guard !friend.userRecordID.isEmpty,
              let ownUsername = settings?.cloudUsernameNormalized,
              !ownUsername.isEmpty
        else {
            acceptLocally(friend)
            return
        }

        let requesterUsername = cloudUsername(from: friend)
        Task {
            do {
                try await cloudSocialStore.acceptFriendRequest(
                    from: friend.userRecordID,
                    requesterUsername: requesterUsername,
                    ownUsername: ownUsername,
                    ownDisplayName: ownDisplayName
                )
                await MainActor.run {
                    acceptLocally(friend)
                }
                if let shareURL = incomingShareURL(for: friend) {
                    try await refreshIncomingShare(for: friend, shareURL: shareURL)
                }
                _ = try await publishOutgoingShare(to: friend, consentStatus: .accepted)
                await MainActor.run {
                    cloudStatusText = "@\(requesterUsername) と友達になりました。"
                }
            } catch {
                await MainActor.run {
                    cloudErrorText = error.localizedDescription
                }
            }
        }
    }

    private func acceptLocally(_ friend: Friend) {
        friend.status = .accepted
        friend.acceptedAt = Date()
        friend.updatedAt = Date()
        friend.lastSeenAt = Date()
        if friend.visibilityPresetID == nil {
            friend.visibilityPresetID = defaultVisibilityPresetID
        }
        save()
    }

    private func registerCloudUsername() {
        let targetSettings = settings ?? {
            let created = UserSettings()
            modelContext.insert(created)
            return created
        }()
        let appUserID = targetSettings.id

        isRegisteringCloudProfile = true
        cloudErrorText = nil
        cloudStatusText = nil

        Task {
            do {
                let profile = try await cloudSocialStore.registerProfile(
                    username: desiredUserID,
                    displayName: ownDisplayName,
                    appUserID: appUserID
                )
                await MainActor.run {
                    targetSettings.cloudUsername = profile.username
                    targetSettings.cloudUsernameNormalized = profile.username
                    targetSettings.cloudUserRecordName = profile.ownerUserRecordName
                    targetSettings.cloudUsernameRegisteredAt = Date()
                    targetSettings.updatedAt = Date()
                    if save() {
                        cloudStatusText = "@\(profile.username) を確定しました。"
                        friendSearchUserID = ""
                        registerForCloudKitPushesIfPossible()
                        ensureFriendConsentSubscriptionIfPossible()
                        ensureFriendShareSubscriptionIfPossible()
                    }
                    isRegisteringCloudProfile = false
                }
            } catch {
                await MainActor.run {
                    cloudErrorText = error.localizedDescription
                    isRegisteringCloudProfile = false
                }
            }
        }
    }

    private func sendCloudFriendRequest() {
        guard let ownUsername = settings?.cloudUsernameNormalized, !ownUsername.isEmpty else {
            cloudErrorText = CloudKitSocialError.ownProfileMissing.localizedDescription
            return
        }

        isSendingCloudFriendRequest = true
        cloudErrorText = nil
        cloudStatusText = nil

        Task {
            do {
                let result = try await cloudSocialStore.sendFriendRequest(
                    to: friendSearchUserID,
                    fromOwnUsername: ownUsername,
                    ownDisplayName: ownDisplayName
                )
                let friend = upsertCloudFriend(profile: result.profile, status: result.status)
                friend.shareURL = result.incomingShareURL ?? friend.shareURL
                if save() {
                    selectedFriend = result.status == .accepted ? friend : nil
                    cloudStatusText = result.status == .accepted
                        ? "@\(result.profile.username) と友達になりました。"
                        : "@\(result.profile.username) に申請しました。"
                    friendSearchUserID = ""
                }
                if result.status == .accepted {
                    if let shareURL = incomingShareURL(for: friend) {
                        try await refreshIncomingShare(for: friend, shareURL: shareURL)
                    }
                    _ = try await publishOutgoingShare(to: friend, consentStatus: .accepted)
                }
                await MainActor.run {
                    isSendingCloudFriendRequest = false
                }
            } catch {
                await MainActor.run {
                    cloudErrorText = error.localizedDescription
                    isSendingCloudFriendRequest = false
                }
            }
        }
    }

    private func refreshCloudRequestsIfPossible() {
        guard hasCloudUsername, !didLoadIncomingCloudRequests else { return }
        refreshCloudRequests(force: false)
    }

    private func refreshCloudRequests(force: Bool) {
        guard let ownUserRecordName = settings?.cloudUserRecordName, !ownUserRecordName.isEmpty else { return }
        if isRefreshingCloudRequests { return }
        isRefreshingCloudRequests = true
        if force {
            cloudErrorText = nil
            cloudStatusText = nil
        }

        Task {
            do {
                let incomingConsents = try await cloudSocialStore.incomingConsents(forOwnUserRecordName: ownUserRecordName)
                let outgoingConsents = try await cloudSocialStore.outgoingConsents(forOwnUserRecordName: ownUserRecordName)
                await MainActor.run {
                    let restorations = CloudFriendConsentRestorePolicy.restorations(
                        incomingConsents: incomingConsents,
                        outgoingConsents: outgoingConsents
                    )
                    for restoration in restorations {
                        let status = restoration.status
                        let friend = upsertCloudFriend(
                            consent: restoration.consent,
                            direction: restoration.direction,
                            status: status
                        )
                        if status == .blocked {
                            handleBlockedCloudFriend(friend, direction: restoration.direction)
                            continue
                        }
                        if status == .accepted, let shareURL = incomingShareURL(for: friend) {
                            Task {
                                try? await refreshIncomingShare(for: friend, shareURL: shareURL)
                                _ = try? await publishOutgoingShare(to: friend, consentStatus: .accepted)
                            }
                        }
                    }
                    if save() {
                        didLoadIncomingCloudRequests = true
                        if force {
                            let count = incomingConsents.count + outgoingConsents.count
                            cloudStatusText = count == 0 ? "新しい申請はありません。" : "\(count)件の申請を更新しました。"
                        }
                    }
                    isRefreshingCloudRequests = false
                }
            } catch {
                await MainActor.run {
                    if force {
                        cloudErrorText = error.localizedDescription
                    }
                    isRefreshingCloudRequests = false
                }
            }
        }
    }

    private func handleBlockedCloudFriend(_ friend: Friend, direction _: CloudFriendConsentDirection) {
        friend.status = .blocked
        friend.blockedAt = Date()
        friend.shareURL = nil
        clearIncomingShareData(for: friend)
        friend.updatedAt = Date()
        Task {
            try? await stopCloudSharing(with: friend)
        }
    }

    private func registerForCloudKitPushesIfPossible() {
        guard hasCloudUsername, !didRegisterCloudKitPushes else { return }
        didRegisterCloudKitPushes = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func ensureFriendConsentSubscriptionIfPossible() {
        guard let ownUserRecordName = settings?.cloudUserRecordName, !ownUserRecordName.isEmpty else { return }
        guard subscribedFriendConsentUserRecordName != ownUserRecordName else { return }
        Task {
            do {
                try await cloudSocialStore.ensureConsentSubscriptions(forOwnUserRecordName: ownUserRecordName)
                await MainActor.run {
                    subscribedFriendConsentUserRecordName = ownUserRecordName
                }
            } catch {
                await MainActor.run {
                    if cloudErrorText == nil {
                        cloudErrorText = "友達更新の通知登録に失敗しました: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func ensureFriendShareSubscriptionIfPossible() {
        guard hasCloudUsername, !didSubscribeFriendShares else { return }
        Task {
            do {
                try await cloudShareStore.ensureIncomingShareSubscription()
                await MainActor.run {
                    didSubscribeFriendShares = true
                }
            } catch {
                await MainActor.run {
                    if cloudErrorText == nil {
                        cloudErrorText = "友達共有の通知登録に失敗しました: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    @discardableResult
    private func upsertCloudFriend(profile: CloudFriendProfile, status: FriendStatus) -> Friend {
        let existing = friends.first {
            $0.userRecordID == profile.ownerUserRecordName
                || UserIDNormalizer.normalizedValue($0.handle.replacingOccurrences(of: "@", with: "")) == profile.username
        }
        let friend = existing ?? Friend(displayName: profile.displayName, handle: "@\(profile.username)", status: status)
        if existing == nil {
            modelContext.insert(friend)
        }
        friend.userRecordID = profile.ownerUserRecordName
        friend.displayName = profile.displayName
        friend.handle = "@\(profile.username)"
        friend.inviteCode = profile.username.uppercased()
        friend.status = status
        friend.updatedAt = Date()
        if status == .accepted {
            friend.acceptedAt = Date()
            friend.lastSeenAt = Date()
        }
        if friend.visibilityPresetID == nil {
            friend.visibilityPresetID = defaultVisibilityPresetID
        }
        return friend
    }

    @discardableResult
    private func upsertCloudFriend(
        consent: CloudFriendConsent,
        direction: CloudFriendConsentDirection,
        status: FriendStatus
    ) -> Friend {
        let friendUserRecordName = CloudFriendConsentRestorePolicy.friendUserRecordName(
            from: consent,
            direction: direction
        )
        let friendUsername = CloudFriendConsentRestorePolicy.friendUsername(
            from: consent,
            direction: direction
        )
        let existing = friends.first { $0.userRecordID == friendUserRecordName }
        let friend = existing ?? Friend(
            displayName: CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: direction),
            handle: "@\(friendUsername)",
            status: status
        )
        if existing == nil {
            modelContext.insert(friend)
        }
        friend.userRecordID = friendUserRecordName
        if direction == .incoming || friend.displayName.isEmpty {
            friend.displayName = CloudFriendConsentRestorePolicy.friendDisplayName(from: consent, direction: direction)
        }
        friend.handle = "@\(friendUsername)"
        friend.inviteCode = friendUsername.uppercased()
        friend.shareURL = CloudFriendConsentRestorePolicy.incomingShareURL(
            from: consent,
            direction: direction,
            restoredStatus: status
        ) ?? friend.shareURL
        friend.status = status
        friend.updatedAt = Date()
        if status == .accepted {
            friend.acceptedAt = friend.acceptedAt ?? Date()
            friend.lastSeenAt = Date()
        }
        if friend.visibilityPresetID == nil {
            friend.visibilityPresetID = defaultVisibilityPresetID
        }
        return friend
    }

    private func publishOutgoingShare(
        to friend: Friend,
        consentStatus: CloudFriendConsent.Status
    ) async throws -> URL? {
        guard CloudFriendSharePublishPolicy.shouldPublishOutgoingShare(consentStatus: consentStatus) else {
            return nil
        }
        guard let ownUsername = settings?.cloudUsernameNormalized, !ownUsername.isEmpty else {
            throw CloudKitSocialError.ownProfileMissing
        }
        let targetUsername = cloudUsername(from: friend)
        try await cloudSocialStore.validateCanPublishOwnShare(
            targetUserRecordName: friend.userRecordID,
            status: consentStatus
        )
        let snapshot = outgoingShareSnapshot(for: friend, ownUsername: ownUsername)
        let result = try await cloudShareStore.upsertOutgoingShare(snapshot: snapshot)
        if let shareURL = result.shareURL {
            _ = try await cloudSocialStore.updateOwnConsentShareURL(
                targetUserRecordName: friend.userRecordID,
                ownUsername: ownUsername,
                targetUsername: targetUsername,
                ownDisplayName: ownDisplayName,
                shareURL: shareURL,
                status: consentStatus
            )
            return shareURL
        }
        return nil
    }

    private func refreshIncomingShare(for friend: Friend, shareURL: URL) async throws {
        do {
            let snapshot = try await cloudShareStore.acceptIncomingShare(url: shareURL)
            await MainActor.run {
                applyIncomingShare(snapshot, to: friend)
                save()
            }
        } catch {
            guard CloudFriendShareRefreshFailurePolicy.shouldClearCachedShare(after: error) else {
                throw error
            }
            await MainActor.run {
                clearIncomingShareData(for: friend)
                friend.shareURL = nil
                save()
            }
        }
    }

    private func outgoingShareSnapshot(for friend: Friend, ownUsername: String) -> CloudFriendShareSnapshot {
        let now = clock.now
        var acceptedFriendIDs = Set(acceptedFriends.map(\.id))
        if friend.status == .accepted {
            acceptedFriendIDs.insert(friend.id)
        }
        return CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: ownUsername,
            ownDisplayName: ownDisplayName,
            visibilityPresets: visibilityPresets,
            chapters: chapters,
            planBlocks: planBlocks,
            acceptedFriendIDs: acceptedFriendIDs,
            now: now,
            scoreProvider: { period in
                selfScore(for: period, anchorDate: period == .today || period == .yesterday ? nil : now)
            }
        )
    }

    private func applyIncomingShare(_ snapshot: CloudFriendShareSnapshot, to friend: Friend) {
        CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
    }

    private func clearIncomingShareData(for friend: Friend) {
        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
    }

    private func publishAcceptedShareIfPossible(to friend: Friend) {
        guard friend.status == .accepted, !friend.userRecordID.isEmpty else { return }
        Task {
            do {
                _ = try await publishOutgoingShare(to: friend, consentStatus: .accepted)
            } catch {
                await MainActor.run {
                    cloudErrorText = "公開設定の反映に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopCloudSharing(with friend: Friend) async throws {
        guard !friend.userRecordID.isEmpty else { return }
        try await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friend.userRecordID)
        guard let ownUsername = settings?.cloudUsernameNormalized, !ownUsername.isEmpty else { return }
        _ = try await cloudSocialStore.blockOwnConsent(
            targetUserRecordName: friend.userRecordID,
            ownUsername: ownUsername,
            targetUsername: cloudUsername(from: friend),
            ownDisplayName: ownDisplayName
        )
    }

    private func incomingShareURL(for friend: Friend) -> URL? {
        guard let shareURL = friend.shareURL else { return nil }
        return URL(string: shareURL)
    }

    private func cloudUsername(from friend: Friend) -> String {
        let handle = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return UserIDNormalizer.normalizedValue(rawUsername)
            ?? UserIDNormalizer.normalizedValue(friend.inviteCode)
            ?? friend.userRecordID
    }

    private var defaultVisibilityPresetID: UUID? {
        visibilityPresets.first { $0.builtInKey == "acquaintances" }?.id
            ?? visibilityPresets.first { $0.name == "控えめ" }?.id
    }

    private func delete(_ friend: Friend) {
        guard !friend.userRecordID.isEmpty else {
            modelContext.delete(friend)
            save()
            return
        }
        Task {
            do {
                try await stopCloudSharing(with: friend)
                await MainActor.run {
                    modelContext.delete(friend)
                    save()
                }
            } catch {
                await MainActor.run {
                    cloudErrorText = "友達共有の停止に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save Friend changes: \(String(describing: error))")
            modelContext.rollback()
            saveError = "時間をおいてもう一度試してください。"
            return false
        }
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        let settings = UserSettings()
        modelContext.insert(settings)
        save()
    }

    private func handlePendingInviteURL() {
        guard let pendingInviteURL, FriendInvitePayload(url: pendingInviteURL) != nil else { return }
        inviteInitialText = pendingInviteURL.absoluteString
        isShowingAddFriend = true
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
}

private struct SectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.headline.weight(.bold))
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(LiminalTheme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(LiminalTheme.elevated))
        }
    }
}

private struct RankingCard: View {
    let entry: FriendRankingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                rankBadge
                Spacer()
                scoreBlock(font: .headline.weight(.black))
            }

            HStack(spacing: 8) {
                rankingAvatar

                Text(entry.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(width: 118, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(LiminalTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(entryBorderColor, lineWidth: entry.isMe ? 1.2 : 1)
        )
    }

    private var entryBorderColor: Color {
        entry.isMe ? entry.tint.opacity(0.38) : LiminalTheme.text.opacity(0.05)
    }

    private var rankBadge: some View {
        Group {
            if entry.rank <= 3 {
                HStack(spacing: 5) {
                    Image(systemName: rankSymbol)
                        .font(.caption.weight(.black))
                    Text("#\(entry.rank)")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(rankColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(rankColor.opacity(0.1)))
                .overlay {
                    Capsule()
                        .stroke(rankColor.opacity(0.38), lineWidth: 1)
                }
            } else {
                Text("#\(entry.rank)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .padding(.vertical, 4)
            }
        }
    }

    private func scoreBlock(font: Font) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int(round(entry.score)))")
                .font(font)
                .monospacedDigit()
            Text("pt")
                .font(.caption2.weight(.bold))
                .opacity(0.68)
        }
    }

    private var rankingAvatar: some View {
        DecoratedFriendAvatar(
            systemImage: entry.imageName,
            tint: entry.tint,
            frameStyle: entry.iconFrame,
            size: 30
        )
    }

    private var rankSymbol: String {
        switch entry.rank {
        case 1:
            "crown.fill"
        case 2:
            "medal.fill"
        default:
            "rosette"
        }
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1:
            Color(red: 0.95, green: 0.58, blue: 0.08)
        case 2:
            Color(red: 0.48, green: 0.54, blue: 0.64)
        default:
            Color(red: 0.68, green: 0.40, blue: 0.20)
        }
    }
}

private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 11) {
            FriendAvatar(friend: friend, size: 46)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(friend.displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)

                    if friend.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LiminalTheme.reward)
                    }
                }

                HStack(spacing: 6) {
                    FriendInlineStreak(
                        count: friend.streakCount,
                        systemImage: friend.streakIconStyle.systemImage,
                        tint: Color(hex: friend.streakIconStyle.tintHex)
                    )

                    Text(friendMoodText)
                        .font(.caption2)
                        .foregroundStyle(LiminalTheme.secondaryText.opacity(0.74))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            FriendSquareMetric(
                title: friend.currentStatusTitle.isEmpty ? "オフ" : friend.currentStatusTitle,
                systemImage: friend.currentStatusIcon,
                tint: Color.cachedDisplayHex(friend.currentStatusColorHex)
            )

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(LiminalTheme.elevated))
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(LiminalTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(LiminalTheme.text.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }

    private var friendMoodText: String {
        let mood = friend.currentMoodText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mood.isEmpty ? "ひとこと未設定" : mood
    }
}

private struct FriendInlineStreak: View {
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityLabel("ストリーク \(count)日")
    }
}

private struct FriendSquareMetric: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(height: 15)
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(tint)
        .frame(width: 46, height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct FriendRequestRow: View {
    let friend: Friend
    let onAccept: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: friend, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(friend.inviteCode)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LiminalTheme.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName)の友達申請を承認")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LiminalTheme.elevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName)の友達申請を削除")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(LiminalTheme.surface)
        )
    }
}

private struct FriendPendingRow: View {
    let friend: Friend
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FriendAvatar(friend: friend, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(friend.status.label)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName)への申請を削除")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(LiminalTheme.surface)
        )
    }
}

private struct FriendAvatar: View {
    let friend: Friend
    let size: CGFloat

    var body: some View {
        DecoratedFriendAvatar(
            systemImage: friend.avatarSystemImage,
            tint: Color(hex: friend.accentColorHex),
            frameStyle: friend.iconFrameStyle,
            size: size
        )
    }
}

private struct DecoratedFriendAvatar: View {
    let systemImage: String
    let tint: Color
    let frameStyle: ProfileIconFrameStyle
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(tint)

            ProfileIconFrameView(style: frameStyle, accentColor: tint, size: size + max(7, size * 0.16))
        }
        .frame(width: size + max(7, size * 0.16), height: size + max(7, size * 0.16))
    }
}

private struct FriendCardBackground: View {
    let cardStyle: ProfileCardStyle
    let accentColor: Color
    let cornerRadius: CGFloat

    var body: some View {
        ProfileDecoratedCardBackground(style: cardStyle, accentColor: accentColor, cornerRadius: cornerRadius)
    }
}

private struct FriendDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    let onSharingSettingsChanged: (Friend) -> Void
    @Query(sort: \VisibilityPreset.sortOrder) private var visibilityPresets: [VisibilityPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @State private var isShowingCalendar = false
    @State private var showingBlockConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var saveError: String?

    private let cloudSocialStore = CloudKitSocialStore()
    private let cloudShareStore = CloudFriendShareStore()

    private var settings: UserSettings? {
        settingsList.first
    }

    private var ownDisplayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : name
    }

    private var accentColor: Color {
        Color(hex: friend.accentColorHex)
    }

    private var badge: FriendBadgeDisplay {
        FriendBadgeDisplayCatalog.item(for: friend.profileBadgeID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FriendProfileHero(
                    friend: friend,
                    badge: badge,
                    onCalendar: { isShowingCalendar = true },
                    onFavorite: {
                        friend.isFavorite.toggle()
                        friend.updatedAt = Date()
                        save()
                    }
                )

                FriendProfileStatsRow(friend: friend)

                statusCard
                sharingSettingsCard
                FriendProfileCollectionSection(friend: friend, badge: badge)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(LiminalTheme.canvasGradient)
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingCalendar) {
            FriendCalendarView(friend: friend)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        friend.isFavorite.toggle()
                        friend.updatedAt = Date()
                        save()
                    } label: {
                        Label(friend.isFavorite ? "お気に入りを外す" : "お気に入り", systemImage: friend.isFavorite ? "star.slash" : "star")
                    }

                    Button(role: .destructive) {
                        showingBlockConfirmation = true
                    } label: {
                        Label("ブロック", systemImage: "hand.raised")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LiminalTheme.accent)
                }
                .accessibilityLabel("友達メニュー")
            }
        }
        .confirmationDialog(
            "\(friend.displayName)をブロックしますか？",
            isPresented: $showingBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("ブロック", role: .destructive) {
                blockFriend()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この相手との共有や表示を停止します。")
        }
        .confirmationDialog(
            "\(friend.displayName)を削除しますか？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                deleteFriend()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("友達の変更を保存できませんでした", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func blockFriend() {
        guard !friend.userRecordID.isEmpty else {
            friend.status = .blocked
            friend.blockedAt = Date()
            friend.updatedAt = Date()
            save()
            return
        }
        Task {
            do {
                try await stopCloudSharing(with: friend)
                await MainActor.run {
                    friend.status = .blocked
                    friend.blockedAt = Date()
                    friend.shareURL = nil
                    clearIncomingShareData()
                    friend.updatedAt = Date()
                    save()
                }
            } catch {
                await MainActor.run {
                    saveError = "友達共有の停止に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteFriend() {
        guard !friend.userRecordID.isEmpty else {
            modelContext.delete(friend)
            guard save() else { return }
            dismiss()
            return
        }
        Task {
            do {
                try await stopCloudSharing(with: friend)
                await MainActor.run {
                    modelContext.delete(friend)
                    guard save() else { return }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    saveError = "友達共有の停止に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stopCloudSharing(with friend: Friend) async throws {
        guard !friend.userRecordID.isEmpty else { return }
        try await cloudShareStore.revokeOutgoingShare(targetUserRecordName: friend.userRecordID)
        guard let ownUsername = settings?.cloudUsernameNormalized, !ownUsername.isEmpty else { return }
        _ = try await cloudSocialStore.blockOwnConsent(
            targetUserRecordName: friend.userRecordID,
            ownUsername: ownUsername,
            targetUsername: cloudUsername(from: friend),
            ownDisplayName: ownDisplayName
        )
    }

    private func clearIncomingShareData() {
        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)
    }

    private func cloudUsername(from friend: Friend) -> String {
        let handle = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return UserIDNormalizer.normalizedValue(rawUsername)
            ?? UserIDNormalizer.normalizedValue(friend.inviteCode)
            ?? friend.userRecordID
    }

    private var statusCard: some View {
        HStack(spacing: 13) {
            let statusColor = Color.cachedDisplayHex(friend.currentStatusColorHex)
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                Image(systemName: friend.currentStatusIcon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(friend.currentStatusTitle.isEmpty ? "オフライン" : friend.currentStatusTitle)
                    .font(.headline.weight(.bold))
                Text(friend.lastSeenAt?.japaneseShortDateTime ?? "まだ記録なし")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cachedDisplayHex(friend.currentStatusColorHex).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.cachedDisplayHex(friend.currentStatusColorHex).opacity(0.22), lineWidth: 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if friend.status == .pendingIncoming {
                Button {
                    friend.status = .accepted
                    friend.acceptedAt = Date()
                    friend.updatedAt = Date()
                    save()
                } label: {
                    Label("承認", systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sharingSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)
                    .background(accentColor.opacity(0.14), in: Circle())
                Text("公開設定")
                    .font(.headline.weight(.bold))
            }

            if visibilityPresets.isEmpty {
                Text("見え方プリセットはまだありません")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
            } else {
                Picker("この友達への見え方", selection: visibilityPresetSelection) {
                    ForEach(visibilityPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("この相手に見せるもの")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)

                if categories.isEmpty {
                    Text("カテゴリはまだありません")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                } else {
                    ForEach(categories) { category in
                        Toggle(isOn: categoryAudienceBinding(category)) {
                            Label(category.name, systemImage: category.icon ?? "circle.fill")
                                .foregroundStyle(category.displayColor)
                        }
                    }
                }

                Text("カテゴリ別のデフォルト公開相手と連動します。既存チャプター/予定や個別例外は変更しません。")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LiminalTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var visibilityPresetSelection: Binding<UUID?> {
        Binding {
            friend.visibilityPresetID ?? defaultVisibilityPresetID
        } set: { id in
            friend.visibilityPresetID = id
            friend.updatedAt = Date()
            if save() {
                onSharingSettingsChanged(friend)
            }
        }
    }

    private var defaultVisibilityPresetID: UUID? {
        visibilityPresets.first { $0.builtInKey == "acquaintances" }?.id
            ?? visibilityPresets.first { $0.name == "控えめ" }?.id
    }

    private func categoryAudienceBinding(_ category: Category) -> Binding<Bool> {
        Binding {
            AudienceResolver.categoryDefaultAudience(
                for: category,
                friendSets: friendSets,
                friends: friends
            ).contains(friend.id)
        } set: { isOn in
            if isOn {
                category.defaultAudienceExcludedFriendIDs.removeAll { $0 == friend.id }
                appendUniqueFriendID(friend.id, to: &category.defaultAudienceIncludedFriendIDs)
            } else {
                category.defaultAudienceIncludedFriendIDs.removeAll { $0 == friend.id }
                appendUniqueFriendID(friend.id, to: &category.defaultAudienceExcludedFriendIDs)
            }
            if save() {
                onSharingSettingsChanged(friend)
            }
        }
    }

    private func appendUniqueFriendID(_ id: UUID, to values: inout [UUID]) {
        guard !values.contains(id) else { return }
        values.append(id)
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save Friend detail changes: \(String(describing: error))")
            modelContext.rollback()
            saveError = "時間をおいてもう一度試してください。"
            return false
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

    private var friendMoodText: String {
        let mood = friend.currentMoodText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mood.isEmpty ? (friend.handle.isEmpty ? friend.status.label : friend.handle) : mood
    }
}

private struct FriendProfileHero: View {
    let friend: Friend
    let badge: FriendBadgeDisplay
    let onCalendar: () -> Void
    let onFavorite: () -> Void

    private var accentColor: Color {
        Color(hex: friend.accentColorHex)
    }

    private var moodText: String {
        let mood = friend.currentMoodText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mood.isEmpty { return mood }
        return friend.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? friend.bio ?? "" : "近況はまだありません"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FriendAvatar(friend: friend, size: 92)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(friend.displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if friend.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LiminalTheme.reward)
                    }
                }
                .padding(.trailing, 76)

                FriendBadgePill(badge: badge)

                Text(moodText)
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(2)
                    .frame(minHeight: 42, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background {
            FriendCardBackground(cardStyle: friend.cardStyle, accentColor: accentColor, cornerRadius: 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(friend.cardStyle.borderColor(accentColor: accentColor), lineWidth: friend.cardStyle.borderWidth)
                }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                FriendProfileActionButton(systemImage: "calendar", label: "カレンダー", action: onCalendar)
                FriendProfileActionButton(systemImage: friend.isFavorite ? "star.fill" : "star", label: "お気に入り", action: onFavorite)
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
            .zIndex(2)
        }
    }
}

private struct FriendProfileActionButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .liminalGlassFill(in: Circle())
                .overlay {
                    Circle()
                        .stroke(LiminalTheme.divider.opacity(0.5), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FriendBadgePill: View {
    let badge: FriendBadgeDisplay

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.systemImage)
                .font(.caption2.weight(.bold))
            Text(badge.title)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(Color(hex: badge.tintHex))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(hex: badge.tintHex).opacity(0.12), in: Capsule())
        .lineLimit(1)
    }
}

private struct FriendProfileStatsRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "ストリーク", value: "\(friend.streakCount)日", systemImage: friend.streakIconStyle.systemImage, tint: Color(hex: friend.streakIconStyle.tintHex))
            ProfileStatTile(title: "今月", value: "\(Int(round(friend.monthScore)))pt", systemImage: "star.fill", tint: Color(hex: "#F2994A"))
            ProfileStatTile(title: "年間", value: "\(Int(round(friend.yearScore)))pt", systemImage: "chart.line.uptrend.xyaxis", tint: Color(hex: "#27AE60"))
        }
    }
}

private struct FriendProfileCollectionSection: View {
    let friend: Friend
    let badge: FriendBadgeDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("装備とコレクション")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ProfileEquipmentTile(title: "バッジ", value: badge.title, systemImage: badge.systemImage, tint: Color(hex: badge.tintHex))
                ProfileEquipmentFrameTile(title: "フレーム", value: friend.iconFrameStyle.title, frameStyle: friend.iconFrameStyle)
                ProfileEquipmentCardStyleTile(title: "カード", value: friend.cardStyle.title, cardStyle: friend.cardStyle, accentColor: Color(hex: friend.accentColorHex))
                ProfileEquipmentTile(title: "連続", value: friend.streakIconStyle.title, systemImage: friend.streakIconStyle.systemImage, tint: Color(hex: friend.streakIconStyle.tintHex))
            }
        }
    }
}

private struct FriendBadgeDisplay {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: String
}

private enum FriendBadgeDisplayCatalog {
    static func item(for id: String?) -> FriendBadgeDisplay {
        switch id {
        case ProfileDecorationUnlocks.noNameBadgeID:
            FriendBadgeDisplay(id: ProfileDecorationUnlocks.noNameBadgeID, title: "なし", systemImage: "minus.circle", tintHex: "#8E879F")
        case "first_record":
            FriendBadgeDisplay(id: "first_record", title: "はじめの記録", systemImage: "sparkles", tintHex: "#2F80ED")
        case "three_days":
            FriendBadgeDisplay(id: "three_days", title: "3日記録", systemImage: "calendar.badge.checkmark", tintHex: "#27AE60")
        case "seven_days":
            FriendBadgeDisplay(id: "seven_days", title: "記録7日", systemImage: "calendar.badge.checkmark", tintHex: "#27AE60")
        case "ten_hours":
            FriendBadgeDisplay(id: "ten_hours", title: "10時間", systemImage: "clock.fill", tintHex: "#6C5CE7")
        case "morning":
            FriendBadgeDisplay(id: "morning", title: "朝の記録", systemImage: "sunrise.fill", tintHex: "#F2994A")
        default:
            FriendBadgeDisplay(id: "starter", title: "ルーキー", systemImage: "person.crop.circle.fill.badge.checkmark", tintHex: "#2F80ED")
        }
    }
}

private struct FriendScoreCard: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(LiminalTheme.secondaryText)
            Text("\(Int(round(value)))")
                .font(.title3.weight(.black))
                .monospacedDigit()
            Capsule()
                .fill(tint.opacity(0.24))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                    }
                }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LiminalTheme.surface)
        )
    }
}

private struct FriendCalendarView: View {
    let friend: Friend
    @State private var visibleMonth = FriendCalendarView.currentMonthStart
    @State private var anchorMonth = FriendCalendarView.currentMonthStart
    @State private var scrolledOffset: Int? = 0
    @State private var pageDataByMonth: [Date: CalendarMonthPageData] = [:]
    @State private var showingMonthPicker = false
    @State private var showingSearch = false
    @State private var pickerYear = Calendar.japanese.component(.year, from: Date())
    @State private var pickerMonth = Calendar.japanese.component(.month, from: Date())
    @State private var selectedDay: FriendSharedCalendarTargetDay?

    private let calendar = Calendar.japanese
    private let weekdays = Calendar.japaneseShortWeekdaySymbols
    private let monthOffsets = Array(-480...480)

    private static var currentMonthStart: Date {
        let cal = Calendar.japanese
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarTopBar

            CalendarWeekdayHeader(
                weekdays: weekdays,
                weekdayColor: weekdayColor(_:)
            )

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(monthOffsets, id: \.self) { offset in
                        CalendarMonthGrid(
                            pageData: cachedPageData(for: month(forOffset: offset)),
                            onOpenDay: { date, _ in
                                selectedDay = FriendSharedCalendarTargetDay(date: date)
                            }
                        )
                        .padding(.vertical, 8)
                        .containerRelativeFrame(.horizontal)
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledOffset, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear {
                ensureData(around: scrolledOffset ?? 0)
            }
            .onChange(of: scrolledOffset) { _, newValue in
                handleScroll(to: newValue)
            }
        }
        .background(LiminalTheme.canvasGradient)
        .navigationTitle("\(friend.displayName)のカレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMonthPicker) {
            CalendarMonthPickerSheet(
                selectedYear: $pickerYear,
                selectedMonth: $pickerMonth,
                yearRange: calendarYearRange,
                onCancel: { showingMonthPicker = false },
                onDone: {
                    applyPickedMonth()
                    showingMonthPicker = false
                }
            )
        }
        .sheet(isPresented: $showingSearch) {
            FriendSharedPlanSearchSheet(friend: friend) { plan in
                jump(to: plan.startTime)
                showingSearch = false
                let target = FriendSharedCalendarTargetDay(date: plan.startTime)
                DispatchQueue.main.async {
                    selectedDay = target
                }
            }
        }
        .sheet(item: $selectedDay) { target in
            NavigationStack {
                FriendSharedCalendarDayPagerSheet(friend: friend, initialDate: target.date)
            }
            .presentationDetents([.large])
        }
    }

    private var calendarTopBar: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Button {
                prepareMonthPicker()
                showingMonthPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(visibleMonth.japaneseYearMonth)
                        .font(.title2.weight(.semibold))
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .foregroundStyle(LiminalTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LiminalTheme.elevated)
                )
                .overlay(
                    Capsule()
                        .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("表示月 \(visibleMonth.japaneseYearMonth)")

            Button {
                showingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("友達の予定を検索")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(LiminalTheme.surface)
    }

    private var calendarYearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 10)...(currentYear + 10)
    }

    private var monthGridDates: [Date] {
        monthGridDates(for: visibleMonth)
    }

    private func monthGridDates(for month: Date) -> [Date] {
        let monthStart = monthStart(for: month)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let dayCount = calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = (weekdayOffset + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        let weekCount = max(5, min(6, Int(ceil(Double(normalizedOffset + dayCount) / 7.0))))
        return (0..<(weekCount * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    // MARK: - ページング / データ取得（遅延・月単位キャッシュ）

    private func month(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
    }

    private func offset(forMonth month: Date) -> Int {
        calendar.dateComponents([.month], from: anchorMonth, to: monthStart(for: month)).month ?? 0
    }

    private func handleScroll(to newValue: Int?) {
        guard let newValue else { return }
        let month = month(forOffset: newValue)
        if visibleMonth != month {
            visibleMonth = month
        }
        ensureData(around: newValue)
    }

    private func jump(to date: Date) {
        let targetMonth = monthStart(for: date)
        let targetOffset = offset(forMonth: targetMonth)
        visibleMonth = targetMonth
        ensureData(around: targetOffset)
        scrolledOffset = targetOffset
    }

    private func ensureData(around offset: Int) {
        for off in (offset - 1)...(offset + 1) {
            let key = monthStart(for: month(forOffset: off))
            if pageDataByMonth[key] == nil {
                pageDataByMonth[key] = computePageData(for: month(forOffset: off))
            }
        }
    }

    private func cachedPageData(for month: Date) -> CalendarMonthPageData {
        if let cached = pageDataByMonth[monthStart(for: month)] {
            return cached
        }
        return computePageData(for: month)
    }

    private func computePageData(for month: Date) -> CalendarMonthPageData {
        let dates = monthGridDates(for: month)
        // sharedPlans は呼ぶたびにJSONデコードが走るため、1ページにつき1回だけ取得する。
        let allPlans = friend.sharedPlans
        var importantPlansByDay: [Date: [CalendarDisplayPlan]] = [:]
        var scoreSummariesByDay: [Date: CalendarDisplayScore] = [:]

        for date in dates {
            let dayStart = calendar.startOfDay(for: date)
            let importantPlans = allPlans
                .filter { $0.overlaps(day: date) && $0.showsInCalendarAsImportant }
                .sorted {
                    if $0.startTime == $1.startTime {
                        return $0.updatedAt < $1.updatedAt
                    }
                    return $0.startTime < $1.startTime
                }
                .map(displayPlan(from:))
            let score = knownScore(on: date)
            // 重要予定もスコアも無い日はセル側がデフォルト（スコアなし/空）で描くため、計算を省く。
            guard !importantPlans.isEmpty || score != nil else { continue }
            if !importantPlans.isEmpty {
                importantPlansByDay[dayStart] = importantPlans
            }
            if let score {
                scoreSummariesByDay[dayStart] = CalendarDisplayScore(value: score.value, hasData: score.hasSharedData)
            }
        }

        return CalendarMonthPageData(
            dates: dates,
            visibleMonth: month,
            importantPlansByDay: importantPlansByDay,
            scoreSummariesByDay: scoreSummariesByDay,
            didFailToLoadRecords: false
        )
    }

    private func displayPlan(from plan: FriendSharedPlanSnapshot) -> CalendarDisplayPlan {
        CalendarDisplayPlan(
            id: plan.id,
            title: plan.title,
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.categoryColorHex,
            createdAt: plan.updatedAt
        )
    }

    private func prepareMonthPicker() {
        pickerYear = calendar.component(.year, from: visibleMonth)
        pickerMonth = calendar.component(.month, from: visibleMonth)
    }

    private func applyPickedMonth() {
        let components = DateComponents(year: pickerYear, month: pickerMonth, day: 1)
        jump(to: calendar.date(from: components) ?? visibleMonth)
    }

    private func knownScore(on date: Date) -> FriendCalendarScore? {
        if calendar.isDateInToday(date) {
            return FriendCalendarScore(value: friend.todayScore, hasSharedData: true)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(date, inSameDayAs: yesterday) {
            return FriendCalendarScore(value: friend.yesterdayScore, hasSharedData: true)
        }
        return nil
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func weekdayColor(_ weekday: String) -> Color {
        switch weekday {
        case "日": .red
        case "土": .blue
        default: .secondary
        }
    }
}

private struct FriendCalendarScore {
    let value: Double
    let hasSharedData: Bool
}

private struct FriendSharedCalendarTargetDay: Identifiable, Hashable {
    let date: Date

    var id: TimeInterval {
        Calendar.japanese.startOfDay(for: date).timeIntervalSince1970
    }
}

private struct FriendSharedCalendarDayPagerSheet: View {
    let friend: Friend

    @State private var anchorDate: Date
    @State private var selectedOffset = 0

    init(friend: Friend, initialDate: Date) {
        self.friend = friend
        _anchorDate = State(initialValue: Calendar.japanese.startOfDay(for: initialDate))
    }

    var body: some View {
        TabView(selection: $selectedOffset) {
            ForEach([-1, 0, 1], id: \.self) { offset in
                FriendSharedCalendarDayView(
                    friend: friend,
                    date: pageDate(offset),
                    allowsDayNavigation: false,
                    showsNavigationTitle: false
                )
                .id(pageDate(offset).timeIntervalSince1970)
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selectedOffset) { _, newValue in
            guard newValue != 0 else { return }
            settlePageShift(newValue)
        }
        .navigationTitle(anchorDate.japaneseMonthDayShortWeekday)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pageDate(_ offset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate
    }

    private func settlePageShift(_ offset: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            anchorDate = pageDate(offset)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedOffset = 0
            }
        }
    }
}

private struct FriendSharedCalendarDayView: View {
    let friend: Friend?
    @State private var date: Date
    var plans: [FriendSharedPlanSnapshot]? = nil
    var activities: [FriendSharedActivitySnapshot]? = nil
    var score: FriendCalendarScore? = nil
    var accentColor: Color? = nil
    var allowsDayNavigation = true
    var showsNavigationTitle = true

    init(
        friend: Friend?,
        date: Date,
        plans: [FriendSharedPlanSnapshot]? = nil,
        activities: [FriendSharedActivitySnapshot]? = nil,
        score: FriendCalendarScore? = nil,
        accentColor: Color? = nil,
        allowsDayNavigation: Bool = true,
        showsNavigationTitle: Bool = true
    ) {
        self.friend = friend
        self.plans = plans
        self.activities = activities
        self.score = score
        self.accentColor = accentColor
        self.allowsDayNavigation = allowsDayNavigation
        self.showsNavigationTitle = showsNavigationTitle
        _date = State(initialValue: date)
    }

    private var resolvedPlans: [FriendSharedPlanSnapshot] {
        if let plans { return plans }
        return friend?.sharedPlans.filter { $0.overlaps(day: date) }.sorted { $0.startTime < $1.startTime } ?? []
    }

    private var resolvedActivities: [FriendSharedActivitySnapshot] {
        if let activities { return activities }
        return friend?.sharedActivities.filter { $0.overlaps(day: date) }.sorted { $0.startTime < $1.startTime } ?? []
    }

    private var resolvedScore: FriendCalendarScore? {
        if let score { return score }
        guard let friend else { return nil }
        let calendar = Calendar.japanese
        if calendar.isDateInToday(date) {
            return FriendCalendarScore(value: friend.todayScore, hasSharedData: true)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(date, inSameDayAs: yesterday) {
            return FriendCalendarScore(value: friend.yesterdayScore, hasSharedData: true)
        }
        return nil
    }

    private var tint: Color {
        accentColor ?? Color(hex: friend?.accentColorHex ?? "#2F80ED")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                importantPlansCard
                scoreCard
                FriendSharedTimelineView(
                    date: date,
                    plans: resolvedPlans.filter { !$0.isAllDay },
                    activities: resolvedActivities,
                    accentColor: tint
                )
            }
            .padding(16)
        }
        .background(LiminalTheme.canvasGradient)
        .modifier(FriendDayNavigationTitleModifier(isEnabled: showsNavigationTitle, title: date.japaneseMonthDayShortWeekday))
        .modifier(FriendDayNavigationGestureModifier(isEnabled: allowsDayNavigation, shiftDay: shiftDay(_:)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date.japaneseMonthDayShortWeekday)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(LiminalTheme.surface))
    }

    private var scoreCard: some View {
        HStack {
            Label("スコア", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)
            Spacer()
            Text(resolvedScore.map { "\(Int($0.value.rounded()))" } ?? "-")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.2), lineWidth: 1))
    }

    @ViewBuilder
    private var importantPlansCard: some View {
        let importantPlans = resolvedPlans.filter(\.showsInCalendarAsImportant)
        if !importantPlans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiminalTheme.reward)
                    Text("重要な予定")
                        .font(.headline)
                }

                ForEach(importantPlans) { plan in
                    FriendSharedPlanRow(plan: plan)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(LiminalTheme.surface))
        }
    }

    private func shiftDay(_ value: Int) {
        date = Calendar.japanese.date(byAdding: .day, value: value, to: date) ?? date
    }
}

private struct FriendDayNavigationTitleModifier: ViewModifier {
    let isEnabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

private struct FriendDayNavigationGestureModifier: ViewModifier {
    let isEnabled: Bool
    let shiftDay: (Int) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            shiftDay(1)
                        } else if value.translation.width > 50 {
                            shiftDay(-1)
                        }
                    }
            )
        } else {
            content
        }
    }
}

private struct FriendSharedTimelineView: View {
    let date: Date
    let plans: [FriendSharedPlanSnapshot]
    let activities: [FriendSharedActivitySnapshot]
    let accentColor: Color

    var body: some View {
        SharedTimelineReadOnlyView(
            date: date,
            title: "1日のタイムライン",
            planSnapshots: plans.map { plan in
                TimelineDisplaySnapshot(
                    id: "friend-plan:\(plan.id.uuidString)",
                    sourceID: plan.id,
                    start: plan.startTime,
                    end: plan.endTime,
                    title: plan.title,
                    categoryName: plan.categoryTitle.isEmpty ? plan.title : plan.categoryTitle,
                    categoryIconName: plan.categoryIconName,
                    categoryColorHex: plan.categoryColorHex
                )
            },
            actualSnapshots: activities.map { activity in
                TimelineDisplaySnapshot(
                    id: "friend-activity:\(activity.id.uuidString)",
                    sourceID: activity.id,
                    start: activity.startTime,
                    end: activity.endTime,
                    title: activity.title,
                    categoryName: activity.categoryTitle.isEmpty ? activity.title : activity.categoryTitle,
                    categoryIconName: activity.categoryIconName,
                    categoryColorHex: activity.categoryColorHex,
                    note: activity.note,
                    mood: activity.mood,
                    locationName: activity.locationName
                )
            }
        )
        .tint(accentColor)
    }
}

private struct FriendSharedPlanRow: View {
    let plan: FriendSharedPlanSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.categoryIconName)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.cachedDisplayHex(plan.categoryColorHex))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.cachedDisplayHex(plan.categoryColorHex).opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeText: String {
        if plan.isAllDay {
            return "終日"
        }
        return "\(plan.startTime.shortTime) - \(plan.endTime.shortTime)"
    }
}

private struct FriendSharedPlanSearchSheet: View {
    let friend: Friend
    let onOpenPlan: (FriendSharedPlanSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPlans: [FriendSharedPlanSnapshot] {
        guard !trimmedQuery.isEmpty else { return [] }
        return friend.sharedPlans
            .filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if friend.sharedPlans.isEmpty {
                            ContentUnavailableView(
                                "共有予定はまだありません",
                                systemImage: "calendar",
                                description: Text("相手が予定を共有すると、ここから探せます")
                            )
                            .padding(.top, 72)
                        } else if trimmedQuery.isEmpty {
                            ContentUnavailableView(
                                "予定名を入力",
                                systemImage: "magnifyingglass",
                                description: Text("検索欄に入力すると共有予定を表示します")
                            )
                            .padding(.top, 72)
                        } else if filteredPlans.isEmpty {
                            ContentUnavailableView(
                                "該当する共有予定はありません",
                                systemImage: "magnifyingglass",
                                description: Text("別の予定名で検索してください")
                            )
                            .padding(.top, 72)
                        } else {
                            ForEach(filteredPlans) { plan in
                                Button {
                                    onOpenPlan(plan)
                                } label: {
                                    FriendSharedPlanSearchRow(plan: plan)
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }

                Text(searchResultText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LiminalTheme.surface)
            }
            .navigationTitle("共有予定を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var searchResultText: String {
        if friend.sharedPlans.isEmpty { return "共有予定はまだありません" }
        if trimmedQuery.isEmpty { return "予定名を入力してください" }
        if filteredPlans.isEmpty { return "該当する共有予定はありません" }
        return "\(filteredPlans.count)件見つかりました"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(LiminalTheme.secondaryText)

            TextField("予定名で検索", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title3.weight(.medium))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Capsule().fill(LiminalTheme.surface))
        .overlay(Capsule().stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1))
    }
}

private struct FriendSharedPlanSearchRow: View {
    let plan: FriendSharedPlanSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.startTime.japaneseYear)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                Text(plan.startTime.japaneseMonthDayShortWeekday)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.cachedDisplayHex(plan.categoryColorHex))
                        .frame(width: 6, height: 6)
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var timeText: String {
        if plan.isAllDay { return "終日" }
        return "\(plan.startTime.shortTime) - \(plan.endTime.shortTime)"
    }
}

private struct FriendAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSubmitInvite: (FriendInvitePayload) -> FriendInviteSubmitResult

    @State private var receivedText: String
    @State private var errorText: String?

    init(
        initialText: String,
        onSubmitInvite: @escaping (FriendInvitePayload) -> FriendInviteSubmitResult
    ) {
        self.onSubmitInvite = onSubmitInvite
        self._receivedText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    receiveCard
                }
                .padding(18)
            }
            .background(LiminalTheme.canvasGradient)
            .navigationTitle("招待を受け取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var receiveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("受け取った招待")
                .font(.headline.weight(.bold))

            TextField("リンクまたはコード", text: $receivedText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(13)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LiminalTheme.elevated)
                )

            Text(inviteInputHint)
                .font(.caption)
                .foregroundStyle(LiminalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Button {
                submit()
            } label: {
                Label("追加", systemImage: "plus")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(invitePayload == nil)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LiminalTheme.surface)
        )
        .onChange(of: receivedText) { _, _ in
            errorText = nil
        }
    }

    private func submit() {
        guard let payload = invitePayload else {
            errorText = "招待を読み取れません"
            return
        }

        switch onSubmitInvite(payload) {
        case .success:
            dismiss()
        case .failure(let message):
            errorText = message
        }
    }

    private var trimmedReceivedText: String {
        receivedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var invitePayload: FriendInvitePayload? {
        FriendInvitePayload(text: receivedText)
    }

    private var inviteInputHint: String {
        if trimmedReceivedText.isEmpty {
            return "共有されたリンク、または招待コードを入力してください。"
        }
        if invitePayload == nil {
            return "Liminalogの招待リンクかコードを入力してください。"
        }
        return "この招待を追加できます。"
    }
}

private enum FriendInviteSubmitResult {
    case success
    case failure(String)
}

private struct FriendRankingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var period: FriendScorePeriod
    @Binding var anchorDate: Date
    let entries: [FriendRankingEntry]
    let onSelectFriend: (Friend) -> Void
    @State private var isShowingPeriodPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("期間", selection: $period) {
                    ForEach(FriendScorePeriod.detailCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Button {
                    isShowingPeriodPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(RankingPeriodFormatter.label(for: period, anchorDate: anchorDate))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(LiminalTheme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(LiminalTheme.surface))
                }
                .buttonStyle(.plain)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            Button {
                                if let friend = entry.friend {
                                    dismiss()
                                    onSelectFriend(friend)
                                }
                            } label: {
                                FriendRankingListRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .background(LiminalTheme.canvasGradient)
            .navigationTitle("ランキング")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingPeriodPicker) {
                FriendRankingPeriodPickerSheet(period: period, anchorDate: $anchorDate)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FriendRankingPeriodPickerSheet: View {
    let period: FriendScorePeriod
    @Binding var anchorDate: Date

    var body: some View {
        PeriodRangeSelectionSheet(
            title: "期間を選択",
            granularity: period.rangePickerGranularity,
            anchorDate: $anchorDate
        )
    }
}

private extension FriendScorePeriod {
    var rangePickerGranularity: PeriodRangeGranularity {
        switch self {
        case .day, .today, .yesterday:
            .day
        case .week:
            .week
        case .month:
            .month
        case .year:
            .year
        }
    }
}

private enum RankingPeriodFormatter {
    static func label(for period: FriendScorePeriod, anchorDate: Date) -> String {
        let calendar = Calendar.japanese
        switch period {
        case .day:
            let year = calendar.component(.year, from: anchorDate)
            let month = calendar.component(.month, from: anchorDate)
            let day = calendar.component(.day, from: anchorDate)
            return "\(year)年\(month)月\(day)日"
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate) ?? DateInterval(start: anchorDate, duration: 7 * 24 * 60 * 60)
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let year = calendar.component(.year, from: interval.start)
            let startMonth = calendar.component(.month, from: interval.start)
            let startDay = calendar.component(.day, from: interval.start)
            let endMonth = calendar.component(.month, from: end)
            let endDay = calendar.component(.day, from: end)
            return "\(year) \(startMonth)/\(startDay)-\(endMonth)/\(endDay)"
        case .month:
            let year = calendar.component(.year, from: anchorDate)
            let month = calendar.component(.month, from: anchorDate)
            return "\(year)年\(month)月"
        case .year:
            return "\(calendar.component(.year, from: anchorDate))年"
        case .today:
            return "今日"
        case .yesterday:
            return "昨日"
        }
    }
}

private struct FriendRankingListRow: View {
    let entry: FriendRankingEntry

    var body: some View {
        HStack(spacing: 12) {
            rankLabel

            DecoratedFriendAvatar(
                systemImage: entry.imageName,
                tint: entry.tint,
                frameStyle: entry.iconFrame,
                size: 38
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(entry.isMe ? "自分" : entry.status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(round(entry.score)))")
                    .font(.headline.weight(.black))
                    .monospacedDigit()
                Text("score")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(width: 12)
                .opacity(entry.friend == nil ? 0 : 1)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LiminalTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(entryBorderColor, lineWidth: entry.isMe ? 1.3 : 1)
        )
    }

    private var entryBorderColor: Color {
        entry.isMe ? entry.tint.opacity(0.5) : LiminalTheme.text.opacity(0.06)
    }

    private var rankLabel: some View {
        Text("#\(entry.rank)")
            .font(.caption.weight(.black))
            .foregroundStyle(rankColor)
            .frame(width: 38, height: 28)
            .background(Capsule().fill(rankColor.opacity(entry.rank <= 3 ? 0.14 : 0.08)))
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1:
            Color(red: 0.95, green: 0.58, blue: 0.08)
        case 2:
            Color(red: 0.48, green: 0.54, blue: 0.64)
        case 3:
            Color(red: 0.68, green: 0.40, blue: 0.20)
        default:
            .secondary
        }
    }
}

private struct FriendRankingEntry: Identifiable {
    let id: String
    let rank: Int
    let name: String
    let imageName: String
    let tint: Color
    let score: Double
    let status: String
    let iconFrame: ProfileIconFrameStyle
    let isMe: Bool
    let friend: Friend?

    func withRank(_ rank: Int) -> FriendRankingEntry {
        FriendRankingEntry(
            id: id,
            rank: rank,
            name: name,
            imageName: imageName,
            tint: tint,
            score: score,
            status: status,
            iconFrame: iconFrame,
            isMe: isMe,
            friend: friend
        )
    }
}

private extension Friend {
    var iconFrameStyle: ProfileIconFrameStyle {
        ProfileIconFrameCatalog.item(for: profileIconFrameID)
    }

    var streakIconStyle: ProfileStreakIconStyle {
        ProfileStreakIconCatalog.item(for: profileStreakIconID)
    }

    var cardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: profileCardStyleID)
    }
}

#Preview("Friends") {
    FriendsView()
        .liminalogPreviewEnvironment()
}

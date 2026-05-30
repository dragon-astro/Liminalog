import SwiftData
import SwiftUI

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding private var pendingInviteURL: URL?

    @Query(sort: \Friend.createdAt) private var friends: [Friend]
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query private var chapters: [Chapter]
    @Query private var plans: [PlanBlock]

    @State private var clock = TickClock(interval: 30)
    @State private var rankingDetailPeriod: FriendScorePeriod = .week
    @State private var isShowingAddFriend = false
    @State private var isShowingProfileShare = false
    @State private var isShowingRankingDetail = false
    @State private var inviteInitialText = ""
    @State private var selectedFriend: Friend?

    init(pendingInviteURL: Binding<URL?> = .constant(nil)) {
        self._pendingInviteURL = pendingInviteURL
    }

    private var settings: UserSettings? {
        settingsList.first
    }

    private var ownDisplayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : name
    }

    private var ownAccentColorHex: String {
        settings?.profileAccentColorHex ?? "#2F80ED"
    }

    private var ownIconFrame: ProfileIconFrameStyle {
        ProfileIconFrameCatalog.item(for: settings?.profileIconFrameID)
    }

    private var ownCardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: settings?.profileCardStyleID)
    }

    private var ownInvitePayload: FriendInvitePayload {
        FriendInvitePayload(
            code: FriendInvitePayload.code(from: settings?.id ?? UUID()),
            displayName: ownDisplayName,
            accentColorHex: ownAccentColorHex
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
        chapters
            .filter { $0.endTime == nil }
            .sorted { $0.startTime > $1.startTime }
            .first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedFriend) { friend in
                FriendDetailView(friend: friend)
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
                    entries: rankingEntries(for: rankingDetailPeriod),
                    onSelectFriend: { friend in
                        selectedFriend = friend
                    }
                )
            }
            .task {
                ensureUserSettings()
                handlePendingInviteURL()
                clock.start()
            }
            .onDisappear {
                clock.stop()
            }
            .onChange(of: pendingInviteURL) { _, _ in
                handlePendingInviteURL()
            }
        }
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
                        .fill(Color(hex: ownAccentColorHex).opacity(0.16))
                        .frame(width: 56, height: 56)
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(hex: ownAccentColorHex))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("プロフィールをシェア")
                        .font(.headline.weight(.bold))
                    Text("リンクかQRでつながる")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                            .fill(Color(hex: ownAccentColorHex))
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
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "昨日のランキング", count: yesterdayRankingEntries.count)
                Spacer()
                Button {
                    rankingDetailPeriod = .week
                    isShowingRankingDetail = true
                } label: {
                    HStack(spacing: 5) {
                        Text("もっと見る")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.black))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
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
                        .disabled(entry.friend == nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "友達", count: acceptedFriends.count)

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

    private func rankingEntries(for period: FriendScorePeriod) -> [FriendRankingEntry] {
        let selfEntry = FriendRankingEntry(
            id: "me",
            rank: 0,
            name: ownDisplayName,
            imageName: activeChapter?.category?.icon ?? "person.fill",
            tint: Color(hex: ownAccentColorHex),
            score: selfScore(for: period),
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

        return ([selfEntry] + friendEntries)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .enumerated()
            .map { index, entry in
                entry.withRank(index + 1)
            }
    }

    private func selfScore(for period: FriendScorePeriod) -> Double {
        switch period {
        case .today:
            return score(on: clock.now).totalScore
        case .yesterday:
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: clock.now) else {
                return 0
            }
            return score(on: yesterday).totalScore
        case .week:
            return averageSelfScore(days: 7)
        case .month:
            return averageSelfScore(days: 30)
        case .year:
            return averageSelfScore(days: 365)
        }
    }

    private func averageSelfScore(days: Int) -> Double {
        let scores = (0..<days).compactMap { offset -> Double? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: clock.now) else {
                return nil
            }
            let summary = score(on: date)
            return summary.plannedDuration > 0 ? summary.totalScore : nil
        }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func score(on date: Date) -> ScoreSummary {
        let boundary = DayBoundary(date: date)
        let dayPlans = plans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
        let dayChapters = chapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clock.now) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }

        return ScoreCalculator.summary(date: date, plans: dayPlans, chapters: dayChapters, now: clock.now)
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
            accentColorHex: payload.accentColorHex,
            now: now
        )
        modelContext.insert(friend)
        save()
        return .success
    }

    private func accept(_ friend: Friend) {
        friend.status = .accepted
        friend.acceptedAt = Date()
        friend.updatedAt = Date()
        friend.lastSeenAt = Date()
        save()
    }

    private func delete(_ friend: Friend) {
        modelContext.delete(friend)
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save Friend changes: \(String(describing: error))")
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.tertiarySystemGroupedBackground)))
        }
    }
}

private struct RankingCard: View {
    let entry: FriendRankingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                rankBadge
                Spacer()
                scoreBlock(font: .title3.weight(.black))
            }

            HStack(spacing: 9) {
                rankingAvatar

                Text(entry.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
        }
        .frame(width: 136, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(entry.isMe ? Color(.tertiarySystemGroupedBackground) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(entry.isMe ? 0.16 : 0.06), lineWidth: 1)
        )
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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(rankColor.opacity(0.14)))
                .overlay {
                    Capsule()
                        .stroke(rankColor.opacity(0.5), lineWidth: 1)
                }
            } else {
                Text("#\(entry.rank)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            }
        }
    }

    private func scoreBlock(font: Font) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int(round(entry.score)))")
                .font(font)
                .monospacedDigit()
            Text("score")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .opacity(0.68)
        }
    }

    private var rankingAvatar: some View {
        DecoratedFriendAvatar(
            systemImage: entry.imageName,
            tint: entry.tint,
            frameStyle: entry.iconFrame,
            size: 34
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
                            .foregroundStyle(.yellow)
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
                        .foregroundStyle(.secondary.opacity(0.74))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            FriendSquareMetric(
                title: friend.currentStatusTitle.isEmpty ? "オフ" : friend.currentStatusTitle,
                systemImage: friend.currentStatusIcon,
                tint: Color(hex: friend.currentStatusColorHex)
            )

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(Color(.secondarySystemGroupedBackground))
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
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17)
                .fill(Color(.secondarySystemGroupedBackground))
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardStyle.backgroundColor)
            .overlay(alignment: .bottom) {
                FriendCardRhythmStrip(accentColor: cardStyle.stripColor(accentColor: accentColor))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct FriendCardRhythmStrip: View {
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            accentColor.opacity(0.35)
                .frame(width: 46)
            Color.clear
                .frame(width: 18)
            accentColor.opacity(0.18)
                .frame(width: 72)
            Color.clear
                .frame(width: 28)
            accentColor.opacity(0.28)
                .frame(width: 40)
            Color.clear
            accentColor.opacity(0.22)
                .frame(width: 84)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.85)
    }
}

private struct FriendDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let friend: Friend

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                statusCard
                scoreCards
                controls
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
                        friend.status = .blocked
                        friend.blockedAt = Date()
                        friend.updatedAt = Date()
                        save()
                    } label: {
                        Label("ブロック", systemImage: "hand.raised")
                    }

                    Button(role: .destructive) {
                        modelContext.delete(friend)
                        save()
                        dismiss()
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            FriendAvatar(friend: friend, size: 76)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(friend.displayName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    if friend.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(friendMoodText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(18)
        .background(
            FriendCardBackground(cardStyle: friend.cardStyle, accentColor: Color(hex: friend.accentColorHex), cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(friend.cardStyle.borderColor(accentColor: Color(hex: friend.accentColorHex)), lineWidth: 1)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color(hex: friend.currentStatusColorHex).opacity(0.18))
                Image(systemName: friend.currentStatusIcon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(hex: friend.currentStatusColorHex))
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(friend.currentStatusTitle.isEmpty ? "オフライン" : friend.currentStatusTitle)
                    .font(.headline.weight(.bold))
                Text(friend.lastSeenAt?.japaneseShortDateTime ?? "まだ記録なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var scoreCards: some View {
        HStack(spacing: 10) {
            FriendScoreCard(title: "今日", value: friend.todayScore, tint: Color(hex: friend.accentColorHex))
            FriendScoreCard(title: "昨日", value: friend.yesterdayScore, tint: .blue)
            FriendScoreCard(title: "今週", value: friend.weekScore, tint: .green)
        }
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

            Button {
                friend.isFavorite.toggle()
                friend.updatedAt = Date()
                save()
            } label: {
                Label(friend.isFavorite ? "お気に入り済み" : "お気に入り", systemImage: friend.isFavorite ? "star.fill" : "star")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: friend.accentColorHex))
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save Friend detail changes: \(String(describing: error))")
        }
    }

    private var friendMoodText: String {
        let mood = friend.currentMoodText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mood.isEmpty ? (friend.handle.isEmpty ? friend.status.label : friend.handle) : mood
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
                .foregroundStyle(.secondary)
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
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
            .background(Color(.systemGroupedBackground))
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
                        .fill(Color(.tertiarySystemGroupedBackground))
                )

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
            .disabled(FriendInvitePayload(text: receivedText) == nil)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func submit() {
        guard let payload = FriendInvitePayload(text: receivedText) else {
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
}

private enum FriendInviteSubmitResult {
    case success
    case failure(String)
}

private struct FriendRankingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var period: FriendScorePeriod
    let entries: [FriendRankingEntry]
    let onSelectFriend: (Friend) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("期間", selection: $period) {
                    ForEach(FriendScorePeriod.detailCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.top, 12)

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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ランキング")
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .opacity(entry.friend == nil ? 0 : 1)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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

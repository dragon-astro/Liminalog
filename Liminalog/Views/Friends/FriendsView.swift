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
    @State private var rankingDetailPeriod: FriendScorePeriod = .day
    @State private var rankingAnchorDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
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
                    anchorDate: $rankingAnchorDate,
                    entries: rankingEntries(for: rankingDetailPeriod, anchorDate: rankingAnchorDate),
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

    private func rankingEntries(for period: FriendScorePeriod, anchorDate: Date? = nil) -> [FriendRankingEntry] {
        let selfEntry = FriendRankingEntry(
            id: "me",
            rank: 0,
            name: ownDisplayName,
            imageName: activeChapter?.category?.icon ?? "person.fill",
            tint: Color(hex: ownAccentColorHex),
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

    private func selfScore(for period: FriendScorePeriod, anchorDate: Date?) -> Double {
        switch period {
        case .day:
            return score(on: anchorDate ?? clock.now).totalScore
        case .today:
            return score(on: clock.now).totalScore
        case .yesterday:
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: clock.now) else {
                return 0
            }
            return score(on: yesterday).totalScore
        case .week:
            return averageSelfScore(in: dateInterval(.weekOfYear, containing: anchorDate ?? clock.now))
        case .month:
            return averageSelfScore(in: dateInterval(.month, containing: anchorDate ?? clock.now))
        case .year:
            return averageSelfScore(in: dateInterval(.year, containing: anchorDate ?? clock.now))
        }
    }

    private func averageSelfScore(in interval: DateInterval) -> Double {
        var date = interval.start
        var scores: [Double] = []
        let calendar = Calendar.japanese

        while date < interval.end {
            let summary = score(on: date)
            if summary.plannedDuration > 0 {
                scores.append(summary.totalScore)
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = nextDate
        }

        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func dateInterval(_ component: Calendar.Component, containing date: Date) -> DateInterval {
        let boundary = DayBoundary(date: date, calendar: .japanese)
        return Calendar.japanese.dateInterval(of: component, for: date) ?? DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
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
    @State private var isShowingCalendar = false

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
                FriendProfileCollectionSection(friend: friend, badge: badge)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color(.systemGroupedBackground))
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
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.trailing, 76)

                FriendBadgePill(badge: badge)

                Text(moodText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 42, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background {
            FriendCardBackground(cardStyle: friend.cardStyle, accentColor: accentColor, cornerRadius: 8)
                .overlay(alignment: .topTrailing) {
                    ProfileCardStyleMark(style: friend.cardStyle, accentColor: accentColor)
                        .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        FriendProfileActionButton(systemImage: "calendar", label: "カレンダー", action: onCalendar)
                        FriendProfileActionButton(systemImage: friend.isFavorite ? "star.fill" : "star", label: "お気に入り", action: onFavorite)
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(friend.cardStyle.borderColor(accentColor: accentColor), lineWidth: friend.cardStyle.borderWidth)
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
                .background(.thinMaterial, in: Circle())
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
            ProfileStatTile(title: "昨日", value: "\(Int(round(friend.yesterdayScore)))pt", systemImage: "star.fill", tint: Color(hex: "#F2994A"))
            ProfileStatTile(title: "今週", value: "\(Int(round(friend.weekScore)))pt", systemImage: "chart.line.uptrend.xyaxis", tint: Color(hex: "#27AE60"))
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
        case "first_record":
            FriendBadgeDisplay(id: "first_record", title: "はじめの記録", systemImage: "sparkles", tintHex: "#2F80ED")
        case "three_days":
            FriendBadgeDisplay(id: "three_days", title: "3日記録", systemImage: "calendar.badge.checkmark", tintHex: "#27AE60")
        case "seven_streak":
            FriendBadgeDisplay(id: "seven_streak", title: "7日連続", systemImage: "flame.fill", tintHex: "#EB5757")
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

private struct FriendCalendarView: View {
    let friend: Friend
    @State private var visibleMonth = Date()

    private let calendar = Calendar.japanese
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader
                weekdayHeader
                calendarGrid
                sharedCalendarNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(friend.displayName)のカレンダー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.black))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(monthTitle)
                    .font(.title2.weight(.bold))
                Text("共有カレンダー")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.black))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    FriendCalendarDayCell(
                        date: date,
                        score: knownScore(on: date),
                        isToday: calendar.isDateInToday(date),
                        accentColor: Color(hex: friend.accentColorHex)
                    )
                } else {
                    Color.clear
                        .frame(height: 72)
                }
            }
        }
    }

    private var sharedCalendarNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(hex: friend.accentColorHex))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: friend.accentColorHex).opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("共有予定は同期後に表示")
                        .font(.subheadline.weight(.bold))
                    Text("今は友達から届いている日別スコアだけを表示します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var monthTitle: String {
        "\(calendar.component(.year, from: visibleMonth))年\(calendar.component(.month, from: visibleMonth))月"
    }

    private var monthCells: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        let rawCells: [Date?] = Array(repeating: nil, count: leadingBlankCount) + dates.map(Optional.some)
        let trailingBlankCount = (7 - rawCells.count % 7) % 7
        return rawCells + Array(repeating: nil, count: trailingBlankCount)
    }

    private func knownScore(on date: Date) -> Double? {
        if calendar.isDateInToday(date) {
            return friend.todayScore
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(date, inSameDayAs: yesterday) {
            return friend.yesterdayScore
        }
        return nil
    }

    private func moveMonth(by offset: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }
}

private struct FriendCalendarDayCell: View {
    let date: Date
    let score: Double?
    let isToday: Bool
    let accentColor: Color

    private var calendar: Calendar {
        .japanese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? accentColor : .primary)

            Spacer(minLength: 0)

            if let score {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Int(round(score)))")
                        .font(.caption2.weight(.black))
                        .monospacedDigit()
                    Capsule()
                        .fill(accentColor.opacity(0.18))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: proxy.size.width * min(max(score / 100, 0), 1))
                            }
                        }
                }
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 4, height: 4)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isToday ? accentColor : Color.primary.opacity(0.05), lineWidth: isToday ? 2 : 1)
        }
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
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
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
            .background(Color(.systemGroupedBackground))
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
    @Environment(\.dismiss) private var dismiss
    let period: FriendScorePeriod
    @Binding var anchorDate: Date
    @State private var selectedDate: Date
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private let calendar = Calendar.japanese

    init(period: FriendScorePeriod, anchorDate: Binding<Date>) {
        let date = anchorDate.wrappedValue
        let calendar = Calendar.japanese
        self.period = period
        self._anchorDate = anchorDate
        self._selectedDate = State(initialValue: date)
        self._selectedYear = State(initialValue: calendar.component(.year, from: date))
        self._selectedMonth = State(initialValue: calendar.component(.month, from: date))
    }

    var body: some View {
        NavigationStack {
            pickerContent
                .padding(.horizontal, 12)
                .navigationTitle(pickerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            applySelection()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.height(300)])
    }

    @ViewBuilder
    private var pickerContent: some View {
        switch period {
        case .day, .week:
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        case .month:
            HStack(spacing: 0) {
                yearPicker
                monthPicker
            }
        case .year:
            yearPicker
        case .today, .yesterday:
            EmptyView()
        }
    }

    private var yearPicker: some View {
        Picker("年", selection: $selectedYear) {
            ForEach(Array(yearRange), id: \.self) { year in
                Text(verbatim: "\(year)年").tag(year)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private var monthPicker: some View {
        Picker("月", selection: $selectedMonth) {
            ForEach(1...12, id: \.self) { month in
                Text("\(month)月").tag(month)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 5)...(currentYear + 1)
    }

    private var pickerTitle: String {
        switch period {
        case .day:
            "日付を選択"
        case .week:
            "週を選択"
        case .month:
            "年月を選択"
        case .year:
            "年を選択"
        case .today, .yesterday:
            "期間を選択"
        }
    }

    private func applySelection() {
        switch period {
        case .day, .week:
            anchorDate = selectedDate
        case .month:
            anchorDate = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? anchorDate
        case .year:
            anchorDate = calendar.date(from: DateComponents(year: selectedYear, month: 1, day: 1)) ?? anchorDate
        case .today, .yesterday:
            break
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

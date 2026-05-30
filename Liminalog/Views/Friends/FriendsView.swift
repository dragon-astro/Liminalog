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
                            .fill(Color.accentColor)
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
            let statusColor = Color(hex: friend.currentStatusColorHex)
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
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: friend.currentStatusColorHex).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: friend.currentStatusColorHex).opacity(0.22), lineWidth: 1)
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

                FriendBadgePill(badge: badge)

                Text(moodText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 42, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 8) {
                FriendProfileActionButton(systemImage: "calendar", label: "カレンダー", action: onCalendar)
                FriendProfileActionButton(systemImage: friend.isFavorite ? "star.fill" : "star", label: "お気に入り", action: onFavorite)
            }
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
    @State private var showingMonthPicker = false
    @State private var showingSearch = false
    @State private var pickerYear = Calendar.japanese.component(.year, from: Date())
    @State private var pickerMonth = Calendar.japanese.component(.month, from: Date())
    @State private var selectedDay: FriendSharedCalendarTargetDay?
    @State private var selectedMonthOffset = 0

    private let calendar = Calendar.japanese
    private let weekdays = Calendar.japaneseShortWeekdaySymbols

    var body: some View {
        VStack(spacing: 0) {
            calendarTopBar

            CalendarWeekdayHeader(
                weekdays: weekdays,
                weekdayColor: weekdayColor(_:)
            )

            TabView(selection: $selectedMonthOffset) {
                ForEach([-1, 0, 1], id: \.self) { offset in
                    let month = pageMonth(offset)
                    VStack(spacing: 0) {
                        FriendSharedCalendarMonthGrid(
                            dates: monthGridDates(for: month),
                            visibleMonth: month,
                            importantPlans: importantPlans(on:),
                            allPlans: sharedPlans(on:),
                            allActivities: sharedActivities(on:),
                            score: knownScore(on:),
                            accentColor: Color(hex: friend.accentColorHex),
                            onOpenDay: { date in
                                selectedDay = FriendSharedCalendarTargetDay(date: date)
                            }
                        )
                        .padding(.vertical, 8)

                        Spacer(minLength: 0)
                    }
                    .id(month.timeIntervalSince1970)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: selectedMonthOffset) { _, newValue in
                guard newValue != 0 else { return }
                settleMonthShift(newValue)
            }
        }
        .background(Color(.systemGroupedBackground))
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
                visibleMonth = monthStart(for: plan.startTime)
                selectedMonthOffset = 0
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
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.34), lineWidth: 1)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
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

    private func importantPlans(on date: Date) -> [FriendSharedPlanSnapshot] {
        sharedPlans(on: date)
            .filter(\.showsInCalendarAsImportant)
    }

    private func sharedPlans(on date: Date) -> [FriendSharedPlanSnapshot] {
        friend.sharedPlans
            .filter { $0.overlaps(day: date) }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func sharedActivities(on date: Date) -> [FriendSharedActivitySnapshot] {
        friend.sharedActivities
            .filter { $0.overlaps(day: date) }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func prepareMonthPicker() {
        pickerYear = calendar.component(.year, from: visibleMonth)
        pickerMonth = calendar.component(.month, from: visibleMonth)
    }

    private func applyPickedMonth() {
        let components = DateComponents(year: pickerYear, month: pickerMonth, day: 1)
        visibleMonth = monthStart(for: calendar.date(from: components) ?? visibleMonth)
        selectedMonthOffset = 0
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

    private func pageMonth(_ offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthStart(for: visibleMonth)) ?? monthStart(for: visibleMonth)
    }

    private func settleMonthShift(_ offset: Int) {
        let nextMonth = pageMonth(offset)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            visibleMonth = nextMonth
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedMonthOffset = 0
            }
        }
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

private struct FriendSharedCalendarMonthGrid: View {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlans: (Date) -> [FriendSharedPlanSnapshot]
    let allPlans: (Date) -> [FriendSharedPlanSnapshot]
    let allActivities: (Date) -> [FriendSharedActivitySnapshot]
    let score: (Date) -> FriendCalendarScore?
    let accentColor: Color
    let onOpenDay: (Date) -> Void

    private let spacing: CGFloat = 1

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(weekDates.enumerated()), id: \.offset) { _, week in
                FriendSharedCalendarWeekRow(
                    dates: week,
                    visibleMonth: visibleMonth,
                    importantPlans: importantPlans,
                    allPlans: allPlans,
                    allActivities: allActivities,
                    score: score,
                    accentColor: accentColor,
                    onOpenDay: onOpenDay,
                    spacing: spacing,
                    cellHeight: cellHeight
                )
            }
        }
        .background(Color(.separator).opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
    }

    private var weekDates: [[Date]] {
        stride(from: 0, to: dates.count, by: 7).map { start in
            Array(dates[start..<min(start + 7, dates.count)])
        }
    }

    private var cellHeight: CGFloat {
        CalendarMonthDayCell.cellHeight(forWeekCount: weekDates.count)
    }
}

private struct FriendSharedCalendarWeekRow: View {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlans: (Date) -> [FriendSharedPlanSnapshot]
    let allPlans: (Date) -> [FriendSharedPlanSnapshot]
    let allActivities: (Date) -> [FriendSharedActivitySnapshot]
    let score: (Date) -> FriendCalendarScore?
    let accentColor: Color
    let onOpenDay: (Date) -> Void
    let spacing: CGFloat
    let cellHeight: CGFloat

    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0

    private let calendar = Calendar.japanese

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: spacing) {
                ForEach(dates, id: \.self) { date in
                    Button {
                        onOpenDay(date)
                    } label: {
                        FriendSharedCalendarDayCell(
                            date: date,
                            visibleMonth: visibleMonth,
                            plans: importantPlans(date),
                            reservedPlanRows: visibleMultiDayPlans.count,
                            score: score(date),
                            accentColor: accentColor,
                            cellHeight: cellHeight
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            GeometryReader { proxy in
                ForEach(Array(visibleMultiDayPlans.enumerated()), id: \.element.id) { lane, plan in
                    if let frame = segmentFrame(for: plan, in: proxy.size, lane: lane) {
                        Button {
                            onOpenDay(plan.startTime)
                        } label: {
                            FriendSharedMultiDayPlanBar(
                                plan: plan,
                                roundsLeading: roundsLeadingEdge(for: plan),
                                roundsTrailing: roundsTrailingEdge(for: plan)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: labelHeight)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: cellHeight)
        }
        .frame(height: cellHeight)
    }

    private var visibleMultiDayPlans: [FriendSharedPlanSnapshot] {
        let plans = multiDayPlans
        guard plans.count > maxVisiblePlanRows else { return plans }
        return Array(plans.prefix(maxVisiblePlanRows))
    }

    private var multiDayPlans: [FriendSharedPlanSnapshot] {
        var seenIDs = Set<UUID>()
        return dates
            .flatMap { importantPlans($0) }
            .filter(\.spansMultipleCalendarDays)
            .filter { plan in
                guard !seenIDs.contains(plan.id) else { return false }
                seenIDs.insert(plan.id)
                return true
            }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func segmentFrame(for plan: FriendSharedPlanSnapshot, in size: CGSize, lane: Int) -> CGRect? {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)),
              let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else { return nil }

        let startIndex = max(0, calendar.dateComponents([.day], from: weekStart, to: max(calendar.startOfDay(for: plan.startTime), weekStart)).day ?? 0)
        let endIndex = min(7, exclusiveDayIndex(for: min(plan.endTime, weekEnd), from: weekStart))
        guard endIndex > startIndex else { return nil }

        let columnWidth = (size.width - spacing * 6) / 7
        let x = CGFloat(startIndex) * (columnWidth + spacing) + 3
        let width = CGFloat(endIndex - startIndex) * columnWidth + CGFloat(endIndex - startIndex - 1) * spacing - 6
        let y = planListTop + CGFloat(lane) * rowStride
        return CGRect(x: x, y: y, width: max(width, 2), height: labelHeight)
    }

    private func exclusiveDayIndex(for end: Date, from weekStart: Date) -> Int {
        let endDay = calendar.startOfDay(for: end)
        let exclusiveEndDay: Date
        if abs(end.timeIntervalSince(endDay)) < 0.001 {
            exclusiveEndDay = endDay
        } else {
            exclusiveEndDay = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        }
        return calendar.dateComponents([.day], from: weekStart, to: exclusiveEndDay).day ?? 0
    }

    private func roundsLeadingEdge(for plan: FriendSharedPlanSnapshot) -> Bool {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)) else { return true }
        return plan.startTime >= weekStart
    }

    private func roundsTrailingEdge(for plan: FriendSharedPlanSnapshot) -> Bool {
        guard let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else { return true }
        return plan.endTime <= weekEnd
    }

    private var maxVisiblePlanRows: Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride), 0)
    }

    private var planListTop: CGFloat { 4 + 22 + 4 }
    private var labelHeight: CGFloat { max(11, CGFloat(planTitleFontSize) + 5) }
    private var planRowSpacing: CGFloat { 2 }
    private var rowStride: CGFloat { labelHeight + planRowSpacing }
}

private struct FriendSharedCalendarDayCell: View {
    let date: Date
    let visibleMonth: Date
    let plans: [FriendSharedPlanSnapshot]
    let reservedPlanRows: Int
    let score: FriendCalendarScore?
    let accentColor: Color
    let cellHeight: CGFloat

    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0

    private var isToday: Bool {
        Calendar.japanese.isDateInToday(date)
    }

    private var isInVisibleMonth: Bool {
        Calendar.japanese.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Calendar.japanese.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? .white : dateNumberColor)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }

                Spacer(minLength: 0)

                FriendCalendarScoreBadge(score: score)
            }

            VStack(alignment: .leading, spacing: 2) {
                if reservedPlanRows > 0 {
                    Color.clear
                        .frame(height: CGFloat(reservedPlanRows) * rowStride)
                }

                ForEach(visibleSingleDayPlans) { plan in
                    FriendSharedPlanLabel(plan: plan, date: date)
                }

                let overflow = max(singleDayPlans.count - visibleSingleDayPlans.count, 0)
                if overflow > 0 {
                    Text("+\(overflow)件")
                        .font(.system(size: 6, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(isInVisibleMonth ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground).opacity(0.5))
        )
        .overlay(
            Rectangle()
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: isToday ? 2.5 : 0)
        )
        .opacity(isInVisibleMonth ? 1 : 0.48)
    }

    private var dateNumberColor: Color {
        let weekday = Calendar.japanese.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .primary
    }

    private var singleDayPlans: [FriendSharedPlanSnapshot] {
        plans.filter { !$0.spansMultipleCalendarDays }
    }

    private var visibleSingleDayPlans: [FriendSharedPlanSnapshot] {
        let capacity = maxVisiblePlanRows
        guard capacity > 0 else { return [] }
        guard singleDayPlans.count > capacity else { return singleDayPlans }
        return Array(singleDayPlans.prefix(max(capacity - 1, 0)))
    }

    private var maxVisiblePlanRows: Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride) - reservedPlanRows, 0)
    }

    private var labelHeight: CGFloat { max(11, CGFloat(planTitleFontSize) + 5) }
    private var planRowSpacing: CGFloat { 2 }
    private var rowStride: CGFloat { labelHeight + planRowSpacing }
}

private struct FriendCalendarScoreBadge: View {
    let score: FriendCalendarScore?

    var body: some View {
        Text(scoreText)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(scoreColor)
            .monospacedDigit()
            .frame(minWidth: 21, minHeight: 17)
            .padding(.horizontal, 3)
            .background(Capsule().fill(scoreColor.opacity(score == nil ? 0.08 : 0.12)))
            .overlay(Capsule().stroke(scoreColor.opacity(score == nil ? 0.14 : 0.24), lineWidth: 1))
    }

    private var scoreText: String {
        guard let score, score.hasSharedData else { return "-" }
        return "\(Int(score.value.rounded()))"
    }

    private var scoreColor: Color {
        guard let score, score.hasSharedData else { return .secondary }
        switch score.value {
        case 85...:
            return .green
        case 65..<85:
            return .teal
        case 40..<65:
            return .orange
        case 1..<40:
            return .red
        default:
            return .secondary
        }
    }
}

private struct FriendSharedPlanLabel: View {
    let plan: FriendSharedPlanSnapshot
    let date: Date

    @AppStorage("calendarTimedPlanLabelStyle") private var timedPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarAllDayPlanLabelStyle") private var allDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var titleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var titleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        HStack(spacing: 3) {
            if let timePrefix {
                Text(timePrefix)
                    .font(.system(size: timeFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: timeColor)
            }

            Color.clear
                .overlay(alignment: .leading) {
                    Text(plan.title)
                        .font(.system(size: titleFontSize, weight: titleBold ? .bold : .regular))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .strikethrough(shouldStrikePastPlan, color: titleColor)
                }
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: labelHeight)
        .padding(.horizontal, 3)
        .background(backgroundShape)
        .overlay(borderShape)
        .padding(.leading, continuesFromPreviousDay ? -3 : 0)
        .padding(.trailing, continuesToNextDay ? -3 : 0)
        .opacity(isPastPlan && dimPastPlans ? 0.38 : 1)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            FriendCalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .fill(color.opacity(0.14))
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if labelStyle == .background {
            FriendCalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .stroke(color.opacity(0.24), lineWidth: 0.7)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(color.opacity(0.28))
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
        }
    }

    private var color: Color { Color(hex: plan.categoryColorHex) }
    private var labelStyle: CalendarPlanLabelStyle {
        let rawValue = plan.isAllDay ? allDayPlanLabelStyleRaw : timedPlanLabelStyleRaw
        return CalendarPlanLabelStyle(rawValue: rawValue) ?? .background
    }
    private var titleColor: Color { labelStyle == .background ? .primary : color }
    private var timeColor: Color { labelStyle == .background ? .secondary : color.opacity(0.75) }
    private var timeFontSize: Double { max(4, titleFontSize - 1) }
    private var labelHeight: CGFloat { max(11, CGFloat(titleFontSize) + 5) }
    private var markerHeight: CGFloat { max(4, CGFloat(titleFontSize) * 0.5) }
    private var markerBottomPadding: CGFloat { max(1, CGFloat(titleFontSize) * 0.08) }
    private var isPastPlan: Bool { min(plan.endTime, dayEnd) <= Date() }
    private var shouldStrikePastPlan: Bool { isPastPlan && strikePastPlans }
    private var dayStart: Date { Calendar.japanese.startOfDay(for: date) }
    private var dayEnd: Date { Calendar.japanese.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart }
    private var continuesFromPreviousDay: Bool { plan.startTime < dayStart }
    private var continuesToNextDay: Bool { plan.endTime > dayEnd }
    private var timePrefix: String? {
        if plan.isAllDay || continuesFromPreviousDay { return nil }
        return plan.startTime.shortTime
    }
}

private struct FriendSharedMultiDayPlanBar: View {
    let plan: FriendSharedPlanSnapshot
    let roundsLeading: Bool
    let roundsTrailing: Bool

    @AppStorage("calendarMultiDayPlanLabelStyle") private var multiDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var titleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var titleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        Color.clear
            .overlay {
                Text(plan.title)
                    .font(.system(size: titleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(isPastPlan && strikePastPlans, color: titleColor)
            }
            .background(backgroundShape)
            .overlay(decorationOverlay)
            .clipped()
            .opacity(isPastPlan && dimPastPlans ? 0.38 : 1)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            FriendCalendarContinuationShape(roundsLeading: roundsLeading, roundsTrailing: roundsTrailing)
                .fill(color.opacity(0.14))
        }
    }

    @ViewBuilder
    private var decorationOverlay: some View {
        if labelStyle == .background {
            FriendCalendarContinuationShape(roundsLeading: roundsLeading, roundsTrailing: roundsTrailing)
                .stroke(color.opacity(0.24), lineWidth: 0.7)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(color.opacity(0.28))
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
        }
    }

    private var labelStyle: CalendarPlanLabelStyle {
        CalendarPlanLabelStyle(rawValue: multiDayPlanLabelStyleRaw) ?? .background
    }
    private var color: Color { Color(hex: plan.categoryColorHex) }
    private var titleColor: Color { labelStyle == .background ? .primary : color }
    private var markerHeight: CGFloat { max(4, CGFloat(titleFontSize) * 0.5) }
    private var markerBottomPadding: CGFloat { max(1, CGFloat(titleFontSize) * 0.08) }
    private var isPastPlan: Bool { plan.endTime <= Date() }
}

private struct FriendCalendarContinuationShape: Shape {
    let roundsLeading: Bool
    let roundsTrailing: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, 4)
        let leadingRadius = roundsLeading ? radius : 0
        let trailingRadius = roundsTrailing ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.minY))
        if trailingRadius > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + trailingRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailingRadius))
        if trailingRadius > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + leadingRadius, y: rect.maxY))
        if leadingRadius > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - leadingRadius), control: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leadingRadius))
        if leadingRadius > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
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
        .background(Color(.systemGroupedBackground))
        .modifier(FriendDayNavigationTitleModifier(isEnabled: showsNavigationTitle, title: date.japaneseMonthDayShortWeekday))
        .modifier(FriendDayNavigationGestureModifier(isEnabled: allowsDayNavigation, shiftDay: shiftDay(_:)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.japaneseMonthDayShortWeekday)
                .font(.title3.bold())
            Text("共有された予定と実績")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var scoreCard: some View {
        HStack {
            Label("スコア", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.yellow)
                    Text("重要な予定")
                        .font(.headline)
                }

                ForEach(importantPlans) { plan in
                    FriendSharedPlanRow(plan: plan)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
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
                .foregroundStyle(Color(hex: plan.categoryColorHex))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(hex: plan.categoryColorHex).opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeText: String {
        if plan.isAllDay {
            return "時間未指定"
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
                        if trimmedQuery.isEmpty {
                            ContentUnavailableView(
                                "予定名を入力",
                                systemImage: "magnifyingglass",
                                description: Text("検索欄に入力すると共有予定を表示します")
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

                Text(trimmedQuery.isEmpty ? "検索ワードを入力してください" : "検索結果: \(filteredPlans.count)件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.bar)
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        .overlay(Capsule().stroke(Color(.separator).opacity(0.45), lineWidth: 1))
    }
}

private struct FriendSharedPlanSearchRow: View {
    let plan: FriendSharedPlanSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.startTime.japaneseYear)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(plan.startTime.japaneseMonthDayShortWeekday)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: plan.categoryColorHex))
                        .frame(width: 6, height: 6)
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var timeText: String {
        if plan.isAllDay { return "時間未指定" }
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

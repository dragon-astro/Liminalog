import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \Friend.createdAt) private var friends: [Friend]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]

    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var isShowingShareProfile = false
    @State private var performanceSnapshot = ProfilePerformanceSnapshot.empty

    private var settings: UserSettings? {
        settingsList.first
    }

    private var displayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : name
    }

    private var bio: String {
        settings?.profileBio.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var accentColor: Color {
        iconFrame.primaryColor
    }

    private var decorationUnlocks: ProfileDecorationUnlocks {
        ProfileDecorationUnlocks(unlockItems: unlockItems)
    }

    private var invitePayload: FriendInvitePayload {
        FriendInvitePayload(
            code: FriendInvitePayload.code(from: settings?.id ?? UUID()),
            displayName: displayName
        )
    }

    private var badges: [ProfileBadgeModel] {
        ProfileBadgeCatalog.items(
            metrics: performanceSnapshot.unlockMetrics,
            unlockItems: unlockItems
        )
    }

    private var equippedBadge: ProfileBadgeModel {
        ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges)
    }

    private var nextUnlockTargets: [ProfileUnlockTarget] {
        ProfileUnlockTargetCatalog.targets(
            metrics: performanceSnapshot.unlockMetrics,
            unlockItems: unlockItems
        )
    }

    private var iconFrame: ProfileIconFrameStyle {
        ProfileIconFrameCatalog.item(for: decorationUnlocks.equippedIconFrameID(settings?.profileIconFrameID))
    }

    private var streakIcon: ProfileStreakIconStyle {
        ProfileStreakIconCatalog.item(for: decorationUnlocks.equippedStreakIconID(settings?.profileStreakIconID))
    }

    private var cardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: decorationUnlocks.equippedCardStyleID(settings?.profileCardStyleID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ProfileHero(
                        displayName: displayName,
                        bio: bio,
                        imageData: settings?.profileImageData,
                        accentColor: accentColor,
                        equippedBadge: equippedBadge,
                        iconFrame: iconFrame,
                        cardStyle: cardStyle,
                        onEdit: { isShowingEditProfile = true },
                        onShare: { isShowingShareProfile = true }
                    )

                    ProfileStatsRow(
                        streak: performanceSnapshot.streakCount,
                        totalScore: performanceSnapshot.totalEarnedScore,
                        friendCount: acceptedFriendCount,
                        streakIcon: streakIcon
                    )

                    if !nextUnlockTargets.isEmpty || !unlockItems.isEmpty {
                        ProfileNextUnlockSection(targets: nextUnlockTargets)
                    }

                    ProfileCollectionSection(
                        badges: badges,
                        equippedBadge: equippedBadge,
                        iconFrame: iconFrame,
                        streakIcon: streakIcon,
                        cardStyle: cardStyle
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .background(LiminalTheme.canvasGradient)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("設定")
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingEditProfile) {
                ProfileEditSheet(
                    settings: settings,
                    badges: badges,
                    unlocks: decorationUnlocks,
                    onSave: saveProfile
                )
            }
            .sheet(isPresented: $isShowingShareProfile) {
                ProfileShareSheet(payload: invitePayload)
            }
            .task {
                ensureUserSettings()
                refreshPerformanceSnapshot()
            }
            .onChange(of: isShowingSettings) { _, isShowing in
                if !isShowing {
                    refreshPerformanceSnapshot()
                }
            }
        }
    }

    private var acceptedFriendCount: Int {
        friends.filter { $0.status == .accepted }.count
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        let settings = UserSettings()
        modelContext.insert(settings)
        try? modelContext.save()
    }

    private func refreshPerformanceSnapshot() {
        let snapshot = ProfilePerformanceSnapshot.load(modelContext: modelContext, now: Date())
        performanceSnapshot = snapshot
        UnlockStore(modelContext: modelContext).refresh(metrics: snapshot.unlockMetrics)
    }

    private func saveProfile(_ draft: ProfileDraft) {
        let target: UserSettings
        if let settings {
            target = settings
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            target = created
        }

        target.profileDisplayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profileBio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profileImageData = draft.imageData
        target.profileBadgeID = ProfileBadgeCatalog.equippedBadge(id: draft.badgeID, badges: badges).id
        target.profileIconFrameID = decorationUnlocks.equippedIconFrameID(draft.iconFrameID)
        target.profileStreakIconID = decorationUnlocks.equippedStreakIconID(draft.streakIconID)
        target.profileCardStyleID = decorationUnlocks.equippedCardStyleID(draft.cardStyleID)
        target.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct ProfilePerformanceSnapshot {
    let totalEarnedScore: Int
    let streakCount: Int
    let recordedDayCount: Int
    let totalRecordedDuration: TimeInterval
    let earlyRecordDayCount: Int
    let lateNightRecordDayCount: Int
    let distinctCategoryCount: Int
    let unlockMetrics: UnlockMetrics

    static let empty = ProfilePerformanceSnapshot(
        totalEarnedScore: 0,
        streakCount: 0,
        recordedDayCount: 0,
        totalRecordedDuration: 0,
        earlyRecordDayCount: 0,
        lateNightRecordDayCount: 0,
        distinctCategoryCount: 0,
        unlockMetrics: UnlockMetrics()
    )

    @MainActor
    static func load(modelContext: ModelContext, now: Date, calendar: Calendar = .japanese) -> ProfilePerformanceSnapshot {
        let todayStart = DayBoundary.dayStart(for: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let interval = DateInterval(start: start, end: end)

        let plans = ScoreSnapshotLoader.plannedBlocks(in: interval, modelContext: modelContext)
        let chapters = ScoreSnapshotLoader.chapters(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        let allChaptersDescriptor = FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)])
        let allChapters = (try? modelContext.fetch(allChaptersDescriptor)) ?? []
        let summaries = ScoreSnapshotLoader.days(in: interval, calendar: calendar).map { date in
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            return ScoreCalculator.summary(date: date, plans: dayPlans, chapters: dayChapters, calendar: calendar, now: now)
        }

        var streak = 0
        for summary in summaries.reversed() {
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            streak += 1
        }

        let totalEarnedScore = summaries.reduce(0) { $0 + Int($1.totalScore.rounded()) }
        let recordedDayStarts = Set(allChapters.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) })
        let completedChapters = allChapters.filter { $0.endTime != nil }
        let earlyRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard (5..<9).contains(hour) else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let lateNightRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard hour >= 23 || hour < 3 else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let totalRecordedDuration = allChapters.reduce(0) { $0 + max(0, ($1.endTime ?? now).timeIntervalSince($1.startTime)) }
        let distinctCategoryCount = Set(allChapters.compactMap { $0.category?.id }).count
        let unlockMetrics = UnlockMetrics(
            cumulativeScore: totalEarnedScore,
            recordedDays: recordedDayStarts.count,
            recordedHours: max(0, Int(totalRecordedDuration / 3600)),
            streakDays: streak,
            earlyRecordDays: earlyRecordDayCount,
            lateNightRecordDays: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount
        )

        return ProfilePerformanceSnapshot(
            totalEarnedScore: totalEarnedScore,
            streakCount: streak,
            recordedDayCount: recordedDayStarts.count,
            totalRecordedDuration: totalRecordedDuration,
            earlyRecordDayCount: earlyRecordDayCount,
            lateNightRecordDayCount: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount,
            unlockMetrics: unlockMetrics
        )
    }
}

private struct ProfileHero: View {
    let displayName: String
    let bio: String
    let imageData: Data?
    let accentColor: Color
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let cardStyle: ProfileCardStyle
    let onEdit: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ProfilePhotoView(
                    displayName: displayName,
                    imageData: imageData,
                    accentColor: accentColor,
                    frameStyle: iconFrame,
                    size: 92
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(cardStyle.textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.trailing, 76)

                    EquippedBadgePill(badge: equippedBadge)

                    Text(bio.isEmpty ? "プロフィールを育てよう" : bio)
                        .font(.subheadline)
                        .foregroundStyle(cardStyle.secondaryTextColor)
                        .lineLimit(2)
                        .frame(minHeight: 42, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardStyle.backgroundColor)
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: cardStyle.stripColor(accentColor: accentColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    ProfileCardStyleMark(style: cardStyle, accentColor: accentColor)
                        .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        ProfileHeroActionButton(systemImage: "pencil", label: "編集", action: onEdit)
                        ProfileHeroActionButton(systemImage: "square.and.arrow.up", label: "シェア", action: onShare)
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStyle.borderColor(accentColor: accentColor), lineWidth: cardStyle.borderWidth)
        }
    }
}

struct ProfileCardStyleMark: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        Image(systemName: style.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(style.markColor(accentColor: accentColor))
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(style.id == ProfileCardStyleCatalog.defaultID ? 0 : 1)
    }
}

private struct ProfileHeroActionButton: View {
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

private struct EquippedBadgePill: View {
    let badge: ProfileBadgeModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.systemImage)
                .font(.caption2.weight(.bold))
            Text(badge.title)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(Color(hex: badge.tint))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(hex: badge.tint).opacity(0.12), in: Capsule())
        .lineLimit(1)
    }
}

private struct ProfilePhotoView: View {
    let displayName: String
    let imageData: Data?
    let accentColor: Color
    let frameStyle: ProfileIconFrameStyle
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.gradient)
                .frame(width: size, height: size)

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }

            ProfileIconFrameView(style: frameStyle, accentColor: accentColor, size: size + 16)
        }
        .frame(width: size + 16, height: size + 16)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.75), lineWidth: 2)
                .frame(width: size, height: size)
        }
        .shadow(color: accentColor.opacity(0.2), radius: 14, y: 6)
    }

    private var initial: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

struct ProfileIconFrameView: View {
    let style: ProfileIconFrameStyle
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style.secondaryColor.opacity(0.24), lineWidth: style.lineWidth + 4)

            switch style.id {
            case "signal":
                Circle()
                    .trim(from: 0.06, to: 0.38)
                    .stroke(style.primaryColor, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-28))
                Circle()
                    .trim(from: 0.56, to: 0.86)
                    .stroke(style.secondaryColor, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-28))
            case "crown":
                Circle()
                    .stroke(style.primaryColor.opacity(0.9), style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, dash: [10, 5]))
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.primaryColor)
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    .offset(x: size * 0.28, y: -size * 0.28)
            case "focus":
                Circle()
                    .stroke(style.primaryColor, lineWidth: style.lineWidth)
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(style.secondaryColor)
                        .frame(width: 4, height: 12)
                        .offset(y: -size * 0.47)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            default:
                Circle()
                    .stroke(style.primaryColor, lineWidth: style.lineWidth)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ProfileStatsRow: View {
    let streak: Int
    let totalScore: Int
    let friendCount: Int
    let streakIcon: ProfileStreakIconStyle

    var body: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "ストリーク", value: "\(streak)日", systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            ProfileStatTile(title: "累計スコア", value: "\(totalScore)pt", systemImage: "star.fill", tint: Color(hex: "#F2994A"))
            ProfileStatTile(title: "友達", value: "\(friendCount)人", systemImage: "person.2.fill", tint: Color(hex: "#27AE60"))
        }
    }
}

struct ProfileStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .topTrailing) {
            tint.opacity(0.18)
                .frame(width: 26, height: 4)
                .clipShape(Capsule())
                .padding(10)
        }
    }
}

private struct ProfileNextUnlockSection: View {
    let targets: [ProfileUnlockTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("次の解放")
                .font(.headline)

            if targets.isEmpty {
                ProfileAllUnlockedCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(targets) { target in
                        ProfileUnlockTargetRow(target: target)
                    }
                }
            }
        }
    }
}

private struct ProfileUnlockTargetRow: View {
    let target: ProfileUnlockTarget

    private var tint: Color {
        Color(hex: target.tintHex)
    }

    private var progressLabel: String {
        "\(target.progressPercent)%"
    }

    private var remainingLabel: String {
        target.remainingText
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: target.systemImageName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(target.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(target.kindTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                }

                ProgressView(value: target.progress)
                    .tint(tint)

                HStack {
                    Text(remainingLabel)
                    Spacer(minLength: 8)
                    Text(progressLabel)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileAllUnlockedCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(hex: "#27AE60"))
                .frame(width: 42, height: 42)
                .background(Color(hex: "#27AE60").opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("全解放済み")
                    .font(.subheadline.weight(.semibold))
                Text("今の装備を磨ける状態")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileCollectionSection: View {
    let badges: [ProfileBadgeModel]
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let streakIcon: ProfileStreakIconStyle
    let cardStyle: ProfileCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("装備とコレクション")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ProfileEquipmentTile(title: "バッジ", value: equippedBadge.title, systemImage: equippedBadge.systemImage, tint: Color(hex: equippedBadge.tint))
                ProfileEquipmentFrameTile(title: "フレーム", value: iconFrame.title, frameStyle: iconFrame)
                ProfileEquipmentCardStyleTile(title: "カード", value: cardStyle.title, cardStyle: cardStyle, accentColor: iconFrame.primaryColor)
                ProfileEquipmentTile(title: "連続", value: streakIcon.title, systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(badges) { badge in
                        ProfileCollectionBadge(badge: badge, isEquipped: badge.id == equippedBadge.id)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ProfileCollectionBadge: View {
    let badge: ProfileBadgeModel
    let isEquipped: Bool

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? tint.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                Circle()
                    .stroke(
                        isEquipped ? tint : (badge.isUnlocked ? tint.opacity(0.65) : Color(.separator).opacity(0.4)),
                        lineWidth: isEquipped ? 2 : 1
                    )
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(badge.isUnlocked ? tint : Color.secondary)
            }
            .frame(width: 62, height: 62)
            .overlay(alignment: .bottomTrailing) {
                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
            }

            Text(badge.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(badge.progressText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 78)
        .opacity(badge.isUnlocked ? 1 : 0.55)
    }
}

struct ProfileEquipmentTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(height: 20)
        }
    }
}

struct ProfileEquipmentFrameTile: View {
    let title: String
    let value: String
    let frameStyle: ProfileIconFrameStyle

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            ZStack {
                Circle()
                    .fill(frameStyle.primaryColor.opacity(0.14))
                    .frame(width: 22, height: 22)

                ProfileIconFrameView(style: frameStyle, accentColor: frameStyle.primaryColor, size: 28)
            }
            .frame(width: 32, height: 24, alignment: .leading)
        }
    }
}

struct ProfileEquipmentCardStyleTile: View {
    let title: String
    let value: String
    let cardStyle: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            ProfileMiniCardStyleView(style: cardStyle, accentColor: accentColor)
                .frame(width: 42, height: 24)
        }
    }
}

struct ProfileEquipmentTileShell<Preview: View>: View {
    let title: String
    let value: String
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview()
                .frame(height: 24, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .frame(minHeight: 78, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileMiniCardStyleView: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(style.backgroundColor)
            .overlay(alignment: .bottom) {
                DecorativeAccentStrip(color: style.stripColor(accentColor: accentColor), height: 7)
            }
            .overlay(alignment: .topTrailing) {
                ProfileCardStyleMark(style: style, accentColor: accentColor)
                    .scaleEffect(0.48)
                    .frame(width: 12, height: 12)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(style.borderColor(accentColor: accentColor), lineWidth: max(1, style.borderWidth))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var imageData: Data?
    @State private var badgeID: String
    @State private var iconFrameID: String
    @State private var streakIconID: String
    @State private var cardStyleID: String
    @State private var selectedPhoto: PhotosPickerItem?

    let badges: [ProfileBadgeModel]
    let unlocks: ProfileDecorationUnlocks
    let onSave: (ProfileDraft) -> Void

    init(
        settings: UserSettings?,
        badges: [ProfileBadgeModel],
        unlocks: ProfileDecorationUnlocks,
        onSave: @escaping (ProfileDraft) -> Void
    ) {
        _displayName = State(initialValue: settings?.profileDisplayName ?? "")
        _bio = State(initialValue: settings?.profileBio ?? "")
        _imageData = State(initialValue: settings?.profileImageData)
        _badgeID = State(initialValue: ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges).id)
        _iconFrameID = State(initialValue: unlocks.equippedIconFrameID(settings?.profileIconFrameID))
        _streakIconID = State(initialValue: unlocks.equippedStreakIconID(settings?.profileStreakIconID))
        _cardStyleID = State(initialValue: unlocks.equippedCardStyleID(settings?.profileCardStyleID))
        self.badges = badges
        self.unlocks = unlocks
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ProfilePhotoView(
                            displayName: displayName.isEmpty ? "L" : displayName,
                            imageData: imageData,
                            accentColor: visualAccentColor,
                            frameStyle: ProfileIconFrameCatalog.item(for: iconFrameID),
                            size: 76
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("写真を選択", systemImage: "photo")
                            }

                            if imageData != nil {
                                Button(role: .destructive) {
                                    imageData = nil
                                } label: {
                                    Label("写真を削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("プロフィール") {
                    TextField("名前", text: $displayName)
                        .textInputAutocapitalization(.never)

                    TextField("自己紹介", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("装備") {
                    ProfileBadgeSelector(
                        badges: badges,
                        selectedID: $badgeID
                    )

                    ProfileFrameSelector(
                        selectedID: $iconFrameID,
                        accentColor: visualAccentColor,
                        unlockedIDs: unlocks.iconFrameIDs
                    )

                    ProfileStreakIconSelector(
                        selectedID: $streakIconID,
                        unlockedIDs: unlocks.streakIconIDs
                    )

                    ProfileCardStyleSelector(
                        selectedID: $cardStyleID,
                        accentColor: visualAccentColor,
                        unlockedIDs: unlocks.cardStyleIDs
                    )
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(
                            ProfileDraft(
                                displayName: displayName,
                                bio: bio,
                                imageData: imageData,
                                badgeID: badgeID,
                                iconFrameID: iconFrameID,
                                streakIconID: streakIconID,
                                cardStyleID: cardStyleID
                            )
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                Task {
                    guard let data = try? await newPhoto?.loadTransferable(type: Data.self) else { return }
                    imageData = Self.normalizedImageData(from: data) ?? data
                }
            }
        }
    }

    private var visualAccentColor: Color {
        ProfileIconFrameCatalog.item(for: iconFrameID).primaryColor
    }

    private static func normalizedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 640
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > 0 ? min(1, maxDimension / longestSide) : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

private struct ProfileBadgeSelector: View {
    let badges: [ProfileBadgeModel]
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("バッジ")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(badges) { badge in
                        ProfileSelectableBadge(badge: badge, isSelected: selectedID == badge.id) {
                            guard badge.isUnlocked else { return }
                            selectedID = badge.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileSelectableBadge: View {
    let badge: ProfileBadgeModel
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(badge.isUnlocked ? tint.opacity(0.16) : Color(.tertiarySystemGroupedBackground))
                    Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(badge.isUnlocked ? tint : Color.secondary)
                }
                .frame(width: 44, height: 44)

                Text(badge.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint : .clear, lineWidth: 2)
            }
            .opacity(badge.isUnlocked ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!badge.isUnlocked)
    }
}

private struct ProfileFrameSelector: View {
    @Binding var selectedID: String
    let accentColor: Color
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アイコンフレーム")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileIconFrameCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                ProfileIconFrameView(style: item, accentColor: accentColor, size: 44)
                                if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(5)
                                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                                }
                            }
                            .frame(width: 48, height: 48)
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? item.primaryColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileStreakIconSelector: View {
    @Binding var selectedID: String
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストリーク")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(ProfileStreakIconCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Image(systemName: isUnlocked ? item.systemImage : "lock.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(isUnlocked ? Color(hex: item.tintHex) : Color.secondary)
                                    .frame(width: 44, height: 44)
                                    .background((isUnlocked ? Color(hex: item.tintHex) : Color.secondary).opacity(0.14), in: Circle())
                            }
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? Color(hex: item.tintHex) : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileCardStyleSelector: View {
    @Binding var selectedID: String
    let accentColor: Color
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プロフィールカード")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileCardStyleCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: isUnlocked ? item.systemImage : "lock.fill")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(isUnlocked ? item.markColor(accentColor: accentColor) : Color.secondary)
                                Spacer()
                                if selectedID == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(item.markColor(accentColor: accentColor))
                                }
                            }

                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            ProfileCardStylePreview(style: item, accentColor: accentColor)
                        }
                        .padding(10)
                        .background(item.backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? item.borderColor(accentColor: accentColor) : Color(.separator).opacity(0.12), lineWidth: selectedID == item.id ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileCardStylePreview: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        HStack(spacing: 4) {
            style.stripColor(accentColor: accentColor)
                .frame(width: 28)
            Color.clear
                .frame(width: 8)
            style.stripColor(accentColor: accentColor).opacity(0.45)
                .frame(width: 42)
            Color.clear
            style.stripColor(accentColor: accentColor).opacity(0.65)
                .frame(width: 24)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(Capsule())
    }
}

private struct ProfileDraft {
    let displayName: String
    let bio: String
    let imageData: Data?
    let badgeID: String
    let iconFrameID: String
    let streakIconID: String
    let cardStyleID: String
}

private struct ProfileBadgeModel: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: String
    let isUnlocked: Bool
    let progressText: String
}

private enum ProfileBadgeCatalog {
    static let defaultBadge = ProfileBadgeModel(
        id: ProfileDecorationUnlocks.defaultNameBadgeID,
        title: "ルーキー",
        systemImage: "person.crop.circle.fill.badge.checkmark",
        tint: "#2F80ED",
        isUnlocked: true,
        progressText: "初期"
    )

    static func items(metrics: UnlockMetrics, unlockItems: [UnlockItem]) -> [ProfileBadgeModel] {
        let unlockedIDs = ProfileDecorationUnlocks(unlockItems: unlockItems).nameBadgeIDs
        let unlockBadges = unlockItems
            .filter { $0.kind == .nameBadge }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.key < $1.key
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map { item in
                ProfileBadgeModel(
                    id: item.targetID,
                    title: item.displayName,
                    systemImage: item.systemImageName,
                    tint: item.tintHex,
                    isUnlocked: unlockedIDs.contains(item.targetID),
                    progressText: progressText(metrics: metrics, item: item)
                )
            }
        return [defaultBadge] + unlockBadges
    }

    static func equippedBadge(id: String?, badges: [ProfileBadgeModel]) -> ProfileBadgeModel {
        if let id, let selected = badges.first(where: { $0.id == id && $0.isUnlocked }) {
            return selected
        }
        if let unlocked = badges.first(where: \.isUnlocked) {
            return unlocked
        }
        return badges.first ?? defaultBadge
    }

    private static func progressText(metrics: UnlockMetrics, item: UnlockItem) -> String {
        if item.unlockedAt != nil {
            return "達成"
        }
        guard item.requiredValue > 0 else { return "0%" }
        let percent = Int((UnlockRules.progress(metrics: metrics, toward: item) * 100).rounded(.down))
        return "\(percent)%"
    }
}

struct ProfileIconFrameStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let primaryHex: String
    let secondaryHex: String
    let lineWidth: CGFloat

    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
}

enum ProfileIconFrameCatalog {
    static let defaultID = "halo"
    static let items: [ProfileIconFrameStyle] = [
        ProfileIconFrameStyle(id: "halo", title: "Halo", systemImage: "circle", primaryHex: "#2F80ED", secondaryHex: "#8AB4FF", lineWidth: 3),
        ProfileIconFrameStyle(id: "signal", title: "Signal", systemImage: "dot.radiowaves.left.and.right", primaryHex: "#00A8A8", secondaryHex: "#F2994A", lineWidth: 4),
        ProfileIconFrameStyle(id: "crown", title: "Crown", systemImage: "crown.fill", primaryHex: "#F2C94C", secondaryHex: "#6C5CE7", lineWidth: 3),
        ProfileIconFrameStyle(id: "focus", title: "Focus", systemImage: "scope", primaryHex: "#EB5757", secondaryHex: "#27AE60", lineWidth: 3)
    ]

    static func item(for id: String?) -> ProfileIconFrameStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

struct ProfileStreakIconStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: String
}

enum ProfileStreakIconCatalog {
    static let defaultID = "flame"
    static let items: [ProfileStreakIconStyle] = [
        ProfileStreakIconStyle(id: "flame", title: "赤い炎", systemImage: "flame.fill", tintHex: "#EB5757"),
        ProfileStreakIconStyle(id: "bolt", title: "金の炎", systemImage: "flame.fill", tintHex: "#F2C94C"),
        ProfileStreakIconStyle(id: "sun", title: "橙の炎", systemImage: "flame.fill", tintHex: "#F2994A"),
        ProfileStreakIconStyle(id: "spark", title: "紫の炎", systemImage: "flame.fill", tintHex: "#6C5CE7")
    ]

    static func item(for id: String?) -> ProfileStreakIconStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

@MainActor
struct ProfileCardStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let lightBackgroundHex: String
    let darkBackgroundHex: String
    let markHex: String?
    let stripOpacity: Double
    let borderWidth: CGFloat

    var backgroundColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? lightBackgroundHex : darkBackgroundHex)
            }
        )
    }

    var textColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#2A2440" : "#ECE8F5")
            }
        )
    }

    var secondaryTextColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#6A6388" : "#C8C1DA")
            }
        )
    }

    func markColor(accentColor: Color) -> Color {
        markHex.map(Color.init(hex:)) ?? accentColor
    }

    func stripColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(stripOpacity)
    }

    func borderColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(borderWidth > 1 ? 0.55 : 0.18)
    }
}

enum ProfileCardStyleCatalog {
    static let defaultID = "clean"
    static let items: [ProfileCardStyle] = [
        ProfileCardStyle(id: "clean", title: "Clean", systemImage: "rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: nil, stripOpacity: 0.35, borderWidth: 1),
        ProfileCardStyle(id: "glass", title: "Glass", systemImage: "sparkle.magnifyingglass", lightBackgroundHex: "#F7FBFF", darkBackgroundHex: "#221B3A", markHex: "#2F80ED", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "dawn", title: "Dawn", systemImage: "sunrise.fill", lightBackgroundHex: "#FFF8F0", darkBackgroundHex: "#2A2032", markHex: "#F2994A", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "mint", title: "Mint", systemImage: "leaf.fill", lightBackgroundHex: "#F2FBF6", darkBackgroundHex: "#18312B", markHex: "#27AE60", stripOpacity: 0.38, borderWidth: 1)
    ]

    static func item(for id: String?) -> ProfileCardStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

private enum ProfileFormat {
    static func duration(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
    }
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}

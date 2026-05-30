import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @Query(sort: \Friend.createdAt) private var friends: [Friend]

    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var isShowingShareProfile = false
    @State private var clock = TickClock(interval: 60)

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
        Color(hex: settings?.profileAccentColorHex ?? "#2F80ED")
    }

    private var invitePayload: FriendInvitePayload {
        FriendInvitePayload(
            code: FriendInvitePayload.code(from: settings?.id ?? UUID()),
            displayName: displayName,
            accentColorHex: settings?.profileAccentColorHex ?? "#2F80ED"
        )
    }

    private var recentChapters: [Chapter] {
        queriedChapters.sorted { $0.startTime > $1.startTime }
    }

    private var finishedChapters: [Chapter] {
        recentChapters.filter { $0.endTime != nil }
    }

    private var totalRecordedDuration: TimeInterval {
        recentChapters.reduce(0) { total, chapter in
            total + max(0, chapter.durationLive)
        }
    }

    private var totalEarnedScore: Int {
        let calendar = Calendar.current
        return (0..<365).reduce(0) { partial, offset in
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { return partial }
            let summary = scoreSummary(on: target)
            return partial + Int(summary.totalScore.rounded())
        }
    }

    private var recordedDays: [Date] {
        let grouped = Dictionary(grouping: recentChapters) { chapter in
            DayBoundary.dayStart(for: chapter.startTime)
        }
        return grouped.keys.sorted(by: >)
    }

    private var badges: [ProfileBadgeModel] {
        [
            ProfileBadgeModel(
                id: "starter",
                title: "ルーキー",
                systemImage: "person.crop.circle.fill.badge.checkmark",
                tint: "#2F80ED",
                isUnlocked: true,
                progressText: "初期"
            ),
            ProfileBadgeModel(
                id: "first_record",
                title: "はじめの記録",
                systemImage: "sparkles",
                tint: "#2F80ED",
                isUnlocked: !recentChapters.isEmpty,
                progressText: recentChapters.isEmpty ? "0/1" : "達成"
            ),
            ProfileBadgeModel(
                id: "three_days",
                title: "3日記録",
                systemImage: "calendar.badge.checkmark",
                tint: "#27AE60",
                isUnlocked: recordedDays.count >= 3,
                progressText: "\(min(recordedDays.count, 3))/3"
            ),
            ProfileBadgeModel(
                id: "seven_streak",
                title: "7日連続",
                systemImage: "flame.fill",
                tint: "#EB5757",
                isUnlocked: streakCount >= 7,
                progressText: "\(min(streakCount, 7))/7"
            ),
            ProfileBadgeModel(
                id: "ten_hours",
                title: "10時間",
                systemImage: "clock.fill",
                tint: "#6C5CE7",
                isUnlocked: totalRecordedDuration >= 36_000,
                progressText: "\(min(Int(totalRecordedDuration / 3600), 10))/10h"
            ),
            ProfileBadgeModel(
                id: "morning",
                title: "朝の記録",
                systemImage: "sunrise.fill",
                tint: "#F2994A",
                isUnlocked: finishedChapters.contains { Calendar.current.component(.hour, from: $0.startTime) < 9 },
                progressText: finishedChapters.contains { Calendar.current.component(.hour, from: $0.startTime) < 9 } ? "達成" : "未達成"
            )
        ]
    }

    private var equippedBadge: ProfileBadgeModel {
        ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges)
    }

    private var iconFrame: ProfileIconFrameStyle {
        ProfileIconFrameCatalog.item(for: settings?.profileIconFrameID)
    }

    private var streakIcon: ProfileStreakIconStyle {
        ProfileStreakIconCatalog.item(for: settings?.profileStreakIconID)
    }

    private var cardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: settings?.profileCardStyleID)
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
                        streak: streakCount,
                        totalScore: totalEarnedScore,
                        friendCount: acceptedFriendCount,
                        streakIcon: streakIcon
                    )

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
            .background(Color(.systemGroupedBackground))
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
                ProfileEditSheet(settings: settings, badges: badges, onSave: saveProfile)
            }
            .sheet(isPresented: $isShowingShareProfile) {
                ProfileShareSheet(payload: invitePayload)
            }
            .task {
                ensureUserSettings()
                clock.start()
            }
            .onDisappear {
                clock.stop()
            }
        }
    }

    private var streakCount: Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { break }
            let summary = scoreSummary(on: target)
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            count += 1
        }
        return count
    }

    private var acceptedFriendCount: Int {
        friends.filter { $0.status == .accepted }.count
    }

    private func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: plans(on: date),
            chapters: chapters(on: date),
            now: clock.now
        )
    }

    private func plans(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        return queriedPlans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date)
        return queriedChapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clock.now) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        let settings = UserSettings()
        modelContext.insert(settings)
        try? modelContext.save()
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
        target.profileAccentColorHex = draft.accentColorHex
        target.profileBadgeID = draft.badgeID
        target.profileIconFrameID = draft.iconFrameID
        target.profileStreakIconID = draft.streakIconID
        target.profileCardStyleID = draft.cardStyleID
        target.updatedAt = Date()
        try? modelContext.save()
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
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.trailing, 76)

                    EquippedBadgePill(badge: equippedBadge)

                    Text(bio.isEmpty ? "プロフィールを育てよう" : bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    ProfileHeroRhythmStrip(accentColor: cardStyle.stripColor(accentColor: accentColor))
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

private struct ProfileCardStyleMark: View {
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

private struct ProfileHeroRhythmStrip: View {
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

private struct ProfileIconFrameView: View {
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
            ProfileStatTile(title: "連続", value: "\(streak)日", systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            ProfileStatTile(title: "累計獲得", value: "\(totalScore)pt", systemImage: "star.fill", tint: Color(hex: "#F2994A"))
            ProfileStatTile(title: "友達", value: "\(friendCount)人", systemImage: "person.2.fill", tint: Color(hex: "#27AE60"))
        }
    }
}

private struct ProfileStatTile: View {
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

private struct ProfileEquipmentTile: View {
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

private struct ProfileEquipmentFrameTile: View {
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

private struct ProfileEquipmentCardStyleTile: View {
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

private struct ProfileEquipmentTileShell<Preview: View>: View {
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

private struct ProfileMiniCardStyleView: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(style.backgroundColor)
            .overlay(alignment: .bottom) {
                ProfileMiniRhythmStrip(accentColor: style.stripColor(accentColor: accentColor))
                    .frame(height: 3)
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

private struct ProfileMiniRhythmStrip: View {
    let accentColor: Color

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                accentColor.opacity(0.35)
                    .frame(width: proxy.size.width * 0.28)
                Color.clear
                    .frame(width: proxy.size.width * 0.1)
                accentColor.opacity(0.18)
                    .frame(width: proxy.size.width * 0.36)
                Color.clear
                accentColor.opacity(0.25)
                    .frame(width: proxy.size.width * 0.16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
    }
}

private struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var imageData: Data?
    @State private var accentColorHex: String
    @State private var badgeID: String
    @State private var iconFrameID: String
    @State private var streakIconID: String
    @State private var cardStyleID: String
    @State private var selectedPhoto: PhotosPickerItem?

    let badges: [ProfileBadgeModel]
    let onSave: (ProfileDraft) -> Void

    init(settings: UserSettings?, badges: [ProfileBadgeModel], onSave: @escaping (ProfileDraft) -> Void) {
        _displayName = State(initialValue: settings?.profileDisplayName ?? "")
        _bio = State(initialValue: settings?.profileBio ?? "")
        _imageData = State(initialValue: settings?.profileImageData)
        _accentColorHex = State(initialValue: settings?.profileAccentColorHex ?? "#2F80ED")
        _badgeID = State(initialValue: ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges).id)
        _iconFrameID = State(initialValue: settings?.profileIconFrameID ?? ProfileIconFrameCatalog.defaultID)
        _streakIconID = State(initialValue: settings?.profileStreakIconID ?? ProfileStreakIconCatalog.defaultID)
        _cardStyleID = State(initialValue: settings?.profileCardStyleID ?? ProfileCardStyleCatalog.defaultID)
        self.badges = badges
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
                            accentColor: Color(hex: accentColorHex),
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

                Section("カラー") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(ProfileAccentColor.allCases) { color in
                            Button {
                                accentColorHex = color.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: color.hex))
                                        .frame(width: 42, height: 42)
                                    if accentColorHex == color.hex {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("装備") {
                    ProfileBadgeSelector(
                        badges: badges,
                        selectedID: $badgeID
                    )

                    ProfileFrameSelector(
                        selectedID: $iconFrameID,
                        accentColor: Color(hex: accentColorHex)
                    )

                    ProfileStreakIconSelector(
                        selectedID: $streakIconID
                    )

                    ProfileCardStyleSelector(
                        selectedID: $cardStyleID,
                        accentColor: Color(hex: accentColorHex)
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
                                accentColorHex: accentColorHex,
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アイコンフレーム")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileIconFrameCatalog.items) { item in
                    Button {
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 10) {
                            ProfileIconFrameView(style: item, accentColor: accentColor, size: 44)
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
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileStreakIconSelector: View {
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストリーク")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(ProfileStreakIconCatalog.items) { item in
                    Button {
                        selectedID = item.id
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: item.systemImage)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color(hex: item.tintHex))
                                .frame(width: 44, height: 44)
                                .background(Color(hex: item.tintHex).opacity(0.14), in: Circle())
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
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileCardStyleSelector: View {
    @Binding var selectedID: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プロフィールカード")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileCardStyleCatalog.items) { item in
                    Button {
                        selectedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: item.systemImage)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(item.markColor(accentColor: accentColor))
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
    let accentColorHex: String
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
    static func equippedBadge(id: String?, badges: [ProfileBadgeModel]) -> ProfileBadgeModel {
        if let id, let selected = badges.first(where: { $0.id == id && $0.isUnlocked }) {
            return selected
        }
        if let unlocked = badges.first(where: \.isUnlocked) {
            return unlocked
        }
        return badges.first ?? ProfileBadgeModel(
            id: "starter",
            title: "ルーキー",
            systemImage: "person.crop.circle.fill.badge.checkmark",
            tint: "#2F80ED",
            isUnlocked: true,
            progressText: "初期"
        )
    }
}

private struct ProfileIconFrameStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let primaryHex: String
    let secondaryHex: String
    let lineWidth: CGFloat

    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
}

private enum ProfileIconFrameCatalog {
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

private struct ProfileStreakIconStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: String
}

private enum ProfileStreakIconCatalog {
    static let defaultID = "flame"
    static let items: [ProfileStreakIconStyle] = [
        ProfileStreakIconStyle(id: "flame", title: "Flame", systemImage: "flame.fill", tintHex: "#EB5757"),
        ProfileStreakIconStyle(id: "bolt", title: "Bolt", systemImage: "bolt.fill", tintHex: "#F2C94C"),
        ProfileStreakIconStyle(id: "sun", title: "Sun", systemImage: "sun.max.fill", tintHex: "#F2994A"),
        ProfileStreakIconStyle(id: "spark", title: "Spark", systemImage: "sparkles", tintHex: "#6C5CE7")
    ]

    static func item(for id: String?) -> ProfileStreakIconStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

@MainActor
private struct ProfileCardStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let backgroundHex: String
    let markHex: String?
    let stripOpacity: Double
    let borderWidth: CGFloat

    var backgroundColor: Color {
        Color(hex: backgroundHex)
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

private enum ProfileCardStyleCatalog {
    static let defaultID = "clean"
    static let items: [ProfileCardStyle] = [
        ProfileCardStyle(id: "clean", title: "Clean", systemImage: "rectangle", backgroundHex: "#FFFFFF", markHex: nil, stripOpacity: 0.35, borderWidth: 1),
        ProfileCardStyle(id: "glass", title: "Glass", systemImage: "sparkle.magnifyingglass", backgroundHex: "#F7FBFF", markHex: "#2F80ED", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "dawn", title: "Dawn", systemImage: "sunrise.fill", backgroundHex: "#FFF8F0", markHex: "#F2994A", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "mint", title: "Mint", systemImage: "leaf.fill", backgroundHex: "#F2FBF6", markHex: "#27AE60", stripOpacity: 0.38, borderWidth: 1)
    ]

    static func item(for id: String?) -> ProfileCardStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

private enum ProfileAccentColor: String, CaseIterable, Identifiable {
    case blue = "#2F80ED"
    case violet = "#6C5CE7"
    case green = "#27AE60"
    case orange = "#F2994A"
    case red = "#EB5757"
    case pink = "#D946EF"
    case teal = "#00A8A8"
    case gray = "#607D8B"

    var id: String { rawValue }
    var hex: String { rawValue }
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

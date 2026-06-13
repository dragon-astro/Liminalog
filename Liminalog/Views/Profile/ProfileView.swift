import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \Friend.createdAt) private var friends: [Friend]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]

    @State private var isShowingEditProfile = false
    @State private var isShowingShareProfile = false
    @State private var isShowingSettings = false
    @State private var isShowingUnlockGallery = false
    @State private var performanceSnapshot = ProfilePerformanceSnapshot.empty
    @State private var performanceSnapshotLoadedAt: Date?
    @State private var saveError: String?
    @State private var shareError: String?
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    @State private var didApplyDebugLaunchRoute = false
    #endif

    private var settings: UserSettings? {
        settingsList.first
    }

    private var displayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : ProfileDisplayNamePolicy.limited(name)
    }

    private var profileUserID: String? {
        let normalized = settings?.cloudUsernameNormalized.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty { return normalized }

        let raw = settings?.cloudUsername.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var bio: String {
        settings?.profileBio.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var accentColor: Color {
        if iconFrame.id == ProfileDecorationUnlocks.noIconFrameID {
            return Color(hex: settings?.profileAccentColorHex ?? "#2F80ED")
        }
        return iconFrame.primaryColor
    }

    private var decorationUnlocks: ProfileDecorationUnlocks {
        ProfileDecorationUnlocks(
            unlockItems: unlockItems,
            includesLockedCatalogItems: allowsLockedDecorationSelection
        )
    }

    private var invitePayload: FriendInvitePayload? {
        guard let username = profileUserID else { return nil }
        return FriendInvitePayload(
            username: username,
            displayName: displayName
        )
    }

    private var badges: [ProfileBadgeModel] {
        ProfileBadgeCatalog.items(
            metrics: performanceSnapshot.unlockMetrics,
            unlockItems: unlockItems,
            includesLockedItems: allowsLockedDecorationSelection
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

    private var freshUnlockItems: [UnlockItem] {
        ProfileDecorationUnlocks.freshUnlockedItems(
            unlockItems: unlockItems,
            settings: settings,
            visibleThemeIDs: Set(LiminalThemeCatalog.selectableThemes.map(\.id))
        )
    }

    private var hasFreshUnlockItems: Bool {
        !freshUnlockItems.isEmpty
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

    private var cumulativeScore: Int {
        performanceSnapshot.unlockMetrics.cumulativeScore
    }

    private var fragmentBalance: Int {
        LiminalLevel.fragmentBalance(
            score: cumulativeScore,
            exchangedCount: LiminalLevel.exchangedCount(in: unlockItems)
        )
    }

    private var allowsLockedDecorationSelection: Bool {
        #if DEBUG
        allowsLockedDecorationTesting
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ProfileHero(
                        displayName: displayName,
                        userID: profileUserID,
                        bio: bio,
                        imageData: settings?.profileImageData,
                        accentColor: accentColor,
                        equippedBadge: equippedBadge,
                        iconFrame: iconFrame,
                        cardStyle: cardStyle,
                        level: LiminalLevel.level(forScore: cumulativeScore),
                        onEdit: { isShowingEditProfile = true },
                        onShare: { openProfileShare() }
                    )
                    .padding(.bottom, cardStyle.hasGeneratedArtwork ? -36 : 0)

                    ProfileLevelGauge(
                        score: cumulativeScore,
                        onTap: { isShowingUnlockGallery = true }
                    )

                    ProfileStatsRow(
                        streak: performanceSnapshot.streakCount,
                        totalScore: performanceSnapshot.totalEarnedScore,
                        friendCount: acceptedFriendCount,
                        streakIcon: streakIcon
                    )

                    if !nextUnlockTargets.isEmpty || !unlockItems.isEmpty {
                        ProfileNextUnlockSection(
                            targets: nextUnlockTargets,
                            fragmentBalance: fragmentBalance,
                            showsGalleryIndicator: hasFreshUnlockItems,
                            onOpenGallery: { isShowingUnlockGallery = true }
                        )
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
            .navigationDestination(isPresented: $isShowingUnlockGallery) {
                UnlockGalleryView(initialMetrics: performanceSnapshot.unlockMetrics)
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
                if let invitePayload {
                    ProfileShareSheet(payload: invitePayload)
                }
            }
            .alert("プロフィールを共有できません", isPresented: shareErrorPresented) {
                Button("OK", role: .cancel) {
                    shareError = nil
                }
            } message: {
                Text(shareError ?? "")
            }
            .alert("プロフィールを保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
            .task {
                ensureUserSettings()
                refreshPerformanceSnapshot()
                applyDebugLaunchRouteIfNeeded()
            }
            .onChange(of: isShowingSettings) { _, isShowing in
                if !isShowing {
                    refreshPerformanceSnapshot()
                }
            }
        }
    }

    private func openProfileShare() {
        guard invitePayload != nil else {
            shareError = "プロフィール共有にはユーザーIDの設定が必要です。設定からユーザーIDを確定してください。"
            return
        }
        isShowingShareProfile = true
    }

    private var acceptedFriendCount: Int {
        friends.filter { $0.status == .accepted }.count
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        if SeedCoordinator.ensureUserSettingsIfAvailable(in: modelContext) == nil {
            NSLog("Liminalog: skipped ProfileView UserSettings initialization because the store is not ready")
        }
    }

    private func refreshPerformanceSnapshot(force: Bool = false) {
        let now = Date()
        if !force,
           let performanceSnapshotLoadedAt,
           now.timeIntervalSince(performanceSnapshotLoadedAt) < 120 {
            return
        }
        guard let snapshot = ProfilePerformanceSnapshot.loadIfAvailable(modelContext: modelContext, now: now) else {
            NSLog("Liminalog: skipped profile unlock refresh because performance snapshot could not be loaded")
            return
        }
        performanceSnapshot = snapshot
        performanceSnapshotLoadedAt = now
        UnlockStore(modelContext: modelContext).refresh(metrics: snapshot.unlockMetrics)
    }

    private func saveProfile(_ draft: ProfileDraft) -> Bool {
        let target: UserSettings
        if let settings {
            target = settings
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            target = created
        }

        target.profileDisplayName = ProfileDisplayNamePolicy.limited(draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines))
        target.profileBio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profileImageData = draft.imageData
        let badgeID = ProfileBadgeCatalog.equippedBadge(id: draft.badgeID, badges: badges).id
        let iconFrameID = decorationUnlocks.equippedIconFrameID(draft.iconFrameID)
        let streakIconID = decorationUnlocks.equippedStreakIconID(draft.streakIconID)
        let cardStyleID = decorationUnlocks.equippedCardStyleID(draft.cardStyleID)
        target.profileBadgeID = badgeID
        target.profileIconFrameID = iconFrameID
        target.profileStreakIconID = streakIconID
        target.profileCardStyleID = cardStyleID
        ProfileDecorationUnlocks.markEquippedItem(kind: .nameBadge, targetID: badgeID, unlockItems: unlockItems, settings: target)
        ProfileDecorationUnlocks.markEquippedItem(kind: .iconFrame, targetID: iconFrameID, unlockItems: unlockItems, settings: target)
        ProfileDecorationUnlocks.markEquippedItem(kind: .streakIcon, targetID: streakIconID, unlockItems: unlockItems, settings: target)
        ProfileDecorationUnlocks.markEquippedItem(kind: .cardStyle, targetID: cardStyleID, unlockItems: unlockItems, settings: target)
        target.updatedAt = Date()
        let didSave = saveSettingsChange("profile", showError: false)
        if didSave {
            refreshPerformanceSnapshot(force: true)
            CloudFriendShareRefreshCoordinator.requestRefresh(reason: "profile decoration changed")
        }
        return didSave
    }

    @discardableResult
    private func saveSettingsChange(_ action: String, showError: Bool) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            if showError {
                saveError = "時間をおいてもう一度試してください。"
            }
            return false
        }
    }

    private func applyDebugLaunchRouteIfNeeded() {
        #if DEBUG
        guard
            !didApplyDebugLaunchRoute,
            Self.debugShouldOpenUnlockGallery()
        else { return }
        didApplyDebugLaunchRoute = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            print("LiminalogUITestMetric debugOpenUnlockGallery requested")
            isShowingUnlockGallery = true
        }
        #endif
    }

    #if DEBUG
    private static func debugShouldOpenUnlockGallery() -> Bool {
        if let value = ProcessInfo.processInfo.environment["LiminalogDebugOpenUnlockGallery"] {
            return value == "1" || value.lowercased() == "true"
        }
        return ProcessInfo.processInfo.arguments.contains("-LiminalogDebugOpenUnlockGallery")
    }
    #endif

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented {
                saveError = nil
            }
        }
    }

    private var shareErrorPresented: Binding<Bool> {
        Binding {
            shareError != nil
        } set: { isPresented in
            if !isPresented {
                shareError = nil
            }
        }
    }
}

/// 自分のプロフィール専用のレベルゲージ行（doc 16 §12.0.1）。
/// 「あと◯◯でレベルアップ」は自分のダッシュボードにだけ出す。共有されるカード側は Lv 数字のみ。
private struct ProfileLevelGauge: View {
    let score: Int
    let onTap: () -> Void

    private var level: Int {
        LiminalLevel.level(forScore: score)
    }

    private var progress: (current: Int, required: Int, fraction: Double) {
        LiminalLevel.progressToNextLevel(score: score)
    }

    private var remainingScore: Int {
        max(progress.required - progress.current, 0)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("Lv.\(level)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
                    .monospacedDigit()

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(LiminalTheme.divider.opacity(0.7))
                        Capsule(style: .continuous)
                            .fill(LiminalTheme.accent.opacity(0.85))
                            .frame(width: progress.fraction <= 0 ? 0 : max(6, proxy.size.width * progress.fraction))
                    }
                }
                .frame(height: 5)

                Text("あと \(remainingScore.formatted())pt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LiminalTheme.divider.opacity(0.65), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("レベル\(level)。次のレベルまであと\(remainingScore)ポイント。タップでコレクションを開く")
    }
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}

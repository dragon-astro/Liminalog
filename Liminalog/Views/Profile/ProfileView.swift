import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \Friend.createdAt) private var friends: [Friend]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]

    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var isShowingShareProfile = false
    @State private var isShowingUnlockGallery = false
    @State private var performanceSnapshot = ProfilePerformanceSnapshot.empty
    @State private var saveError: String?
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

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

    private var invitePayload: FriendInvitePayload {
        FriendInvitePayload(
            code: FriendInvitePayload.code(from: settings?.id ?? UUID()),
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
                        bio: bio,
                        imageData: settings?.profileImageData,
                        accentColor: accentColor,
                        equippedBadge: equippedBadge,
                        iconFrame: iconFrame,
                        cardStyle: cardStyle,
                        onEdit: { isShowingEditProfile = true },
                        onShare: { isShowingShareProfile = true }
                    )
                    .padding(.bottom, cardStyle.hasGeneratedArtwork ? -36 : 0)

                    ProfileStatsRow(
                        streak: performanceSnapshot.streakCount,
                        totalScore: performanceSnapshot.totalEarnedScore,
                        friendCount: acceptedFriendCount,
                        streakIcon: streakIcon
                    )

                    if !nextUnlockTargets.isEmpty || !unlockItems.isEmpty {
                        ProfileNextUnlockSection(
                            targets: nextUnlockTargets,
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
                ProfileShareSheet(payload: invitePayload)
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
            }
            .onChange(of: isShowingSettings) { _, isShowing in
                if !isShowing {
                    refreshPerformanceSnapshot()
                }
            }
            .onChange(of: isShowingUnlockGallery) { _, isShowing in
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
        _ = saveSettingsChange("initial profile settings", showError: true)
    }

    private func refreshPerformanceSnapshot() {
        guard let snapshot = ProfilePerformanceSnapshot.loadIfAvailable(modelContext: modelContext, now: Date()) else {
            NSLog("Liminalog: skipped profile unlock refresh because performance snapshot could not be loaded")
            return
        }
        performanceSnapshot = snapshot
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

        target.profileDisplayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return saveSettingsChange("profile", showError: false)
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

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}

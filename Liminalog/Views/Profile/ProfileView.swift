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

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}

import SwiftData
import SwiftUI

struct UnlockGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]

    @State private var metrics: UnlockMetrics
    @State private var selectedTab: UnlockGalleryTab
    @State private var visibleSeenUnlockKeys: Set<String> = []
    @State private var saveError: String?
    #if DEBUG
    @State private var didLogDebugReady = false
    #endif
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

    private static let galleryFrameTargetIDs = Set(
        UnlockCatalog.items
            .filter { $0.kind == .iconFrame }
            .map(\.targetID)
    )

    private static let galleryCardTargetIDs = Set(
        UnlockCatalog.items
            .filter { $0.kind == .cardStyle }
            .map(\.targetID)
    )

    init(initialMetrics: UnlockMetrics) {
        _metrics = State(initialValue: initialMetrics)
        #if DEBUG
        _selectedTab = State(initialValue: Self.debugInitialTab() ?? .badges)
        #else
        _selectedTab = State(initialValue: .badges)
        #endif
    }

    private var settings: UserSettings? {
        settingsList.first
    }

    private var unlocks: ProfileDecorationUnlocks {
        ProfileDecorationUnlocks(
            unlockItems: unlockItems,
            includesLockedCatalogItems: allowsLockedDecorationSelection
        )
    }

    private var badges: [ProfileBadgeModel] {
        ProfileBadgeCatalog.items(
            metrics: metrics,
            unlockItems: unlockItems,
            includesLockedItems: allowsLockedDecorationSelection
        )
    }

    private var selectedBadgeID: String {
        ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges).id
    }

    private var selectedFrameID: String {
        unlocks.equippedIconFrameID(settings?.profileIconFrameID)
    }

    private var selectedStreakID: String {
        unlocks.equippedStreakIconID(settings?.profileStreakIconID)
    }

    private var selectedCardID: String {
        unlocks.equippedCardStyleID(settings?.profileCardStyleID)
    }

    private var selectedThemeID: String {
        unlocks.equippedThemeID(settings?.themeName)
    }

    private var galleryFrameStyles: [ProfileIconFrameStyle] {
        Self.galleryFrameTargetIDs.isEmpty ? ProfileIconFrameCatalog.visibleItems : ProfileIconFrameCatalog.visibleItems.filter { frame in
            frame.id == ProfileDecorationUnlocks.noIconFrameID
                || frame.id == ProfileDecorationUnlocks.defaultIconFrameID
                || Self.galleryFrameTargetIDs.contains(frame.id)
        }
    }

    private var galleryCardStyles: [ProfileCardStyle] {
        Self.galleryCardTargetIDs.isEmpty ? ProfileCardStyleCatalog.visibleItems : ProfileCardStyleCatalog.visibleItems.filter { style in
            style.id == ProfileDecorationUnlocks.noCardStyleID
                || style.id == ProfileDecorationUnlocks.defaultCardStyleID
                || Self.galleryCardTargetIDs.contains(style.id)
        }
    }

    private var visualAccentColor: Color {
        let frame = ProfileIconFrameCatalog.item(for: selectedFrameID)
        return frame.id == ProfileDecorationUnlocks.noIconFrameID ? LiminalTheme.accent : frame.primaryColor
    }

    private var allowsLockedDecorationSelection: Bool {
        #if DEBUG
        allowsLockedDecorationTesting
        #else
        false
        #endif
    }

    /// ひかりのかけら残高（導出値）。レベルアップごとに1枚、交換で1枚消費。
    private var fragmentBalance: Int {
        LiminalLevel.fragmentBalance(
            score: metrics.cumulativeScore,
            exchangedCount: LiminalLevel.exchangedCount(in: unlockItems)
        )
    }

    /// 個性装飾（.exchange）をかけら1枚で交換する。指標による自動解放はないので、
    /// ここで unlockedAt を立てるのが唯一の解放経路。
    private func exchange(item: UnlockItem?) {
        guard
            let item,
            item.requirementKind == .exchange,
            item.unlockedAt == nil,
            fragmentBalance > 0
        else { return }
        let now = Date()
        item.unlockedAt = now
        item.updatedAt = now
        // 自分で選んで交換したものに「new」ドットは不要なので既読も同時に付ける
        if !item.key.isEmpty {
            visibleSeenUnlockKeys.insert(item.key)
        }
        updateSettings(successFeedback: .commit) { settings in
            if !item.key.isEmpty, !settings.seenUnlockItemKeys.contains(item.key) {
                settings.seenUnlockItemKeys.append(item.key)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabBar
                tabContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        .navigationTitle("コレクション")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            prepareGalleryState()
            prepareCurrentTabVisit()
            logDebugReadyIfNeeded(reason: "task")
        }
        .onChange(of: selectedTab) {
            prepareCurrentTabVisit()
            logDebugReadyIfNeeded(reason: "tabChange")
        }
        .alert("コレクションを更新できませんでした", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func logDebugReadyIfNeeded(reason: String) {
        #if DEBUG
        guard !didLogDebugReady else { return }
        didLogDebugReady = true
        print(
            "LiminalogUITestMetric unlockGalleryReady",
            "reason=\(reason)",
            "tab=\(selectedTab.rawValue)",
            "badges=\(badges.count)",
            "frames=\(galleryFrameStyles.count)",
            "streaks=\(ProfileStreakIconCatalog.equippableItems.count)",
            "cards=\(galleryCardStyles.count)",
            "themes=\(LiminalThemeCatalog.selectableThemes.count)",
            "unlockItems=\(unlockItems.count)"
        )
        #endif
    }

    #if DEBUG
    private static func debugInitialTab() -> UnlockGalleryTab? {
        if let rawValue = ProcessInfo.processInfo.environment["LiminalogDebugUnlockGalleryTab"] {
            return UnlockGalleryTab(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-LiminalogDebugUnlockGalleryTab"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else { return nil }

        return UnlockGalleryTab(rawValue: arguments[arguments.index(after: flagIndex)].trimmingCharacters(in: .whitespacesAndNewlines))
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: selectedTab.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(selectedTab.tint)
                    .frame(width: 34, height: 34)
                    .background(selectedTab.tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTab.title)
                        .font(.headline)
                        .foregroundStyle(LiminalTheme.text)
                    Text(selectedTab.subtitle)
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }

                Spacer()
            }

            ProgressView(value: selectedTabProgress)
                .tint(selectedTab.tint)

            if selectedTab == .cards {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LiminalTheme.reward)
                    Text("ひかりのかけら ×\(fragmentBalance)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Spacer()
                    Text("レベルアップで1枚もらえます")
                        .font(.caption2)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
        .liminalSectionCard(cornerRadius: 8, padding: 14)
        .opacity(1 + Double(themeTransitionProgress * 0))
    }

    private var tabBar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(UnlockGalleryTab.allCases) { tab in
                Button {
                    if selectedTab != tab {
                        LiminalHaptics.tabSelection()
                    }
                    selectedTab = tab
                } label: {
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                                .font(.caption.weight(.bold))
                            Text(tab.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .foregroundStyle(selectedTab == tab ? .white : tab.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? tab.tint : tab.tint.opacity(0.13))
                        )

                        if hasFreshUnlock(in: tab) {
                            Circle()
                                .fill(LiminalTheme.reward)
                                .frame(width: 8, height: 8)
                                .overlay {
                                    Circle()
                                        .stroke(LiminalTheme.surface, lineWidth: 1.5)
                                }
                                .offset(x: 1, y: -1)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(hasFreshUnlock(in: tab) ? "新しく解放された項目があります" : "")
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            switch selectedTab {
            case .badges:
                badgeCards
            case .frames:
                frameCards
            case .streaks:
                streakCards
            case .cards:
                profileCardStyleCards
            case .themes:
                themeCards
            }
        }
    }

    @ViewBuilder
    private var badgeCards: some View {
        ForEach(badges) { badge in
            let item = unlockItem(kind: .nameBadge, targetID: badge.id)
            let isNone = badge.id == ProfileDecorationUnlocks.noNameBadgeID
            let isDefault = badge.id == ProfileDecorationUnlocks.defaultNameBadgeID
            let isEquipped = selectedBadgeID == badge.id
            UnlockGalleryItemCard(
                title: badge.title,
                conditionText: conditionText(for: item, isNone: isNone, isDefault: isDefault),
                systemImage: badge.systemImage,
                tint: Color(hex: badge.tint),
                isUnlocked: badge.isUnlocked,
                isEquipped: isEquipped,
                showsNewIndicator: showsNewIndicator(for: item, isUnlocked: badge.isUnlocked, isEquipped: isEquipped),
                progress: progress(
                    for: item,
                    isDefault: isNone || isDefault,
                    isUnlocked: badge.isUnlocked
                ),
                progressText: progressText(for: item, isNone: isNone, isDefault: isDefault, isUnlocked: badge.isUnlocked),
                actionTitle: "装着",
                equippedActionTitle: isNone ? "未装備" : "外す",
                allowsEquippedAction: !isNone,
                detailPreview: {
                    AnyView(
                        Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(badge.isUnlocked ? Color(hex: badge.tint) : LiminalTheme.secondaryText)
                            .frame(width: 140, height: 140)
                            .background((badge.isUnlocked ? Color(hex: badge.tint) : LiminalTheme.secondaryText).opacity(0.14), in: Circle())
                    )
                }
            ) {
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(badge.isUnlocked ? Color(hex: badge.tint) : LiminalTheme.secondaryText)
            } action: {
                guard badge.isUnlocked else { return }
                updateSettings(requestsFriendShareRefresh: true) { settings in
                    let nextID = isEquipped && !isNone ? ProfileDecorationUnlocks.noNameBadgeID : badge.id
                    settings.profileBadgeID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .nameBadge, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
            }
        }
    }

    @ViewBuilder
    private var frameCards: some View {
        // 単体表示（なし/初期装備）。獲得（instrument）系は系統ごとのスタックにまとめる。
        ForEach(galleryFrameStyles.filter { ProfileIconFrameCatalog.instrumentCategory(for: $0.id) == nil }) { frame in
            let item = unlockItem(kind: .iconFrame, targetID: frame.id)
            let isUnlocked = unlocks.iconFrameIsUnlocked(frame.id)
            let isNone = frame.id == ProfileDecorationUnlocks.noIconFrameID
            let isDefault = frame.id == ProfileDecorationUnlocks.defaultIconFrameID
            let isEquipped = selectedFrameID == frame.id
            UnlockGalleryItemCard(
                title: frame.title,
                conditionText: conditionText(for: item, isNone: isNone, isDefault: isDefault),
                systemImage: frame.systemImage,
                tint: frame.primaryColor,
                isUnlocked: isUnlocked,
                isEquipped: isEquipped,
                showsNewIndicator: showsNewIndicator(for: item, isUnlocked: isUnlocked, isEquipped: isEquipped),
                progress: progress(
                    for: item,
                    isDefault: isNone || isDefault,
                    isUnlocked: isUnlocked
                ),
                progressText: progressText(for: item, isNone: isNone, isDefault: isDefault, isUnlocked: isUnlocked),
                actionTitle: "装着",
                equippedActionTitle: isNone ? "未装備" : "外す",
                allowsEquippedAction: !isNone,
                detailPreview: isNone ? nil : {
                    AnyView(
                        ZStack {
                            Circle()
                                .fill(LiminalTheme.elevated)
                                .frame(width: 156, height: 156)
                            ProfileIconFrameView(style: frame, accentColor: frame.primaryColor, size: 164)
                        }
                    )
                },
                lockedActionTitle: item?.requirementKind == .exchange ? "かけら1枚で交換" : nil,
                isLockedActionEnabled: fragmentBalance > 0,
                lockedActionCaption: item?.requirementKind == .exchange ? "ひかりのかけら ×\(fragmentBalance)" : nil,
                lockedAction: item?.requirementKind == .exchange ? { exchange(item: item) } : nil
            ) {
                ZStack {
                    if isNone {
                        Image(systemName: frame.systemImage)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .frame(width: 52, height: 52)
                            .background(LiminalTheme.elevated, in: Circle())
                    } else {
                        Circle()
                            .fill(LiminalTheme.elevated)
                            .frame(width: 52, height: 52)
                        ProfileIconFrameView(style: frame, accentColor: frame.primaryColor, size: 54)
                    }
                }
            } action: {
                guard isUnlocked else { return }
                updateSettings(requestsFriendShareRefresh: true) { settings in
                    let nextID = isEquipped && !isNone ? ProfileDecorationUnlocks.noIconFrameID : frame.id
                    settings.profileIconFrameID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .iconFrame, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
            }
        }

        ForEach(InstrumentFrameCategory.allCases) { category in
            let styles = galleryFrameStyles.filter { ProfileIconFrameCatalog.instrumentCategory(for: $0.id) == category }
            if !styles.isEmpty {
                UnlockGalleryFrameStackCard(
                    category: category,
                    entries: styles.map(frameStackEntry(for:))
                )
            }
        }
    }

    private func frameStackEntry(for frame: ProfileIconFrameStyle) -> UnlockGalleryFrameStackCard.Entry {
        let item = unlockItem(kind: .iconFrame, targetID: frame.id)
        let isUnlocked = unlocks.iconFrameIsUnlocked(frame.id)
        let isEquipped = selectedFrameID == frame.id
        return UnlockGalleryFrameStackCard.Entry(
            style: frame,
            rank: ProfileIconFrameCatalog.instrumentRank(for: frame.id) ?? 1,
            isUnlocked: isUnlocked,
            isEquipped: isEquipped,
            conditionText: conditionText(for: item, isDefault: false),
            progress: progress(for: item, isDefault: false, isUnlocked: isUnlocked),
            progressText: progressText(for: item, isDefault: false, isUnlocked: isUnlocked),
            showsNewIndicator: showsNewIndicator(for: item, isUnlocked: isUnlocked, isEquipped: isEquipped)
        ) {
            guard isUnlocked else { return }
            updateSettings(requestsFriendShareRefresh: true) { settings in
                let nextID = isEquipped ? ProfileDecorationUnlocks.noIconFrameID : frame.id
                settings.profileIconFrameID = nextID
                ProfileDecorationUnlocks.markEquippedItem(kind: .iconFrame, targetID: nextID, unlockItems: unlockItems, settings: settings)
            }
        }
    }

    @ViewBuilder
    private var streakCards: some View {
        ForEach(ProfileStreakIconCatalog.equippableItems) { streak in
            let item = unlockItem(kind: .streakIcon, targetID: streak.id)
            let isUnlocked = unlocks.streakIconIsUnlocked(streak.id)
            let isDefault = streak.id == ProfileDecorationUnlocks.defaultStreakIconID
            let isEquipped = selectedStreakID == streak.id
            UnlockGalleryItemCard(
                title: streak.title,
                conditionText: conditionText(for: item, isDefault: isDefault),
                systemImage: streak.systemImage,
                tint: Color(hex: streak.tintHex),
                isUnlocked: isUnlocked,
                isEquipped: isEquipped,
                showsNewIndicator: showsNewIndicator(for: item, isUnlocked: isUnlocked, isEquipped: isEquipped),
                progress: progress(
                    for: item,
                    isDefault: isDefault,
                    isUnlocked: isUnlocked
                ),
                progressText: progressText(for: item, isDefault: isDefault, isUnlocked: isUnlocked),
                actionTitle: "装着",
                equippedActionTitle: isDefault ? "装着中" : "標準に戻す",
                allowsEquippedAction: !isDefault,
                detailPreview: {
                    AnyView(
                        Image(systemName: isUnlocked ? streak.systemImage : "lock.fill")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText)
                            .frame(width: 140, height: 140)
                            .background((isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText).opacity(0.14), in: Circle())
                    )
                }
            ) {
                Image(systemName: isUnlocked ? streak.systemImage : "lock.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText)
                    .frame(width: 56, height: 56)
                    .background((isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText).opacity(0.14), in: Circle())
            } action: {
                guard isUnlocked else { return }
                updateSettings(requestsFriendShareRefresh: true) { settings in
                    let nextID = isEquipped && !isDefault ? ProfileDecorationUnlocks.defaultStreakIconID : streak.id
                    settings.profileStreakIconID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .streakIcon, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
            }
        }
    }

    @ViewBuilder
    private var profileCardStyleCards: some View {
        ForEach(galleryCardStyles) { style in
            let item = unlockItem(kind: .cardStyle, targetID: style.id)
            let isUnlocked = unlocks.cardStyleIsUnlocked(style.id)
            let isNone = style.id == ProfileDecorationUnlocks.noCardStyleID
            let isDefault = style.id == ProfileDecorationUnlocks.defaultCardStyleID
            let isEquipped = selectedCardID == style.id
            UnlockGalleryItemCard(
                title: style.title,
                conditionText: conditionText(for: item, isNone: isNone, isDefault: isDefault),
                systemImage: style.systemImage,
                tint: style.markColor(accentColor: visualAccentColor),
                isUnlocked: isUnlocked,
                isEquipped: isEquipped,
                showsNewIndicator: showsNewIndicator(for: item, isUnlocked: isUnlocked, isEquipped: isEquipped),
                progress: progress(
                    for: item,
                    isDefault: isNone || isDefault,
                    isUnlocked: isUnlocked
                ),
                progressText: progressText(for: item, isNone: isNone, isDefault: isDefault, isUnlocked: isUnlocked),
                actionTitle: "装着",
                equippedActionTitle: isNone ? "未装備" : "外す",
                allowsEquippedAction: !isNone,
                detailPreview: {
                    AnyView(
                        ProfileMiniCardStyleView(style: style, accentColor: visualAccentColor)
                            .frame(width: 228, height: 142)
                    )
                },
                lockedActionTitle: item?.requirementKind == .exchange ? "かけら1枚で交換" : nil,
                isLockedActionEnabled: fragmentBalance > 0,
                lockedActionCaption: item?.requirementKind == .exchange ? "ひかりのかけら ×\(fragmentBalance)" : nil,
                lockedAction: item?.requirementKind == .exchange ? { exchange(item: item) } : nil,
                detailPreviewHeight: 150
            ) {
                UnlockGalleryCardThumbnailView(style: style, accentColor: visualAccentColor)
                    .frame(width: 74, height: 46)
            } action: {
                guard isUnlocked else { return }
                updateSettings(requestsFriendShareRefresh: true) { settings in
                    let nextID = isEquipped && !isNone ? ProfileDecorationUnlocks.noCardStyleID : style.id
                    settings.profileCardStyleID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .cardStyle, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
            }
        }
    }

    @ViewBuilder
    private var themeCards: some View {
        UnlockGalleryItemCard(
            title: "システム追従",
            conditionText: "初期装備",
            systemImage: "circle.lefthalf.filled",
            tint: LiminalTheme.accent,
            isUnlocked: true,
            isEquipped: selectedThemeID == ProfileDecorationUnlocks.defaultThemeID,
            showsNewIndicator: false,
            progress: 1,
            progressText: "100%",
            actionTitle: "適用",
            detailPreview: {
                AnyView(
                    UnlockGalleryThemeSwatch(definition: nil)
                        .frame(width: 264, height: 156)
                )
            }
        ) {
            UnlockGalleryThemeSwatch(definition: nil)
                .frame(width: 78, height: 46)
        } action: {
            updateTheme(ProfileDecorationUnlocks.defaultThemeID)
        }

        ForEach(LiminalThemeCatalog.fixedDefaultThemes, id: \.id) { theme in
            UnlockGalleryItemCard(
                title: theme.name,
                conditionText: "初期装備",
                systemImage: theme.appearance == .dark ? "moon.stars.fill" : "sunrise.fill",
                tint: Color(theme.palette.accent),
                isUnlocked: true,
                isEquipped: selectedThemeID == theme.id,
                showsNewIndicator: false,
                progress: 1,
                progressText: "100%",
                actionTitle: "適用",
                detailPreview: {
                    AnyView(
                        UnlockGalleryThemeSwatch(definition: theme)
                            .frame(width: 264, height: 156)
                    )
                }
            ) {
                UnlockGalleryThemeSwatch(definition: theme)
                    .frame(width: 78, height: 46)
            } action: {
                updateTheme(theme.id)
            }
        }

        ForEach(LiminalThemeCatalog.selectableThemes, id: \.id) { theme in
            let item = unlockItem(kind: .theme, targetID: theme.id)
            let isUnlocked = unlocks.themeIsUnlocked(theme.id)
            let isEquipped = selectedThemeID == theme.id
            UnlockGalleryItemCard(
                title: theme.name,
                conditionText: conditionText(for: item, isDefault: false),
                systemImage: item?.systemImageName ?? "sparkles",
                tint: Color(theme.palette.accent),
                isUnlocked: isUnlocked,
                isEquipped: isEquipped,
                showsNewIndicator: showsNewIndicator(for: item, isUnlocked: isUnlocked, isEquipped: isEquipped),
                progress: progress(for: item, isDefault: false, isUnlocked: isUnlocked),
                progressText: progressText(for: item, isDefault: false, isUnlocked: isUnlocked),
                actionTitle: "適用",
                detailPreview: {
                    AnyView(
                        UnlockGalleryThemeSwatch(definition: theme)
                            .frame(width: 264, height: 156)
                    )
                }
            ) {
                UnlockGalleryThemeSwatch(definition: theme)
                    .frame(width: 78, height: 46)
            } action: {
                guard isUnlocked else { return }
                updateTheme(theme.id)
            }
        }
    }

    private var selectedTabProgress: Double {
        let counts = selectedTabCounts
        guard counts.total > 0 else { return 0 }
        return Double(counts.unlocked) / Double(counts.total)
    }

    private var selectedTabCounts: (unlocked: Int, total: Int) {
        switch selectedTab {
        case .badges:
            return (badges.filter(\.isUnlocked).count, badges.count)
        case .frames:
            return (
                galleryFrameStyles.filter { unlocks.iconFrameIsUnlocked($0.id) }.count,
                galleryFrameStyles.count
            )
        case .streaks:
            return (
                ProfileStreakIconCatalog.equippableItems.filter { unlocks.streakIconIsUnlocked($0.id) }.count,
                ProfileStreakIconCatalog.equippableItems.count
            )
        case .cards:
            return (
                galleryCardStyles.filter { unlocks.cardStyleIsUnlocked($0.id) }.count,
                galleryCardStyles.count
            )
        case .themes:
            let standardCount = LiminalThemeCatalog.fixedDefaultThemes.count + 1
            let total = LiminalThemeCatalog.selectableThemes.count + standardCount
            let unlocked = LiminalThemeCatalog.selectableThemes.filter { unlocks.themeIsUnlocked($0.id) }.count + standardCount
            return (unlocked, total)
        }
    }

    private func progress(for item: UnlockItem?, isDefault: Bool, isUnlocked: Bool) -> Double {
        if isDefault || isUnlocked { return 1 }
        guard let item else { return 0 }
        return UnlockRules.progress(metrics: metrics, toward: item)
    }

    private func conditionText(for item: UnlockItem?, isNone: Bool = false, isDefault: Bool) -> String {
        if isNone { return "装飾なし" }
        if isDefault { return "初期装備" }
        guard let item else { return "解放条件を確認中" }
        return item.requirementKind.requirementText(requiredValue: item.requiredValue)
    }

    private func progressText(for item: UnlockItem?, isNone: Bool = false, isDefault: Bool, isUnlocked: Bool) -> String {
        if isNone || isDefault { return "100%" }
        guard let item else { return "0%" }
        let currentValue = isUnlocked ? item.requiredValue : metrics.value(for: item.requirementKind)
        return item.requirementKind.progressText(
            currentValue: currentValue,
            requiredValue: item.requiredValue,
            progress: progress(for: item, isDefault: isDefault, isUnlocked: isUnlocked)
        )
    }

    private func showsNewIndicator(for item: UnlockItem?, isUnlocked: Bool, isEquipped: Bool) -> Bool {
        guard
            let item,
            isUnlocked,
            !isEquipped,
            item.unlockedAt != nil,
            !item.key.isEmpty
        else { return false }
        return !visibleSeenUnlockKeys.contains(item.key)
    }

    private func hasFreshUnlock(in tab: UnlockGalleryTab) -> Bool {
        unlockedItemKeys(in: tab).contains { !visibleSeenUnlockKeys.contains($0) }
    }

    private func unlockItem(kind: UnlockKind, targetID: String) -> UnlockItem? {
        unlockItems.first { $0.kind == kind && $0.targetID == targetID }
    }

    private func prepareGalleryState() {
        guard unlockItems.isEmpty else { return }
        _ = UnlockStore(modelContext: modelContext).seedMasterItems()
    }

    private func updateTheme(_ id: String) {
        updateSettings { settings in
            settings.themeName = id
            ProfileDecorationUnlocks.markEquippedItem(kind: .theme, targetID: id, unlockItems: unlockItems, settings: settings)
        }
    }

    private func prepareCurrentTabVisit() {
        visibleSeenUnlockKeys = persistedSeenUnlockKeys()
        markSelectedTabAsSeen()
    }

    private func persistedSeenUnlockKeys() -> Set<String> {
        Set(settings?.seenUnlockItemKeys ?? [])
            .union(settings?.equippedUnlockItemKeys ?? [])
    }

    private func markSelectedTabAsSeen() {
        let keys = unlockedItemKeys(in: selectedTab)
        let newKeys = keys.filter { !visibleSeenUnlockKeys.contains($0) }
        guard !newKeys.isEmpty else { return }
        visibleSeenUnlockKeys.formUnion(newKeys)
        updateSettings(showError: false, successFeedback: nil) { settings in
            for key in newKeys where !settings.seenUnlockItemKeys.contains(key) {
                settings.seenUnlockItemKeys.append(key)
            }
        }
    }

    private func unlockedItemKeys(in tab: UnlockGalleryTab) -> [String] {
        unlockItems
            .filter { item in
                guard item.unlockedAt != nil, !item.key.isEmpty else { return false }
                switch tab {
                case .badges:
                    return item.kind == .nameBadge
                case .frames:
                    return item.kind == .iconFrame
                case .streaks:
                    return item.kind == .streakIcon
                case .cards:
                    return item.kind == .cardStyle
                case .themes:
                    return item.kind == .theme && LiminalThemeCatalog.selectableThemes.contains { $0.id == item.targetID }
                }
            }
            .map(\.key)
    }

    private func updateSettings(
        showError: Bool = true,
        successFeedback: UnlockGallerySuccessFeedback? = .selection,
        requestsFriendShareRefresh: Bool = false,
        _ update: (UserSettings) -> Void
    ) {
        let target: UserSettings
        if let settings {
            target = settings
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            target = created
        }
        update(target)
        target.updatedAt = Date()
        do {
            try modelContext.save()
            if requestsFriendShareRefresh {
                CloudFriendShareRefreshCoordinator.requestRefresh(reason: "profile decoration equipped")
            }
            if showError {
                playSuccessFeedback(successFeedback)
            }
        } catch {
            NSLog("Liminalog: failed to save unlock gallery settings: \(String(describing: error))")
            modelContext.rollback()
            if showError {
                LiminalHaptics.failure()
                saveError = "時間をおいてもう一度試してください。"
            }
        }
    }

    private func playSuccessFeedback(_ feedback: UnlockGallerySuccessFeedback?) {
        switch feedback {
        case .selection:
            LiminalHaptics.selection()
        case .commit:
            LiminalHaptics.commit()
        case nil:
            break
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

private enum UnlockGallerySuccessFeedback {
    case selection
    case commit
}

private enum UnlockGalleryTab: String, CaseIterable, Identifiable {
    case badges
    case frames
    case streaks
    case cards
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badges:
            "バッジ"
        case .frames:
            "フレーム"
        case .streaks:
            "連続"
        case .cards:
            "カード"
        case .themes:
            "テーマ"
        }
    }

    var subtitle: String {
        switch self {
        case .badges:
            "名前の横に出る称号を選ぶ"
        case .frames:
            "プロフィール画像の外周を変える"
        case .streaks:
            "ストリークのアイコン表現を変える"
        case .cards:
            "プロフィールカードの質感を変える"
        case .themes:
            "アプリ全体の空を切り替える"
        }
    }

    var systemImage: String {
        switch self {
        case .badges:
            "seal.fill"
        case .frames:
            "circle.dashed"
        case .streaks:
            "flame.fill"
        case .cards:
            "rectangle.fill"
        case .themes:
            "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .badges:
            Color(hex: "#2F80ED")
        case .frames:
            Color(hex: "#00A8A8")
        case .streaks:
            Color(hex: "#F2994A")
        case .cards:
            Color(hex: "#7E62C9")
        case .themes:
            LiminalTheme.accent
        }
    }
}

private struct UnlockGalleryItemCard<Preview: View>: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let title: String
    let conditionText: String
    let systemImage: String
    let tint: Color
    let isUnlocked: Bool
    let isEquipped: Bool
    let showsNewIndicator: Bool
    let progress: Double
    let progressText: String
    let actionTitle: String
    var equippedActionTitle: String = "装着中"
    var allowsEquippedAction = false
    /// 詳細シート用の大きいプレビュー。生成PNG系はscaleEffectだとぼけるため、ネイティブサイズで描き直す。
    var detailPreview: (() -> AnyView)? = nil
    /// 未解放時のアクション（かけら交換）。nil なら従来どおり「未解放」表示のみ。
    var lockedActionTitle: String? = nil
    var isLockedActionEnabled = false
    /// 未解放時にボタン下へ出す補足（所持かけら数など）。
    var lockedActionCaption: String? = nil
    var lockedAction: (() -> Void)? = nil
    var detailPreviewHeight: CGFloat = 180
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    @State private var isShowingDetail = false

    var body: some View {
        let _ = themeTransitionProgress
        Button {
            LiminalHaptics.openSheet()
            isShowingDetail = true
        } label: {
            compactTile
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)。\(conditionText)")
        .accessibilityHint("タップで詳細を表示")
        .sheet(isPresented: $isShowingDetail) {
            detailSheet
        }
    }

    /// 3列グリッド用のコンパクト表示。装着操作は詳細シート側に寄せている。
    private var compactTile: some View {
        VStack(spacing: 8) {
            preview()
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .opacity(isUnlocked ? 1 : 0.38)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            UnlockGalleryProgressBar(
                value: progress,
                tint: tint,
                isUnlocked: isUnlocked
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEquipped ? tint.opacity(0.8) : LiminalTheme.divider.opacity(0.65), lineWidth: isEquipped ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            statusBadge
                .padding(5)
        }
        .opacity(isUnlocked ? 1 : 0.62)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isEquipped {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(LiminalTheme.accent)
                .background(LiminalTheme.surface, in: Circle())
                .accessibilityLabel("装着中")
        } else if showsNewIndicator {
            Circle()
                .fill(LiminalTheme.reward)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(LiminalTheme.surface, lineWidth: 1.5)
                }
                .accessibilityLabel("新しく解放済み")
        } else if !isUnlocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(LiminalTheme.elevated, in: Circle())
        }
    }

    private var detailSheet: some View {
        VStack(spacing: 20) {
            Group {
                if let detailPreview {
                    detailPreview()
                } else {
                    preview()
                        .scaleEffect(2.4)
                }
            }
            .frame(height: detailPreviewHeight)
            .frame(maxWidth: .infinity)
            .opacity(isUnlocked ? 1 : 0.42)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
                Text(conditionText)
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("進捗")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                    Spacer()
                    Text(progressText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isUnlocked ? tint : LiminalTheme.secondaryText)
                }
                UnlockGalleryProgressBar(
                    value: progress,
                    tint: tint,
                    isUnlocked: isUnlocked
                )
            }

            // 装着の主導線はプロフィールカード編集。ここは控えめな補助ボタンに留める。
            Button {
                if isUnlocked {
                    action()
                } else {
                    lockedAction?()
                }
            } label: {
                Text(buttonTitle)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 22)
                    .frame(height: 32)
                    .foregroundStyle(buttonEnabled ? LiminalTheme.accent : LiminalTheme.secondaryText)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(buttonEnabled ? LiminalTheme.accent.opacity(0.65) : LiminalTheme.divider, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!buttonEnabled)

            if !isUnlocked, let lockedActionCaption {
                Text(lockedActionCaption)
                    .font(.caption2)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var buttonTitle: String {
        if !isUnlocked { return lockedActionTitle ?? "未解放" }
        return isEquipped ? equippedActionTitle : actionTitle
    }

    private var buttonEnabled: Bool {
        if !isUnlocked {
            return lockedAction != nil && isLockedActionEnabled
        }
        return !isEquipped || allowsEquippedAction
    }
}

/// 獲得（instrument）フレームを系統ごとに1枚へまとめたスタックカード。
/// タップでランク一覧シートを開き、大きいプレビューで確認しながら装着できる。
private struct UnlockGalleryFrameStackCard: View {
    struct Entry: Identifiable {
        let style: ProfileIconFrameStyle
        let rank: Int
        let isUnlocked: Bool
        let isEquipped: Bool
        let conditionText: String
        let progress: Double
        let progressText: String
        let showsNewIndicator: Bool
        let equip: () -> Void

        var id: String { style.id }
    }

    let category: InstrumentFrameCategory
    let entries: [Entry]

    @State private var isShowingDetail = false

    private var unlockedCount: Int {
        entries.filter(\.isUnlocked).count
    }

    /// スタックの顔は解放済みの最高ランク（未解放のみならRank 1）。
    private var displayEntry: Entry? {
        entries.last(where: \.isUnlocked) ?? entries.first
    }

    private var hasEquippedEntry: Bool {
        entries.contains(where: \.isEquipped)
    }

    var body: some View {
        Button {
            LiminalHaptics.openSheet()
            isShowingDetail = true
        } label: {
            compactTile
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title)。\(unlockedCount)/\(entries.count)ランク解放済み")
        .accessibilityHint("タップでランク一覧を表示")
        .sheet(isPresented: $isShowingDetail) {
            UnlockGalleryFrameStackSheet(category: category, entries: entries)
        }
    }

    private var compactTile: some View {
        VStack(spacing: 8) {
            ZStack {
                // 背後の輪郭で「重なっている」ことを示す
                Circle()
                    .stroke(LiminalTheme.divider.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                    .offset(x: 12, y: 0)
                Circle()
                    .stroke(LiminalTheme.divider.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 40, height: 40)
                    .offset(x: 20, y: 0)

                if let displayEntry {
                    ZStack {
                        Circle()
                            .fill(LiminalTheme.elevated)
                            .frame(width: 52, height: 52)
                        ProfileIconFrameView(style: displayEntry.style, accentColor: displayEntry.style.primaryColor, size: 54)
                    }
                    .offset(x: -8)
                    .opacity(displayEntry.isUnlocked ? 1 : 0.38)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)

            Text(category.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(unlockedCount)/\(entries.count) 解放")
                .font(.caption2)
                .foregroundStyle(LiminalTheme.secondaryText)

            UnlockGalleryProgressBar(
                value: Double(unlockedCount) / Double(max(entries.count, 1)),
                tint: LiminalTheme.accent,
                isUnlocked: unlockedCount > 0
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hasEquippedEntry ? LiminalTheme.accent.opacity(0.8) : LiminalTheme.divider.opacity(0.65), lineWidth: hasEquippedEntry ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            statusBadge
                .padding(5)
        }
        .opacity(unlockedCount > 0 ? 1 : 0.62)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if hasEquippedEntry {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(LiminalTheme.accent)
                .background(LiminalTheme.surface, in: Circle())
                .accessibilityLabel("装着中")
        } else if entries.contains(where: \.showsNewIndicator) {
            Circle()
                .fill(LiminalTheme.reward)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(LiminalTheme.surface, lineWidth: 1.5)
                }
                .accessibilityLabel("新しく解放済み")
        } else if unlockedCount == 0 {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(LiminalTheme.elevated, in: Circle())
        }
    }
}

private struct UnlockGalleryFrameStackSheet: View {
    let category: InstrumentFrameCategory
    let entries: [UnlockGalleryFrameStackCard.Entry]

    @State private var selectedID: String?

    private var selectedEntry: UnlockGalleryFrameStackCard.Entry? {
        if let selectedID, let entry = entries.first(where: { $0.id == selectedID }) {
            return entry
        }
        return entries.first(where: \.isEquipped)
            ?? entries.last(where: \.isUnlocked)
            ?? entries.first
    }

    var body: some View {
        VStack(spacing: 20) {
            if let entry = selectedEntry {
                ZStack {
                    Circle()
                        .fill(LiminalTheme.elevated)
                        .frame(width: 168, height: 168)
                    ProfileIconFrameView(style: entry.style, accentColor: entry.style.primaryColor, size: 176)
                }
                .frame(height: 190)
                .opacity(entry.isUnlocked ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.15), value: entry.id)

                VStack(spacing: 6) {
                    Text(entry.style.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(LiminalTheme.text)
                    Text(entry.conditionText)
                        .font(.subheadline)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                rankSelector

                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("進捗")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiminalTheme.secondaryText)
                        Spacer()
                        Text(entry.progressText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(entry.isUnlocked ? entry.style.primaryColor : LiminalTheme.secondaryText)
                    }
                    UnlockGalleryProgressBar(
                        value: entry.progress,
                        tint: entry.style.primaryColor,
                        isUnlocked: entry.isUnlocked
                    )
                }

                Button(action: entry.equip) {
                    Text(buttonTitle(for: entry))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 22)
                        .frame(height: 32)
                        .foregroundStyle(entry.isUnlocked ? LiminalTheme.accent : LiminalTheme.secondaryText)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(entry.isUnlocked ? LiminalTheme.accent.opacity(0.65) : LiminalTheme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!entry.isUnlocked)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var rankSelector: some View {
        HStack(spacing: 10) {
            ForEach(entries) { entry in
                let isSelected = entry.id == selectedEntry?.id
                Button {
                    if selectedID != entry.id {
                        LiminalHaptics.selection()
                    }
                    selectedID = entry.id
                } label: {
                    ZStack {
                        Circle()
                            .fill(isSelected ? entry.style.primaryColor.opacity(0.22) : LiminalTheme.elevated)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle()
                                    .stroke(isSelected ? entry.style.primaryColor : LiminalTheme.divider.opacity(0.65), lineWidth: isSelected ? 2 : 1)
                            }
                        if entry.isUnlocked {
                            Text("\(entry.rank)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(LiminalTheme.text)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if entry.isEquipped {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(LiminalTheme.accent)
                                .background(LiminalTheme.surface, in: Circle())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rank \(entry.rank)。\(entry.isUnlocked ? "解放済み" : "未解放")\(entry.isEquipped ? "・装着中" : "")")
            }
        }
    }

    private func buttonTitle(for entry: UnlockGalleryFrameStackCard.Entry) -> String {
        if !entry.isUnlocked { return "未解放" }
        return entry.isEquipped ? "外す" : "装着"
    }
}

private struct UnlockGalleryCardThumbnailView: View {
    let style: ProfileCardStyle
    let accentColor: Color

    private var markColor: Color {
        style.markColor(accentColor: accentColor)
    }

    var body: some View {
        if style.hasGeneratedArtwork {
            Image(style.thumbnailAssetName)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(markColor.opacity(0.45), lineWidth: 1)
                }
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(style.backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(markColor.opacity(0.45), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(markColor.opacity(style.id == ProfileDecorationUnlocks.noCardStyleID ? 0 : 0.34))
                        .frame(height: 6)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 5,
                                bottomTrailingRadius: 5,
                                topTrailingRadius: 0,
                                style: .continuous
                            )
                        )
                }
                .overlay {
                    Image(systemName: style.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(markColor)
                }
                .allowsHitTesting(false)
        }
    }
}

private struct UnlockGalleryProgressBar: View {
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let value: Double
    let tint: Color
    let isUnlocked: Bool

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        let _ = themeTransitionProgress
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LiminalTheme.divider.opacity(0.7))

                Capsule(style: .continuous)
                    .fill(progressFill)
                    .frame(width: clampedValue <= 0 ? 0 : max(6, proxy.size.width * clampedValue))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("進捗")
        .accessibilityValue("\(Int((clampedValue * 100).rounded()))%")
    }

    private var progressFill: Color {
        isUnlocked ? LiminalTheme.accent : LiminalTheme.accent.opacity(0.72)
    }
}

private struct UnlockGalleryThemeSwatch: View {
    let definition: LiminalThemeDefinition?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(gradient)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(swatchRingColor, lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(primaryColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(accentRingColor, lineWidth: 1))
                    .padding(5)
            }
    }

    private var primaryColor: Color {
        if let definition {
            return Color(definition.palette.accent)
        }
        return LiminalTheme.accent
    }

    private var accentRingColor: Color {
        guard let definition else {
            return .white.opacity(0.55)
        }
        if definition.id == LiminalThemeCatalog.daybreak.id {
            return Color(hex: "#7E777C").opacity(0.7)
        }
        if definition.appearance == .light {
            return Color(definition.palette.text).opacity(0.5)
        }
        return .white.opacity(0.55)
    }

    private var swatchRingColor: Color {
        guard let definition else {
            return .white.opacity(0.2)
        }
        if definition.id == LiminalThemeCatalog.daybreak.id {
            return Color(hex: "#8B8186").opacity(0.42)
        }
        if definition.appearance == .light {
            return Color(definition.palette.text).opacity(0.18)
        }
        return .white.opacity(0.2)
    }

    private var gradient: LinearGradient {
        if let definition {
            return LinearGradient(
                colors: [
                    Color(definition.palette.gradientTop),
                    Color(definition.palette.gradientMiddle),
                    Color(definition.palette.gradientBottom)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(LiminalThemeCatalog.dusk.palette.canvas),
                Color(LiminalThemeCatalog.dusk.palette.gradientMiddle),
                Color(LiminalThemeCatalog.daybreak.palette.gradientBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview("Unlock Gallery") {
    NavigationStack {
        UnlockGalleryView(initialMetrics: UnlockMetrics(recordedDays: 8, recordedHours: 12, streakDays: 7, earlyRecordDays: 4, distinctCategoryCount: 4))
    }
    .liminalogPreviewEnvironment()
}

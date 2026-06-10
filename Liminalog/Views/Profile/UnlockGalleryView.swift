import SwiftData
import SwiftUI

struct UnlockGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]

    @State private var metrics: UnlockMetrics
    @State private var selectedTab: UnlockGalleryTab = .badges
    @State private var visibleSeenUnlockKeys: Set<String> = []
    @State private var saveError: String?
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

    init(initialMetrics: UnlockMetrics) {
        _metrics = State(initialValue: initialMetrics)
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
        ProfileIconFrameCatalog.visibleItems.filter { frame in
            frame.id == ProfileDecorationUnlocks.noIconFrameID
                || frame.id == ProfileDecorationUnlocks.defaultIconFrameID
                || UnlockCatalog.items.contains { $0.kind == .iconFrame && $0.targetID == frame.id }
        }
    }

    private var galleryCardStyles: [ProfileCardStyle] {
        ProfileCardStyleCatalog.visibleItems.filter { style in
            style.id == ProfileDecorationUnlocks.noCardStyleID
                || style.id == ProfileDecorationUnlocks.defaultCardStyleID
                || UnlockCatalog.items.contains { $0.kind == .cardStyle && $0.targetID == style.id }
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
            refreshUnlockState()
            prepareCurrentTabVisit()
        }
        .onChange(of: selectedTab) {
            prepareCurrentTabVisit()
        }
        .alert("コレクションを更新できませんでした", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

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
        }
        .liminalSectionCard(cornerRadius: 8, padding: 14)
        .opacity(1 + Double(themeTransitionProgress * 0))
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UnlockGalleryTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Label(tab.title, systemImage: tab.systemImage)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(selectedTab == tab ? .white : tab.tint)
                                .padding(.horizontal, 12)
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
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
                allowsEquippedAction: !isNone
            ) {
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(badge.isUnlocked ? Color(hex: badge.tint) : LiminalTheme.secondaryText)
            } action: {
                guard badge.isUnlocked else { return }
                updateSettings { settings in
                    let nextID = isEquipped && !isNone ? ProfileDecorationUnlocks.noNameBadgeID : badge.id
                    settings.profileBadgeID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .nameBadge, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
            }
        }
    }

    @ViewBuilder
    private var frameCards: some View {
        ForEach(galleryFrameStyles) { frame in
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
                allowsEquippedAction: !isNone
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
                            .fill(frame.primaryColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        ProfileIconFrameView(style: frame, accentColor: frame.primaryColor, size: 54)
                    }
                }
            } action: {
                guard isUnlocked else { return }
                updateSettings { settings in
                    let nextID = isEquipped && !isNone ? ProfileDecorationUnlocks.noIconFrameID : frame.id
                    settings.profileIconFrameID = nextID
                    ProfileDecorationUnlocks.markEquippedItem(kind: .iconFrame, targetID: nextID, unlockItems: unlockItems, settings: settings)
                }
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
                allowsEquippedAction: !isDefault
            ) {
                Image(systemName: isUnlocked ? streak.systemImage : "lock.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText)
                    .frame(width: 56, height: 56)
                    .background((isUnlocked ? Color(hex: streak.tintHex) : LiminalTheme.secondaryText).opacity(0.14), in: Circle())
            } action: {
                guard isUnlocked else { return }
                updateSettings { settings in
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
                allowsEquippedAction: !isNone
            ) {
                ProfileMiniCardStyleView(style: style, accentColor: visualAccentColor)
                    .frame(width: 74, height: 46)
            } action: {
                guard isUnlocked else { return }
                updateSettings { settings in
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
            actionTitle: "適用"
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
                actionTitle: "適用"
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
                actionTitle: "適用"
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

    private func refreshUnlockState() {
        guard let snapshot = ProfilePerformanceSnapshot.loadIfAvailable(modelContext: modelContext, now: Date()) else {
            NSLog("Liminalog: skipped unlock gallery refresh because performance snapshot could not be loaded")
            return
        }
        metrics = snapshot.unlockMetrics
        UnlockStore(modelContext: modelContext).refresh(metrics: snapshot.unlockMetrics)
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
        guard !keys.isEmpty else { return }
        updateSettings(showError: false) { settings in
            for key in keys where !settings.seenUnlockItemKeys.contains(key) {
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

    private func updateSettings(showError: Bool = true, _ update: (UserSettings) -> Void) {
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
        } catch {
            NSLog("Liminalog: failed to save unlock gallery settings: \(String(describing: error))")
            modelContext.rollback()
            if showError {
                saveError = "時間をおいてもう一度試してください。"
            }
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
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        let _ = themeTransitionProgress
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                preview()
                    .frame(height: 58, alignment: .leading)
                    .opacity(isUnlocked ? 1 : 0.38)

                Spacer(minLength: 8)

                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LiminalTheme.accent)
                } else if showsNewIndicator {
                    Circle()
                        .fill(LiminalTheme.reward)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(LiminalTheme.surface, lineWidth: 2)
                        }
                        .padding(7)
                        .accessibilityLabel("新しく解放済み")
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(LiminalTheme.elevated, in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(conditionText)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("進捗")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                Spacer(minLength: 6)
                Text(progressText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isUnlocked ? tint : LiminalTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            UnlockGalleryProgressBar(
                value: progress,
                tint: tint,
                isUnlocked: isUnlocked
            )

            Button(action: action) {
                Text(isEquipped ? equippedActionTitle : actionTitle)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .foregroundStyle(isUnlocked ? .white : LiminalTheme.secondaryText)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isUnlocked ? LiminalTheme.accent : LiminalTheme.elevated)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isUnlocked || (isEquipped && !allowsEquippedAction))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEquipped ? tint.opacity(0.8) : LiminalTheme.divider.opacity(0.65), lineWidth: isEquipped ? 2 : 1)
        }
        .opacity(isUnlocked ? 1 : 0.62)
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
                    .fill(isUnlocked ? tint : tint.opacity(0.75))
                    .frame(width: clampedValue <= 0 ? 0 : max(6, proxy.size.width * clampedValue))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("進捗")
        .accessibilityValue("\(Int((clampedValue * 100).rounded()))%")
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

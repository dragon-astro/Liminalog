import SwiftUI
import SwiftData
import UIKit

private enum RootTab: Hashable, CaseIterable {
    case today
    case calendar
    case dashboard
    case friends
    case profile
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]
    @State private var appStores: AppStores?
    @State private var selectedTab: RootTab
    @State private var pendingFriendInviteURL: URL?
    @State private var renderedThemeID: String?
    @State private var transitionSourceThemeID: String?
    @State private var themeTransitionProgress: CGFloat = 1
    @State private var themeTransitionNonce = 0
    @State private var tabThemeRefreshEpochs: [RootTab: Int] = [:]
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

    init() {
        _selectedTab = State(initialValue: Self.initialTab())
    }

    /// 選択中テーマ（UserSettings.themeName を流用。"default" はシステム追従）。
    private var selectedThemeID: String {
        ProfileDecorationUnlocks(
            unlockItems: unlockItems,
            includesLockedCatalogItems: allowsLockedDecorationSelection
        ).equippedThemeID(settingsList.first?.themeName)
    }

    private var renderingThemeID: String {
        renderedThemeID ?? selectedThemeID
    }

    private var freshUnlockCount: Int {
        ProfileDecorationUnlocks.freshUnlockedItems(
            unlockItems: unlockItems,
            settings: settingsList.first,
            visibleThemeIDs: Set(LiminalThemeCatalog.selectableThemes.map(\.id))
        ).count
    }

    private var allowsLockedDecorationSelection: Bool {
        #if DEBUG
        allowsLockedDecorationTesting
        #else
        false
        #endif
    }

    var body: some View {
        ThemeTransitionHost(
            activeThemeID: renderingThemeID,
            sourceThemeID: transitionSourceThemeID,
            progress: themeTransitionProgress
        ) {
            Group {
                if let appStores {
                    let store = appStores.chapterStore
                    TabView(selection: $selectedTab) {
                        Tab("今日", systemImage: "clock.fill", value: RootTab.today) {
                            HomeView()
                                .id(themeRefreshID(for: .today))
                        }
                        Tab("カレンダー", systemImage: "calendar", value: RootTab.calendar) {
                            CalendarView()
                                .id(themeRefreshID(for: .calendar))
                        }
                        Tab("統計", systemImage: "chart.bar.fill", value: RootTab.dashboard) {
                            DashboardView()
                                .id(themeRefreshID(for: .dashboard))
                        }
                        Tab("友達", systemImage: "person.2.fill", value: RootTab.friends) {
                            FriendsView(pendingInviteURL: $pendingFriendInviteURL)
                                .id(themeRefreshID(for: .friends))
                        }
                        Tab("プロフィール", systemImage: "person.crop.circle", value: RootTab.profile) {
                            ProfileView()
                                .id(themeRefreshID(for: .profile))
                        }
                        .badge(freshUnlockCount)
                    }
                    .environment(store)
                } else {
                    ProgressView()
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .tint(LiminalTheme.accent)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            .task {
                guard appStores == nil else { return }
                let initializedStores = AppStores(modelContext: modelContext)
                let initializedStore = initializedStores.bootstrap()
                #if DEBUG
                let seedRequest = PreviewSupport.runtimeSeedRequest()
                if seedRequest.shouldSeedPreviewPlans {
                    initializedStore.seedPreviewPlansIfNeeded()
                }
                if seedRequest.shouldSeedDevData {
                    initializedStore.seedDevSampleChaptersIfNeeded()
                }
                #endif
                appStores = initializedStores
                await initializedStores.streakNotificationStore.refreshStreakBreakWarning()
                let didConsumeShortcutRoute = consumePendingShortcutRoute()
                #if DEBUG
                if !didConsumeShortcutRoute {
                    selectedTab = Self.initialTab()
                }
                #endif
            }
            .onAppear {
                guard renderedThemeID == nil else { return }
                renderedThemeID = selectedThemeID
            }
            .onChange(of: selectedThemeID) { oldID, newID in
                startThemeTransition(from: renderedThemeID ?? oldID, to: newID)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    consumePendingShortcutRoute()
                } else {
                    persistAppState(reason: "\(phase)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                persistAppState(reason: "did enter background")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                persistAppState(reason: "will terminate")
            }
            .onOpenURL { url in
                guard FriendInvitePayload(url: url) != nil else { return }
                pendingFriendInviteURL = url
                selectedTab = .friends
            }
        }
    }

    @discardableResult
    private func consumePendingShortcutRoute() -> Bool {
        guard let route = LiminalogShortcutRoute.consumePendingRoute() else { return false }
        selectedTab = RootTab(route)
        return true
    }

    private func startThemeTransition(from sourceID: String, to targetID: String) {
        guard sourceID != targetID else {
            renderedThemeID = targetID
            transitionSourceThemeID = nil
            themeTransitionProgress = 1
            return
        }

        themeTransitionNonce += 1
        let nonce = themeTransitionNonce
        transitionSourceThemeID = sourceID
        renderedThemeID = targetID
        themeTransitionProgress = 0

        withAnimation(LiminalTheme.themeTransitionAnimation) {
            themeTransitionProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard themeTransitionNonce == nonce else { return }
            transitionSourceThemeID = nil
            themeTransitionProgress = 1
            refreshThemeDependentTabs()
        }
    }

    private func themeRefreshID(for tab: RootTab) -> String {
        "\(tab)-\(tabThemeRefreshEpochs[tab, default: 0])"
    }

    private func refreshThemeDependentTabs() {
        // テーマ選択中のナビゲーションを保つため、プロフィールタブは再生成しない。
        for tab in RootTab.allCases where tab != .profile {
            tabThemeRefreshEpochs[tab, default: 0] += 1
        }
    }

    private func persistAppState(reason: String) {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to persist app state on \(reason): \(String(describing: error))")
        }

        UserDefaults.standard.synchronize()
        UserDefaults(suiteName: SharedModelContainer.appGroupID)?.synchronize()
    }

    private static func initialTab() -> RootTab {
        #if DEBUG
        if let environmentValue = ProcessInfo.processInfo.environment["LiminalogInitialRootTab"] {
            return tab(from: environmentValue)
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-LiminalogInitialRootTab"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return .today
        }

        return tab(from: arguments[arguments.index(after: flagIndex)])
        #else
        return .today
        #endif
    }

    private static func tab(from rawValue: String) -> RootTab {
        switch rawValue.lowercased() {
        case "calendar":
            return .calendar
        case "dashboard":
            return .dashboard
        case "friends":
            return .friends
        case "profile":
            return .profile
        default:
            return .today
        }
    }
}

private struct ThemeTransitionHost<Content: View>: View, Animatable {
    let activeThemeID: String
    let sourceThemeID: String?
    var progress: CGFloat
    let content: () -> Content

    init(
        activeThemeID: String,
        sourceThemeID: String?,
        progress: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.activeThemeID = activeThemeID
        self.sourceThemeID = sourceThemeID
        self.progress = progress
        self.content = content
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        LiminalThemeCatalog.activeThemeID = activeThemeID
        LiminalThemeCatalog.transitionSourceThemeID = sourceThemeID
        LiminalThemeCatalog.transitionProgress = progress
        return content()
            .environment(\.liminalThemeID, activeThemeID)
            .environment(\.liminalThemeTransitionProgress, progress)
            .preferredColorScheme(chromeColorScheme)
            .toolbarColorScheme(chromeColorScheme, for: .navigationBar)
            .toolbarColorScheme(chromeColorScheme, for: .tabBar)
    }

    private var chromeThemeID: String {
        if let sourceThemeID, progress < 0.5 {
            return sourceThemeID
        }
        return activeThemeID
    }

    private var chromeColorScheme: ColorScheme? {
        LiminalThemeCatalog.preferredColorScheme(for: chromeThemeID)
    }
}

private extension RootTab {
    init(_ shortcutRoute: LiminalogShortcutRoute) {
        switch shortcutRoute {
        case .today:
            self = .today
        case .calendar:
            self = .calendar
        case .dashboard:
            self = .dashboard
        case .profile:
            self = .profile
        }
    }
}

#Preview {
    RootTabView()
        .liminalogPreviewEnvironment()
}

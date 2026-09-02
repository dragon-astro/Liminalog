import Combine
import CoreData
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
    @State private var lastRemoteChangeDuplicateMergeAt: Date?
    @State private var pendingRemoteChangeDuplicateMergeTask: Task<Void, Never>?
    @State private var pendingRemoteChangeRequiresFullMerge = false
    @State private var isShowingStorageFallbackNotice = false
    private let refreshIncomingFriendShares: (@MainActor (String) async -> Void)?
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

    init(refreshIncomingFriendShares: (@MainActor (String) async -> Void)? = nil) {
        self.refreshIncomingFriendShares = refreshIncomingFriendShares
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
                        Tab("ホーム", systemImage: "clock.fill", value: RootTab.today) {
                            HomeView()
                                .id(themeRefreshID(for: .today))
                                .onAppear { TabPerformanceDiagnostics.event("Today tab visible") }
                        }
                        Tab("カレンダー", systemImage: "calendar", value: RootTab.calendar) {
                            CalendarView()
                                .id(themeRefreshID(for: .calendar))
                                .onAppear { TabPerformanceDiagnostics.event("Calendar tab visible") }
                        }
                        Tab("統計", systemImage: "chart.bar.fill", value: RootTab.dashboard) {
                            StatisticsTabContent(purchaseStore: appStores.purchaseStore)
                                .id(themeRefreshID(for: .dashboard))
                                .onAppear { TabPerformanceDiagnostics.event("Dashboard tab visible") }
                        }
                        Tab("友達", systemImage: "person.2.fill", value: RootTab.friends) {
                            FriendsView(
                                pendingInviteURL: $pendingFriendInviteURL,
                                refreshIncomingFriendShares: refreshIncomingFriendShares
                            )
                                .id(themeRefreshID(for: .friends))
                                .onAppear { TabPerformanceDiagnostics.event("Friends tab visible") }
                        }
                        Tab("プロフィール", systemImage: "person.crop.circle", value: RootTab.profile) {
                            ProfileView()
                                .id(themeRefreshID(for: .profile))
                                .onAppear { TabPerformanceDiagnostics.event("Profile tab visible") }
                        }
                    }
                    .environment(store)
                    .environment(appStores.planPresetStore)
                    .environment(appStores.purchaseStore)
                } else {
                    ProgressView()
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            // 装飾カードやスコア表示のレイアウトを守るため、文字サイズはシステム設定に追従させない。
            .dynamicTypeSize(.large)
            .tint(LiminalTheme.accent)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            .task {
                guard appStores == nil else { return }
                let initializedStores = AppStores(modelContext: modelContext)
                let initializedStore = await initializedStores.bootstrapWithStoreReadinessRetry()
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
                let purchaseRuntimePolicy = PurchaseStoreRuntimePolicy.current()
                if purchaseRuntimePolicy.shouldStartStoreKitOnAppLaunch {
                    Task {
                        await initializedStores.purchaseStore.start()
                    }
                }
                if SharedModelContainer.storageMode != .cloudSync {
                    isShowingStorageFallbackNotice = true
                }
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
            .onChange(of: selectedTab) { oldTab, newTab in
                guard oldTab != newTab else { return }
                newTab.recordSelectionPerformanceEvent()
                LiminalHaptics.tabSelection()
            }
            .onChange(of: selectedThemeID) { oldID, newID in
                startThemeTransition(from: renderedThemeID ?? oldID, to: newID)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    consumePendingShortcutRoute()
                    if let appStores {
                        let purchaseRuntimePolicy = PurchaseStoreRuntimePolicy.current()
                        if purchaseRuntimePolicy.shouldRefreshEntitlementsOnSceneActivation {
                            Task {
                                await appStores.purchaseStore.refreshEntitlementsIfStale(
                                    maxAge: purchaseRuntimePolicy.sceneActivationRefreshMaxAge
                                )
                            }
                        }
                        scheduleRemoteChangeDuplicateMerge(
                            reason: "scene active",
                            activeDelay: 35,
                            includeTimelineRecords: false
                        )
                    }
                } else {
                    pendingRemoteChangeDuplicateMergeTask?.cancel()
                    pendingRemoteChangeDuplicateMergeTask = nil
                    persistAppState(reason: "\(phase)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                if appStores != nil, pendingRemoteChangeRequiresFullMerge {
                    runCloudDuplicateMerge(reason: "did enter background", includeTimelineRecords: true)
                }
                persistAppState(reason: "did enter background")
            }
            // CloudKitインポートが届いても、ユーザー操作中に全件統合を割り込ませない。
            // active中は表示に出やすい小さな重複だけ遅延回収し、履歴全体の統合はbackground/長いidleへ逃がす。
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .NSPersistentStoreRemoteChange)
                    .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            ) { _ in
                guard appStores != nil else { return }
                pendingRemoteChangeRequiresFullMerge = true
                scheduleRemoteChangeDuplicateMerge(
                    reason: "remote change",
                    activeDelay: 45,
                    includeTimelineRecords: false
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                persistAppState(reason: "will terminate")
            }
            .onOpenURL { url in
                guard FriendInvitePayload(url: url) != nil else { return }
                pendingFriendInviteURL = url
                selectedTab = .friends
            }
            .alert(storageFallbackTitle, isPresented: $isShowingStorageFallbackNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageFallbackMessage)
            }
        }
    }

    /// 保存先がフォールバックしている（iCloud同期や永続化が縮退している）ことを起動時に告知する。
    private var storageFallbackTitle: String {
        switch SharedModelContainer.storageMode {
        case .cloudSync:
            return ""
        case .appGroupLocal, .deviceLocal:
            return "iCloud同期を開始できませんでした"
        case .inMemory:
            return "記録を保存できない状態です"
        }
    }

    private var storageFallbackMessage: String {
        switch SharedModelContainer.storageMode {
        case .cloudSync:
            return ""
        case .appGroupLocal:
            return "記録はこの端末の中に保存されますが、iCloudへのバックアップと他の端末との同期は行われません。iCloudのサインイン状態と空き容量を確認して、アプリを起動し直してください。"
        case .deviceLocal:
            return "記録はこの端末の中に保存されますが、iCloud同期とウィジェット連携は利用できません。端末の空き容量を確認して、アプリを起動し直してください。"
        case .inMemory:
            return "アプリを閉じると今回の記録が失われます。端末の空き容量を確認して、アプリを起動し直してください。"
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

    private func scheduleRemoteChangeDuplicateMerge(
        reason: String,
        activeDelay: TimeInterval,
        includeTimelineRecords: Bool,
        now: Date = Date()
    ) {
        pendingRemoteChangeDuplicateMergeTask?.cancel()

        let minimumInterval: TimeInterval = includeTimelineRecords ? 180 : 90
        let cooldown = lastRemoteChangeDuplicateMergeAt.map {
            max(0, minimumInterval - now.timeIntervalSince($0))
        } ?? 0
        let delay = max(activeDelay, cooldown)

        pendingRemoteChangeDuplicateMergeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds(for: delay))
            guard !Task.isCancelled, appStores != nil else { return }
            runCloudDuplicateMerge(reason: reason, includeTimelineRecords: includeTimelineRecords)
            pendingRemoteChangeDuplicateMergeTask = nil
        }
    }

    private func runCloudDuplicateMerge(reason: String, includeTimelineRecords: Bool) {
        let startedAt = Date()
        let mergeStore = CloudDuplicateMergeStore(modelContext: modelContext)
        let merged = TabPerformanceDiagnostics.measure("Cloud duplicate merge") {
            includeTimelineRecords ? mergeStore.mergeAll() : mergeStore.mergeLightweight()
        }
        lastRemoteChangeDuplicateMergeAt = Date()
        if includeTimelineRecords {
            pendingRemoteChangeRequiresFullMerge = false
        }
        if merged > 0 {
            CloudFriendShareRefreshCoordinator.postSharedRecordsDidChange()
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > 0.08 {
            NSLog("Liminalog: duplicate merge on \(reason) took \(String(format: "%.3f", elapsed))s")
        }
    }

    private func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
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
    func recordSelectionPerformanceEvent() {
        switch self {
        case .today:
            TabPerformanceDiagnostics.event("Today tab selected")
        case .calendar:
            TabPerformanceDiagnostics.event("Calendar tab selected")
        case .dashboard:
            TabPerformanceDiagnostics.event("Dashboard tab selected")
        case .friends:
            TabPerformanceDiagnostics.event("Friends tab selected")
        case .profile:
            TabPerformanceDiagnostics.event("Profile tab selected")
        }
    }

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

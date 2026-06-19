import SwiftUI
import SwiftData

private enum TodayPage: String, CaseIterable, Identifiable {
    case yesterday
    case today
    case tomorrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yesterday: "昨日"
        case .today: "今日"
        case .tomorrow: "明日"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .yesterday: "昨日の振り返り"
        case .today: "今日の記録"
        case .tomorrow: "明日の予定"
        }
    }
}

private enum TomorrowPlanMode: String, CaseIterable, Identifiable {
    case timeline
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "時間軸"
        case .list: "リスト"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "calendar.day.timeline.left"
        case .list: "list.bullet.rectangle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .timeline: "明日を時間軸で表示"
        case .list: "明日をリストで表示"
        }
    }
}

private struct HomePlanCreateRequest: Identifiable {
    let id = UUID()
    let initialDate: Date
    let startsAsAllDay: Bool
}

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.createdAt)]) private var categories: [Category]
    @AppStorage("home.tomorrowPlanMode") private var tomorrowPlanModeRawValue = TomorrowPlanMode.timeline.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false
    @State private var selectedPage: TodayPage = HomeView.defaultInitialTodayPage
    @State private var editingChapter: Chapter? = nil
    @State private var editingPlan: PlanBlock? = nil
    @State private var planCreateRequest: HomePlanCreateRequest? = nil
    @State private var clock = TickClock(interval: 60)
    @State private var pendingLiveActivitySyncTask: Task<Void, Never>?
    @State private var tomorrowHasActionableGap = false
    @State private var didApplyInitialPage = false
    @State private var selectedTomorrowTimelineCategoryID: UUID?
    @State private var tomorrowTimelineVisibleHour = 7
    @State private var tomorrowScheduleInteractionActive = false
    @State private var tomorrowPlanReloadToken = 0

    var body: some View {
        // 各ページをプロフィールと同じ NavigationStack { ScrollView } 構造にする。
        // TabView(.page) を safe area 外まで広げてページがバー裏まで届くようにし、
        // コンテンツの safe area は各 NavigationStack が再適用する（上端停止は維持）。
        // これでガラスのバーが白いシステム地ではなく暖色グラデ/コンテンツをぼかす。
        ZStack {
            // 画面全体（上下バー裏含む）にグラデを敷く。ガラスのバーが白ではなく
            // この暖色グラデをぼかすようにして、下端の白を消す。
            LiminalTheme.canvasGradient.ignoresSafeArea()

            TabView(selection: todayPageSelection) {
                ForEach(scrollPages) { page in
                    NavigationStack {
                        dayPage(page)
                            .background(LiminalTheme.canvasGradient)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { toolbarContent(for: page) }
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .onChange(of: selectedPage) { _, _ in
            refreshTomorrowCoverage()
        }
        .sheet(item: $editingChapter) { chapter in
            ChapterEditSheet(chapter: chapter)
        }
        .sheet(item: $editingPlan, onDismiss: reloadTomorrowPlansAfterEditing) { plan in
            PlanCreateSheet(plan: plan)
        }
        .sheet(item: $planCreateRequest, onDismiss: reloadTomorrowPlansAfterEditing) { request in
            PlanCreateSheet(initialDate: request.initialDate, startsAsAllDay: request.startsAsAllDay)
        }
        .onAppear {
            clock.start()
            applyInitialPage()
            store.seedDefaultCategorySetsIfNeeded()
            scheduleLiveActivitySyncAfterAppear()
            refreshTomorrowCoverage()
        }
        .onDisappear {
            pendingLiveActivitySyncTask?.cancel()
            pendingLiveActivitySyncTask = nil
            clock.stop()
        }
    }

    private func scheduleLiveActivitySyncAfterAppear() {
        pendingLiveActivitySyncTask?.cancel()
        pendingLiveActivitySyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            store.syncLiveActivityWithActiveChapter()
            pendingLiveActivitySyncTask = nil
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for page: TodayPage) -> some ToolbarContent {
        if page == .tomorrow {
            ToolbarItem(placement: .topBarLeading) {
                tomorrowPlanModeMenu
            }
        }
        ToolbarItem(placement: .principal) {
            TodayPageTextTabs(
                selection: todayPageSelection,
                showsTomorrowIndicator: tomorrowHasActionableGap
            )
        }
        if page == .today {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: CategorySettingsView()) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                }
                .accessibilityLabel("カテゴリ設定")
            }
        } else if page == .tomorrow {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    planCreateRequest = defaultTomorrowPlanCreateRequest
                    LiminalHaptics.openSheet()
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                }
                .accessibilityLabel("明日の予定を追加")
            }
        }
    }

    private var tomorrowPlanModeMenu: some View {
        Menu {
            ForEach(TomorrowPlanMode.allCases) { mode in
                Button {
                    setTomorrowPlanMode(mode)
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                }
                .accessibilityLabel(mode.accessibilityLabel)
            }
        } label: {
            Image(systemName: selectedTomorrowPlanMode.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(LiminalTheme.accent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("明日の表示を切り替え")
    }

    @ViewBuilder
    private func dayPage(_ page: TodayPage) -> some View {
        switch page {
        case .yesterday:
            YesterdayReviewPage(date: yesterdayDate) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    selectedPage = .tomorrow
                }
            }
                .id(dayID(for: yesterdayDate))
        case .today:
            TodayRecordPage(date: todayDate, editingChapter: $editingChapter)
                .id(dayID(for: todayDate))
        case .tomorrow:
            TomorrowPlanPage(
                date: tomorrowDate,
                mode: selectedTomorrowPlanMode,
                categories: categories,
                planTitleFontSize: planTitleFontSize,
                planTitleBold: planTitleBold,
                reloadToken: tomorrowPlanReloadToken,
                visibleHour: $tomorrowTimelineVisibleHour,
                selectedCategoryID: $selectedTomorrowTimelineCategoryID,
                isScheduleInteractionActive: $tomorrowScheduleInteractionActive,
                onEditPlan: { plan in
                    editingPlan = plan
                },
                onScheduleChanged: {
                    refreshTomorrowCoverage()
                }
            )
                .id(dayID(for: tomorrowDate))
        }
    }

    private var todayDate: Date {
        dayID(for: clock.now)
    }

    private var yesterdayDate: Date {
        relativeDate(-1)
    }

    private var tomorrowDate: Date {
        relativeDate(1)
    }

    private var defaultTomorrowPlanCreateRequest: HomePlanCreateRequest {
        if let start = firstAvailableTomorrowPlanStart {
            return HomePlanCreateRequest(initialDate: start, startsAsAllDay: false)
        }
        return HomePlanCreateRequest(
            initialDate: DayBoundary.dayStart(for: tomorrowDate, calendar: .japanese),
            startsAsAllDay: true
        )
    }

    private var firstAvailableTomorrowPlanStart: Date? {
        let calendar = Calendar.japanese
        let boundary = DayBoundary(date: tomorrowDate, calendar: calendar)
        let preferred = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrowDate) ?? boundary.dayStart
        let latestStart = calendar.date(byAdding: .hour, value: -1, to: boundary.dayEnd) ?? preferred

        var candidate = preferred
        while candidate <= latestStart {
            let candidateEnd = calendar.date(byAdding: .hour, value: 1, to: candidate) ?? candidate
            if !store.hasTimedPlanOverlap(startTime: candidate, endTime: candidateEnd) {
                return candidate
            }
            guard let nextCandidate = calendar.date(byAdding: .minute, value: 15, to: candidate),
                  nextCandidate > candidate
            else { break }
            candidate = nextCandidate
        }

        return nil
    }

    private func relativeDate(_ dayOffset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: dayOffset, to: todayDate) ?? todayDate
    }

    private func dayID(for date: Date) -> Date {
        DayBoundary.dayStart(for: date, calendar: .japanese)
    }

    private func refreshTomorrowCoverage() {
        let boundary = DayBoundary(date: tomorrowDate, calendar: .japanese)
        let plans = ScoreSnapshotLoader.plannedBlocks(
            in: DateInterval(start: boundary.dayStart, end: boundary.dayEnd),
            modelContext: modelContext
        )
        tomorrowHasActionableGap = PlanCoverageSummary.make(date: tomorrowDate, plans: plans).hasActionableGap
    }

    private var debugInitialTodayPage: TodayPage {
        Self.defaultInitialTodayPage
    }

    private var todayPageSelection: Binding<TodayPage> {
        Binding(
            get: { selectedPage },
            set: { newValue in
                selectedPage = newValue
            }
        )
    }

    private var scrollPages: [TodayPage] {
        TodayPage.allCases
    }

    private var selectedTomorrowPlanMode: TomorrowPlanMode {
        TomorrowPlanMode(rawValue: tomorrowPlanModeRawValue) ?? .timeline
    }

    private func setTomorrowPlanMode(_ mode: TomorrowPlanMode) {
        guard selectedTomorrowPlanMode != mode else { return }
        tomorrowPlanModeRawValue = mode.rawValue
        LiminalHaptics.selection()
    }

    private func reloadTomorrowPlansAfterEditing() {
        tomorrowPlanReloadToken += 1
        refreshTomorrowCoverage()
    }

    private func applyInitialPage() {
        guard !didApplyInitialPage else { return }
        didApplyInitialPage = true

        selectedPage = debugInitialTodayPage
    }

    private static var defaultInitialTodayPage: TodayPage {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-LiminalogInitialTodayPage"),
              arguments.indices.contains(index + 1),
              let page = TodayPage(rawValue: arguments[index + 1]) else {
            return .today
        }
        return page
        #else
        return .today
        #endif
    }
}

private struct TodayPageTextTabs: View {
    @Binding var selection: TodayPage
    let showsTomorrowIndicator: Bool
    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: 28) {
            ForEach(TodayPage.allCases) { page in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selection = page
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Text(page.title)
                                .font(.headline.weight(selection == page ? .bold : .semibold))
                                .foregroundStyle(selection == page ? LiminalTheme.text : LiminalTheme.secondaryText.opacity(0.68))
                                .lineLimit(1)

                            if page == .tomorrow, showsTomorrowIndicator {
                                Circle()
                                    .fill(LiminalTheme.reward)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 8, y: -1)
                                    .accessibilityHidden(true)
                            }
                        }

                        ZStack {
                            Capsule()
                                .fill(Color.clear)
                                .frame(width: 22, height: 3)
                            if selection == page {
                                Capsule()
                                    .fill(LiminalTheme.accent)
                                    .matchedGeometryEffect(id: "today-page-underline", in: underlineNamespace)
                                    .frame(width: 22, height: 3)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityAddTraits(selection == page ? .isSelected : [])
            }
        }
        .frame(maxWidth: 220)
    }
}

private struct TodayRecordPage: View {
    @Environment(ChapterStore.self) private var store

    let date: Date
    @Binding var editingChapter: Chapter?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CurrentChapterCard()
                // CategoryGrid 内のチェブロンで折りたたみを行う。
                CategoryGrid()
                TimelineView(
                    date: date,
                    title: "",
                    editingChapter: $editingChapter,
                    splitCards: true
                )
                .id("\(date.timeIntervalSince1970)-\(store.contentRevision)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}

private struct TomorrowPlanPage: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    let date: Date
    let mode: TomorrowPlanMode
    let categories: [Category]
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let reloadToken: Int
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onEditPlan: (PlanBlock) -> Void
    let onScheduleChanged: () -> Void

    @State private var timelinePlans: [PlanBlock] = []
    @State private var clock = TickClock(interval: 60)

    var body: some View {
        Group {
            switch mode {
            case .timeline:
                timelineMode
            case .list:
                CalendarDayView(
                    date: date,
                    showsNavigationControls: false,
                    allowsDayNavigation: false,
                    contentPadding: 16,
                    showsPlanningStatus: true
                )
            }
        }
        .onAppear {
            clock.start()
            normalizeSelectedCategory()
            reloadTimelinePlans()
        }
        .onDisappear {
            clock.stop()
        }
        .onChange(of: date) { _, _ in
            reloadTimelinePlans()
        }
        .onChange(of: reloadToken) { _, _ in
            reloadTimelinePlans()
        }
        .onChange(of: categories.map(\.id)) { _, _ in
            normalizeSelectedCategory()
        }
    }

    private var timelineMode: some View {
        VStack(spacing: 0) {
            HomeTomorrowPlanningStatusIndicator(
                remainingText: planningDeadlineText,
                coverage: planningCoverage
            )
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 2)

            HomeTomorrowTimelineCategoryPalette(
                categories: categories,
                selectedCategoryID: $selectedCategoryID
            )

            GeometryReader { proxy in
                EditablePlanTimelineView(
                    date: date,
                    plans: timelinePlans,
                    categories: categories,
                    visibleCategoryIDs: nil,
                    isEditingEnabled: store.canCreatePlan(startTime: date, isAllDay: false),
                    planTitleFontSize: planTitleFontSize,
                    planTitleBold: planTitleBold,
                    isInteractionEnabled: true,
                    isPageSwipeActive: false,
                    visibleHour: $visibleHour,
                    selectedCategoryID: $selectedCategoryID,
                    isScheduleInteractionActive: $isScheduleInteractionActive,
                    onEditPlan: onEditPlan,
                    onScheduleChanged: {
                        reloadTimelinePlans()
                        onScheduleChanged()
                    }
                )
                .frame(
                    width: max(1, proxy.size.width - 32),
                    height: max(1, proxy.size.height - 6),
                    alignment: .top
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
        .background(LiminalTheme.canvasGradient)
    }

    private func reloadTimelinePlans() {
        timelinePlans = PlanStore(modelContext: modelContext).plannedBlocks(on: date)
    }

    private var planningCoverage: PlanCoverageSummary {
        PlanCoverageSummary.make(date: date, plans: timelinePlans)
    }

    private var planningDeadlineText: String {
        let deadline = DayBoundary.dayStart(for: date, calendar: .japanese)
        let remaining = deadline.timeIntervalSince(clock.now)
        guard remaining > 0 else { return "調整中" }
        return compactRemainingDuration(remaining)
    }

    private func compactRemainingDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return remainingHours > 0 ? "\(days)日\(remainingHours)時間" : "\(days)日"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)時間\(minutes)分"
        }
        if hours > 0 {
            return "\(hours)時間"
        }
        return "\(minutes)分"
    }

    private func normalizeSelectedCategory() {
        if let selectedCategoryID, categories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }
        selectedCategoryID = categories.first?.id
    }
}

private struct HomeTomorrowPlanningStatusIndicator: View {
    let remainingText: String
    let coverage: PlanCoverageSummary

    private var hasGap: Bool {
        coverage.hasActionableGap
    }

    private var tint: Color {
        hasGap ? CalendarSemanticColor.planGap : CalendarSemanticColor.planFilled
    }

    private var statusText: String {
        hasGap ? "空きあり" : "予定登録済み"
    }

    private var statusIcon: String {
        hasGap ? "circle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.caption.weight(.bold))

            Text("残り \(remainingText)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 10)

            Image(systemName: statusIcon)
                .font(.caption2.weight(.bold))
                .symbolRenderingMode(.hierarchical)

            Text(statusText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("明日の予定づくりの残り時間")
        .accessibilityValue("\(remainingText)、\(statusText)")
    }
}

private struct HomeTomorrowTimelineCategoryPalette: View {
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if categories.isEmpty {
                    HomeTomorrowTimelineEmptyCategoryChip()
                } else {
                    ForEach(categories) { category in
                        Button {
                            selectedCategoryID = category.id
                            LiminalHaptics.selection()
                        } label: {
                            HomeTomorrowTimelineCategoryChip(
                                category: category,
                                isSelected: category.id == selectedCategoryID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 6)
    }
}

private struct HomeTomorrowTimelineCategoryChip: View {
    let category: Category
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon ?? "circle.fill")
                .font(.system(size: 10, weight: .bold))

            Text(category.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(isSelected ? .white : category.displayColor)
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(
            Capsule()
                .fill(isSelected ? category.displayColor : category.displayColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(category.displayColor.opacity(isSelected ? 0.9 : 0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name)を選択")
    }
}

private struct HomeTomorrowTimelineEmptyCategoryChip: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 10.5, weight: .bold))

            Text("カテゴリなし")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(LiminalTheme.secondaryText)
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background(
            Capsule()
                .fill(LiminalTheme.elevated.opacity(0.72))
        )
        .overlay(
            Capsule()
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("カテゴリなし")
    }
}

private struct YesterdayReviewPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @State private var cachedPayload: DailyReflectionPayload?
    @State private var cachedPayloadSourceSignature: String?
    @State private var persistedSnapshotSignatures: Set<String> = []

    let date: Date
    let onPlanTomorrow: () -> Void

    init(date: Date, onPlanTomorrow: @escaping () -> Void) {
        self.date = date
        self.onPlanTomorrow = onPlanTomorrow
        let boundary = DayBoundary(date: date, calendar: .japanese)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let chapterLookbackStart = Calendar.japanese.date(byAdding: .day, value: -28, to: dayStart) ?? dayStart
        _queriedPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < dayEnd && $0.endTime > dayStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
        _queriedChapters = Query(
            filter: #Predicate<Chapter> {
                $0.startTime >= chapterLookbackStart && $0.startTime < dayEnd
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    var body: some View {
        let payload = resolvedPayload

        ScrollView {
            VStack(spacing: 14) {
                DailyReflectionPayloadCard(
                    payload: payload,
                    onPlanTomorrow: onPlanTomorrow,
                    onPersistSnapshot: persistDailyCardSnapshotIfNeeded
                )
                .equatable()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .task(id: payloadSourceSignature) {
            refreshPayloadCache()
        }
    }

    private var resolvedPayload: DailyReflectionPayload {
        if cachedPayloadSourceSignature == payloadSourceSignature,
           let cachedPayload {
            return cachedPayload
        }
        return makePayload()
    }

    private var payloadSourceSignature: String {
        [
            "\(date.timeIntervalSince1970)",
            queriedPlans.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ","),
            queriedChapters.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.endTime?.timeIntervalSince1970 ?? -1)" }.joined(separator: ",")
        ].joined(separator: "|")
    }

    private func makePayload() -> DailyReflectionPayload {
        DailyReflectionPayload.make(
            date: date,
            queriedPlans: queriedPlans,
            queriedChapters: queriedChapters
        )
    }

    @MainActor
    private func refreshPayloadCache() {
        cachedPayload = makePayload()
        cachedPayloadSourceSignature = payloadSourceSignature
    }

    @MainActor
    private func persistDailyCardSnapshotIfNeeded(_ payload: DailyReflectionPayload) {
        let signature = payload.snapshotSignature
        guard !persistedSnapshotSignatures.contains(signature) else { return }
        persistedSnapshotSignatures.insert(signature)
        DailyCardSnapshotStore(modelContext: modelContext).upsert(
            date: payload.date,
            summary: payload.summary,
            persona: payload.persona,
            categoryRows: payload.categoryRows,
            recordedDuration: payload.recordedDuration
        )
    }
}

private struct YesterdayScoreCard: View {
    let date: Date
    let summary: ScoreSummary
    let chapters: [Chapter]
    let dayBoundary: DayBoundary
    let topCategory: (category: Category, duration: TimeInterval)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ReviewScoreRing(score: summary.totalScore, hasScore: summary.plannedDuration > 0, color: scoreColor)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreColor)
                            .frame(width: 22, height: 22)
                            .background(scoreColor.opacity(0.14), in: Circle())

                        Text(date.japaneseMonthDayWeekday)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Text(summary.gradeText)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }

            YesterdayChapterRibbon(
                chapters: chapters,
                dayBoundary: dayBoundary,
                fallbackColor: scoreColor
            )
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: scoreColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor)
                        .frame(width: 24, height: 24)
                        .liminalGlassFill(in: Circle())
                        .padding(16)
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scoreColor.opacity(summary.plannedDuration > 0 ? 0.22 : 0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var scoreColor: Color {
        reviewScoreColor(summary)
    }

    private var heroSubtitle: String {
        if summary.plannedDuration == 0 {
            if let topCategory {
                return "\(topCategory.category.name)が一番長い昨日でした"
            }
            return "予定がある日ほど振り返りが育ちます"
        }
        if let topCategory {
            return "\(topCategory.category.name)を中心に過ごした1日"
        }
        return "予定と実績を振り返ります"
    }
}

private struct ReviewScoreRing: View {
    let score: Double
    let hasScore: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(LiminalTheme.elevated, lineWidth: 10)

            Circle()
                .trim(from: 0, to: hasScore ? min(max(score / 100, 0), 1) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(hasScore ? "\(Int(score.rounded()))" : "-")
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                Text("pt")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
        .frame(width: 92, height: 92)
        .shadow(color: color.opacity(hasScore ? 0.2 : 0), radius: 10, y: 4)
    }
}

private struct YesterdayChapterRibbon: View {
    let chapters: [Chapter]
    let dayBoundary: DayBoundary
    let fallbackColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LiminalTheme.elevated)

                    ForEach(chapters) { chapter in
                        if let segment = segment(for: chapter, width: width) {
                            Rectangle()
                                .fill(chapter.category?.displayColor ?? fallbackColor)
                                .frame(width: max(segment.width, 2), height: 18)
                                .offset(x: segment.x)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 18)

            HStack {
                Text("0")
                Spacer()
                Text("12")
                Spacer()
                Text("24")
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(LiminalTheme.tertiaryText)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("昨日の24時間リズム")
    }

    private func segment(for chapter: Chapter, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
        let start = max(chapter.startTime, dayBoundary.dayStart)
        guard end > start else { return nil }
        let total = dayBoundary.dayEnd.timeIntervalSince(dayBoundary.dayStart)
        guard total > 0 else { return nil }
        let x = width * CGFloat(start.timeIntervalSince(dayBoundary.dayStart) / total)
        let segmentWidth = width * CGFloat(end.timeIntervalSince(start) / total)
        return (max(0, x), max(0, segmentWidth))
    }
}

private func reviewScoreColor(_ summary: ScoreSummary) -> Color {
    guard summary.plannedDuration > 0 else { return .secondary }
    switch summary.totalScore {
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

private func friendlyDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(Int(seconds / 60), 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0, minutes > 0 {
        return "\(hours)時間\(minutes)分"
    } else if hours > 0 {
        return "\(hours)時間"
    } else {
        return "\(minutes)分"
    }
}

#Preview("Home") {
    HomeView()
        .liminalogPreviewEnvironment()
}

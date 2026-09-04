import SwiftUI
import SwiftData
import CoreData
import Combine
import UIKit

private struct CalendarPlanDuplicateCategoryKey: Hashable {
    let isDefault: Bool
    let normalizedName: String
}

private enum CalendarPlanDuplicateKey: Hashable {
    case source(String)
    case manual(
        category: CalendarPlanDuplicateCategoryKey?,
        normalizedTitle: String,
        startMinute: Int,
        endMinute: Int,
        isAllDay: Bool,
        normalizedNote: String
    )
}

enum CalendarTabCacheRefreshPlan: Hashable {
    case immediateVisibleRange
    case deferredCurrentMonth
    case deferredVisibleRange
}

enum CalendarTabCacheRefreshPolicy {
    static func plan(
        hasCachedPageData: Bool,
        loadedContentRevision: Int?,
        currentContentRevision: Int,
        requiresExternalRefresh: Bool
    ) -> CalendarTabCacheRefreshPlan {
        guard hasCachedPageData else { return .immediateVisibleRange }
        if requiresExternalRefresh || loadedContentRevision != currentContentRevision {
            return .deferredVisibleRange
        }
        return .deferredCurrentMonth
    }
}

struct CalendarView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.createdAt)]) private var categories: [Category]
    @Query(sort: [SortDescriptor(\Friend.displayName), SortDescriptor(\Friend.createdAt)]) private var friends: [Friend]
    @Query(sort: [SortDescriptor(\PlanPreset.sortOrder), SortDescriptor(\PlanPreset.createdAt)]) private var planPresets: [PlanPreset]

    @AppStorage("calendar.filter.usesCustomCategories") private var usesCustomCategoryFilter = false
    @AppStorage("calendar.filter.categoryIDs") private var storedCategoryFilterIDs = ""
    @AppStorage("calendar.filter.overlayFriendIDs") private var storedOverlayFriendIDs = ""
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = CalendarPlanTitleMetrics.defaultSize
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false

    @State private var visibleMonth = CalendarView.currentMonthStart
    @State private var anchorMonth = CalendarView.currentMonthStart
    @State private var monthScrolledOffset: Int? = 0
    @State private var pageDataByMonth: [Date: CalendarMonthPageData] = [:]
    @State private var loadedContentRevision: Int?
    @State private var deferredTabRefreshPlan: CalendarTabCacheRefreshPlan?
    @State private var externalRefreshRevision = 0
    @State private var loadedExternalRefreshRevision = 0
    @State private var showingMonthPicker = false
    @State private var pickerYear = Calendar.japanese.component(.year, from: Date())
    @State private var pickerMonth = Calendar.japanese.component(.month, from: Date())
    @State private var pickerDay = Calendar.japanese.component(.day, from: Date())
    @State private var showingCalendarSettings = false
    @State private var showingCalendarSearch = false
    @State private var showingCalendarFilter = false
    @State private var selectedDay: CalendarDayPresentation?
    @State private var editingPlan: PlanBlock?
    @State private var pendingPlanCreation: CalendarPlanCreationRequest?
    @State private var displayMode = Self.initialDisplayMode()
    @State private var timelineAnchorDate = Calendar.japanese.startOfDay(for: Date())
    @State private var selectedTimelineCategoryID: UUID?
    @State private var clock = TickClock(interval: 60)
    @State private var timelineScheduleInteractionActive = false
    @State private var timelineScrolledOffset: Int? = 0
    @State private var timelineVisibleHour = 0
    @State private var timelinePlanDataByPage: [CalendarTimelinePlanPageKey: [PlanBlock]] = [:]
    @State private var showingTimelineCategoryEditor = false
    @State private var pendingCreatedTimelineCategoryID: UUID?
    @State private var timelineDayPresetRequest: CalendarTimelineDayPresetRequest?
    @State private var timelinePresetInteractionCoordinator = TimelinePlanPresetInteractionCoordinator()
    @State private var timelinePresetDrawerPresented = Self.initialPresetDrawerPresentation()
    @State private var opensCalendarSettingsAfterPresetDrawerDismiss = false

    private let calendar = Calendar.japanese
    private let weekdays = Calendar.japaneseShortWeekdaySymbols
    private let monthPageOffsets = Array(-480...480)
    private let timelinePageOffsets = Array(-60...60)
    private let timelinePresetOverlayCoordinateSpaceName = "calendar-timeline-preset-overlay"

    private static var currentMonthStart: Date {
        let cal = Calendar.japanese
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private static func initialDisplayMode() -> CalendarDisplayMode {
        #if DEBUG
        if let environmentValue = ProcessInfo.processInfo.environment["LiminalogInitialCalendarMode"] {
            switch environmentValue.lowercased() {
            case "day": return .day
            case "week": return .week
            default: break
            }
        }

        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-LiminalogInitialCalendarMode"),
           arguments.indices.contains(arguments.index(after: flagIndex)) {
            switch arguments[arguments.index(after: flagIndex)].lowercased() {
            case "day": return .day
            case "week": return .week
            default: break
            }
        }
        #endif
        return .month
    }

    private static func initialPresetDrawerPresentation() -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-LiminalogDebugOpenPlanPresetDrawer")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarTopBar
                calendarModeContent
            }
            .background(LiminalTheme.canvasGradient)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingMonthPicker) {
                CalendarMonthPickerSheet(
                    selectedYear: $pickerYear,
                    selectedMonth: $pickerMonth,
                    selectedDay: $pickerDay,
                    includesDay: displayMode == .day,
                    yearRange: calendarYearRange,
                    onCancel: {
                        showingMonthPicker = false
                    },
                    onDone: {
                        applyPickedPeriod()
                        showingMonthPicker = false
                    }
                )
            }
            .sheet(isPresented: $showingCalendarSearch, onDismiss: reloadVisibleData) {
                CalendarPlanSearchSheet { plan in
                    jump(to: plan.startTime)
                    showingCalendarSearch = false
                    let target = CalendarDayPresentation(date: plan.startTime, planID: plan.id)
                    DispatchQueue.main.async {
                        selectedDay = target
                    }
                }
            }
            .sheet(isPresented: $showingCalendarSettings) {
                CalendarSettingsSheet()
            }
            .sheet(isPresented: $showingCalendarFilter) {
                CalendarFilterSheet(
                    categories: categories,
                    friends: acceptedFriends,
                    isResetEnabled: isCalendarFilterActive,
                    isCategorySelected: { selectedCategoryIDs.contains($0.id) },
                    onToggleCategory: toggleCategoryFilter(_:),
                    isFriendSelected: { selectedOverlayFriendIDs.contains($0.id) },
                    onToggleFriend: toggleOverlayFriend(_:),
                    onReset: resetCalendarFilter
                )
            }
            .sheet(isPresented: $showingTimelineCategoryEditor) {
                CategoryEditSheet(category: nil) { category in
                    handleCreatedTimelineCategory(category)
                }
            }
            .sheet(item: $timelineDayPresetRequest, onDismiss: reloadTimelinePlanData) { request in
                DayPresetApplySheet(
                    targetDate: request.date,
                    existingPlans: request.existingPlans
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedDay, onDismiss: reloadVisibleData) { target in
                NavigationStack {
                    CalendarDayPagerSheet(initialDate: target.date, highlightedPlanID: target.planID)
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingPlan, onDismiss: reloadVisibleData) { plan in
                PlanCreateSheet(plan: plan)
            }
            .sheet(item: $pendingPlanCreation, onDismiss: reloadVisibleData) { request in
                PlanCreateSheet(
                    initialDate: request.preset.initialDate,
                    startsAsAllDay: request.preset.startsAsAllDay
                )
            }
            .onAppear {
                clock.start()
                pruneCalendarFilterStorage()
                let refreshPlan = CalendarTabCacheRefreshPolicy.plan(
                    hasCachedPageData: !pageDataByMonth.isEmpty,
                    loadedContentRevision: loadedContentRevision,
                    currentContentRevision: store.contentRevision,
                    requiresExternalRefresh: loadedExternalRefreshRevision != externalRefreshRevision
                )
                if refreshPlan == .immediateVisibleRange {
                    reloadVisibleData()
                } else {
                    deferredTabRefreshPlan = refreshPlan
                }
            }
            .task(id: deferredTabRefreshPlan) {
                guard let refreshPlan = deferredTabRefreshPlan else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                let targetExternalRefreshRevision = externalRefreshRevision
                let targetContentRevision = store.contentRevision
                let effectivePlan: CalendarTabCacheRefreshPlan =
                    loadedExternalRefreshRevision == targetExternalRefreshRevision
                    ? refreshPlan
                    : .deferredVisibleRange
                await performDeferredTabRefresh(
                    effectivePlan,
                    targetContentRevision: targetContentRevision
                )
                guard !Task.isCancelled else { return }
                if effectivePlan == .deferredVisibleRange {
                    loadedExternalRefreshRevision = targetExternalRefreshRevision
                }
                deferredTabRefreshPlan = nil
            }
            .onDisappear {
                clock.stop()
                resetTimelineInteractionState()
            }
            .onChange(of: categories.map(\.id)) { _, _ in
                pruneCalendarFilterStorage()
                resolvePendingCreatedTimelineCategory()
                normalizeSelectedTimelineCategory()
            }
            .onChange(of: acceptedFriends.map(\.id)) { _, _ in
                pruneCalendarFilterStorage()
            }
            .onChange(of: usesCustomCategoryFilter) { _, _ in
                normalizeSelectedTimelineCategory()
                reloadVisibleData()
            }
            .onChange(of: storedCategoryFilterIDs) { _, _ in
                normalizeSelectedTimelineCategory()
                reloadVisibleData()
            }
            .onChange(of: storedOverlayFriendIDs) { _, _ in
                reloadVisibleData()
            }
            .onChange(of: displayMode) { oldValue, newValue in
                LiminalHaptics.selection()
                resetTimelineInteractionState()
                if newValue == .month {
                    syncMonthToTimelineAnchor()
                    reloadVisibleData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange)) { notification in
                guard shouldReloadForSharedRecordChange(notification) else { return }
                reloadVisibleData(forSharedRecordChange: notification)
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .NSPersistentStoreRemoteChange)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                externalRefreshRevision &+= 1
            }
        }
    }

    private var calendarTopBar: some View {
        ZStack {
            calendarTitleButton

            HStack {
                calendarLeadingButtons
                Spacer(minLength: 0)
                calendarUtilityButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var calendarLeadingButtons: some View {
        HStack(spacing: 4) {
            calendarSettingsButton
            calendarDisplayModeMenu
        }
    }

    private var calendarSettingsButton: some View {
        Button {
            LiminalHaptics.openSheet()
            if timelinePresetDrawerPresented {
                opensCalendarSettingsAfterPresetDrawerDismiss = true
                timelinePresetDrawerPresented = false
            } else {
                showingCalendarSettings = true
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(calendarSideButtonTint)
        .accessibilityLabel("カレンダー表示設定")
    }

    private var calendarDisplayModeMenu: some View {
        Menu {
            ForEach(CalendarDisplayMode.allCases) { mode in
                Button {
                    LiminalHaptics.selection()
                    setDisplayMode(mode)
                } label: {
                    Label(mode.menuTitle, systemImage: mode.systemImage)
                }
            }
        } label: {
            Image(systemName: displayMode.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .foregroundStyle(calendarSideButtonTint)
        .accessibilityLabel("カレンダー表示を切り替え")
    }

    private func openCalendarSettingsAfterPresetDrawerIfNeeded() {
        guard opensCalendarSettingsAfterPresetDrawerDismiss else { return }
        opensCalendarSettingsAfterPresetDrawerDismiss = false
        DispatchQueue.main.async {
            showingCalendarSettings = true
        }
    }

    private var calendarUtilityButtons: some View {
        HStack(spacing: 4) {
            Button {
                LiminalHaptics.openSheet()
                showingCalendarFilter = true
            } label: {
                Image(systemName: isCalendarFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCalendarFilterActive ? LiminalTheme.accent : calendarSideButtonTint)
            .accessibilityLabel("カレンダー表示フィルタ")

            Button {
                LiminalHaptics.openSheet()
                showingCalendarSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(calendarSideButtonTint)
            .accessibilityLabel("カレンダーを検索")
        }
    }

    private var calendarSideButtonTint: Color {
        LiminalTheme.accent.opacity(0.72)
    }

    private var calendarTitleButton: some View {
        Button {
            LiminalHaptics.openSheet()
            prepareMonthPicker()
            showingMonthPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(calendarTitle)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
            .foregroundStyle(LiminalTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(LiminalTheme.elevated)
            )
            .overlay(
                Capsule()
                    .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("表示期間 \(calendarTitleAccessibilityText)")
    }

    @ViewBuilder
    private var calendarModeContent: some View {
        switch displayMode {
        case .month:
            monthPager
        case .week:
            timelineModeContent {
                timelinePager { offset, isInteractionEnabled in
                    CalendarWeekTimelineView(
                        anchorDate: timelineDate(offset: offset),
                        categories: timelineSelectableCategories,
                        planPresets: planPresets,
                        visibleCategoryIDs: usesCustomCategoryFilter ? selectedCategoryIDs : nil,
                        plans: cachedTimelinePlans(for: offset),
                        planTitleFontSize: normalizedTimelinePlanTitleFontSize,
                        planTitleBold: planTitleBold,
                        isInteractionEnabled: isInteractionEnabled,
                        isPageSwipeActive: !isInteractionEnabled,
                        presetInteractionCoordinator: timelinePresetInteractionCoordinator,
                        presetExternalCoordinateSpaceName: nil,
                        presetDrawerPresentation: $timelinePresetDrawerPresented,
                        onPresetDrawerDismiss: openCalendarSettingsAfterPresetDrawerIfNeeded,
                        visibleHour: $timelineVisibleHour,
                        selectedCategoryID: $selectedTimelineCategoryID,
                        isScheduleInteractionActive: $timelineScheduleInteractionActive,
                        onOpenPlan: { plan in
                            LiminalHaptics.openSheet()
                            editingPlan = plan
                        },
                        onOpenDay: { date in
                            LiminalHaptics.openSheet()
                            selectedDay = CalendarDayPresentation(date: date, planID: nil)
                        },
                        onScheduleChanged: {
                            reloadTimelinePlanData()
                        }
                    )
                }
            }
        case .day:
            timelineModeContent {
                timelinePager { offset, isInteractionEnabled in
                    CalendarDayTimelineContainer(
                        date: timelineDate(offset: offset),
                        categories: timelineSelectableCategories,
                        planPresets: planPresets,
                        visibleCategoryIDs: usesCustomCategoryFilter ? selectedCategoryIDs : nil,
                        plans: cachedTimelinePlans(for: offset),
                        planTitleFontSize: normalizedTimelinePlanTitleFontSize,
                        planTitleBold: planTitleBold,
                        isInteractionEnabled: isInteractionEnabled,
                        isPageSwipeActive: !isInteractionEnabled,
                        presetInteractionCoordinator: timelinePresetInteractionCoordinator,
                        presetExternalCoordinateSpaceName: nil,
                        visibleHour: $timelineVisibleHour,
                        selectedCategoryID: $selectedTimelineCategoryID,
                        isScheduleInteractionActive: $timelineScheduleInteractionActive,
                        onOpenDay: { date in
                            LiminalHaptics.openSheet()
                            selectedDay = CalendarDayPresentation(date: date, planID: nil)
                        },
                        onEditPlan: { plan in
                            LiminalHaptics.openSheet()
                            editingPlan = plan
                        },
                        onScheduleChanged: {
                            reloadTimelinePlanData()
                        }
                    )
                }
            }
        }
    }

    private func timelineModeContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                timelineCategoryPalette
                content()
            }

            if displayMode != .week, !planPresets.isEmpty {
                TimelinePlanPresetLibrary(
                    presets: planPresets,
                    categories: timelineSelectableCategories,
                    onFixedTimeTap: timelinePresetInteractionCoordinator.addFixedTimePreset,
                    onDurationDragChanged: timelinePresetInteractionCoordinator.updateDurationPreset,
                    onDurationDrop: timelinePresetInteractionCoordinator.finishDurationPreset,
                    onDraggingChanged: timelinePresetInteractionCoordinator.setDragging,
                    launcherPlacement: .externalControl,
                    isPresented: $timelinePresetDrawerPresented,
                    onDismiss: openCalendarSettingsAfterPresetDrawerIfNeeded
                )
                .zIndex(100)
            }
        }
        .coordinateSpace(name: timelinePresetOverlayCoordinateSpaceName)
        .onAppear {
            normalizeSelectedTimelineCategory()
        }
    }

    private var normalizedTimelinePlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
    }

    private var timelineCategoryPalette: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if displayMode != .month, !planPresets.isEmpty {
                    Button {
                        LiminalHaptics.openSheet()
                        timelinePresetDrawerPresented = true
                    } label: {
                        TimelineCategoryStatusChip(
                            title: "予定プリセット",
                            systemImage: "bookmark.fill",
                            accessibilityLabel: "予定プリセットを開く"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if displayMode == .day {
                    Button {
                        LiminalHaptics.openSheet()
                        timelineDayPresetRequest = CalendarTimelineDayPresetRequest(
                            date: visibleTimelineDate,
                            existingPlans: cachedTimelinePlans(for: currentTimelineOffset)
                        )
                    } label: {
                        TimelineCategoryStatusChip(
                            title: "一日プリセット",
                            systemImage: "calendar.badge.clock",
                            accessibilityLabel: "一日プリセットを適用"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if timelineSelectableCategories.isEmpty {
                    Button {
                        LiminalHaptics.openSheet()
                        showingCalendarFilter = true
                    } label: {
                        TimelineCategoryStatusChip(
                            title: usesCustomCategoryFilter ? "表示カテゴリなし" : "カテゴリなし",
                            systemImage: usesCustomCategoryFilter ? "line.3.horizontal.decrease.circle.fill" : "square.grid.2x2",
                            accessibilityLabel: usesCustomCategoryFilter ? "表示カテゴリなし。フィルタを開く" : "カテゴリなし"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(timelineSelectableCategories) { category in
                        Button {
                            LiminalHaptics.selection()
                            selectedTimelineCategoryID = category.id
                        } label: {
                            TimelineCategoryChip(
                                category: category,
                                isSelected: category.id == selectedTimelineCategoryID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    LiminalHaptics.openSheet()
                    showingTimelineCategoryEditor = true
                } label: {
                    TimelineCreateCategoryChip()
                }
                .buttonStyle(.plain)

            }
            .padding(.vertical, 2)
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 6)
    }

    private func timelinePager<Page: View>(@ViewBuilder page: @escaping (Int, Bool) -> Page) -> some View {
        let activeOffset = timelineScrolledOffset ?? 0
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(timelinePageOffsets, id: \.self) { offset in
                    page(offset, offset == activeOffset)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(offset != activeOffset)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $timelineScrolledOffset, anchor: .center)
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
        .scrollDisabled(timelineScheduleInteractionActive)
        .frame(maxHeight: .infinity)
        .onAppear {
            ensureTimelinePlanPagesAroundCurrentOffset()
        }
        .onChange(of: timelineScrolledOffset) { _, newValue in
            handleTimelineScroll(to: newValue)
        }
    }

    private var monthPager: some View {
        let pageData = cachedPageData(for: visibleMonth)
        let pageHeight = CalendarMonthPage.height(forWeekCount: pageData.dates.count / 7)
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(monthPageOffsets, id: \.self) { offset in
                    CalendarMonthPage(
                        weekdays: weekdays,
                        weekdayColor: weekdayColor(_:),
                        pageData: cachedPageData(for: month(forOffset: offset)),
                        onOpenDay: { date, planID in
                            LiminalHaptics.openSheet()
                            selectedDay = CalendarDayPresentation(date: date, planID: planID)
                        },
                        onCreatePlan: { date in
                            preparePlanCreation(for: date)
                        }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $monthScrolledOffset, anchor: .center)
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
        .onAppear {
            ensureData(around: currentMonthOffset)
        }
        .onChange(of: monthScrolledOffset) { _, newValue in
            handleMonthScroll(to: newValue)
        }
        .contentShape(Rectangle())
        .frame(height: pageHeight)
        .background(LiminalTheme.divider.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.5), lineWidth: 1)
        )
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func preparePlanCreation(for date: Date) {
        guard let preset = CalendarPlanCreationPreset.make(
            for: date,
            canCreateTimedPlan: store.canCreatePlan(startTime: date, isAllDay: false)
        ) else { return }
        pendingPlanCreation = CalendarPlanCreationRequest(preset: preset)
    }

    private var calendarYearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 10)...(currentYear + 10)
    }

    private var calendarTitle: String {
        switch displayMode {
        case .month:
            visibleMonth.japaneseYearMonth
        case .week:
            visibleTimelineDate.japaneseYearMonth
        case .day:
            visibleTimelineDate.japaneseMonthDayShortWeekday
        }
    }

    private var calendarTitleAccessibilityText: String {
        switch displayMode {
        case .month, .day:
            calendarTitle
        case .week:
            "\(timelineWeekStart.japaneseMonthDayShortWeekday)から\(timelineWeekEndInclusive.japaneseMonthDayShortWeekday)"
        }
    }

    private var timelineWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: visibleTimelineDate)?.start
            ?? calendar.startOfDay(for: visibleTimelineDate)
    }

    private var timelineWeekEndInclusive: Date {
        let exclusiveEnd = calendar.date(byAdding: .day, value: 7, to: timelineWeekStart) ?? timelineWeekStart
        return calendar.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? timelineWeekStart
    }

    private var preferredTimelineAnchorDate: Date {
        if calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month) {
            return calendar.startOfDay(for: Date())
        }
        return visibleMonth
    }

    private func timelineDate(offset: Int) -> Date {
        let component: Calendar.Component = displayMode == .week ? .weekOfYear : .day
        return calendar.startOfDay(for: calendar.date(byAdding: component, value: offset, to: timelineAnchorDate) ?? timelineAnchorDate)
    }

    private var visibleTimelineDate: Date {
        timelineDate(offset: currentTimelineOffset)
    }

    private var currentTimelineOffset: Int {
        timelineScrolledOffset ?? 0
    }

    private var currentMonthOffset: Int {
        monthScrolledOffset ?? offset(forMonth: visibleMonth)
    }

    private func timelineInterval(forOffset offset: Int) -> DateInterval {
        switch displayMode {
        case .month:
            let start = monthStart(for: visibleMonth)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            return CalendarWeekTimelineView.weekInterval(containing: timelineDate(offset: offset))
        case .day:
            let start = calendar.startOfDay(for: timelineDate(offset: offset))
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private func timelinePlanPageKey(forOffset offset: Int) -> CalendarTimelinePlanPageKey {
        let interval = timelineInterval(forOffset: offset)
        return CalendarTimelinePlanPageKey(mode: displayMode, start: interval.start)
    }

    private func ensureTimelinePlanPagesAroundCurrentOffset() {
        ensureTimelinePlanPages(around: currentTimelineOffset)
    }

    private func ensureTimelinePlanPages(around offset: Int) {
        guard displayMode != .month else { return }
        let offsets = Array((offset - 1)...(offset + 1))
        let missingOffsets = offsets.filter { offset in
            timelinePlanDataByPage[timelinePlanPageKey(forOffset: offset)] == nil
        }
        guard !missingOffsets.isEmpty else { return }

        let intervalsByOffset = Dictionary(
            uniqueKeysWithValues: offsets.map { ($0, timelineInterval(forOffset: $0)) }
        )
        guard let fetchStart = intervalsByOffset.values.map(\.start).min(),
              let fetchEnd = intervalsByOffset.values.map(\.end).max()
        else { return }

        let fetchedPlans = TabPerformanceDiagnostics.measure("Calendar timeline fetch") {
            fetchTimelinePlans(for: DateInterval(start: fetchStart, end: fetchEnd))
        }
        TabPerformanceDiagnostics.measure("Calendar timeline page cache") {
            performWithoutAnimation {
                for offset in missingOffsets {
                    guard let interval = intervalsByOffset[offset] else { continue }
                    timelinePlanDataByPage[timelinePlanPageKey(forOffset: offset)] = fetchedPlans.filter {
                        $0.startTime < interval.end && $0.endTime > interval.start
                    }
                }
            }
        }
    }

    private func pruneTimelinePlanData(around offset: Int) {
        guard displayMode != .month else { return }
        let retainedKeys = Set((-1...1).map { timelinePlanPageKey(forOffset: offset + $0) })
        performWithoutAnimation {
            timelinePlanDataByPage = timelinePlanDataByPage.filter { key, _ in
                key.mode != displayMode || retainedKeys.contains(key)
            }
        }
    }

    private func cachedTimelinePlans(for offset: Int) -> [PlanBlock] {
        guard displayMode != .month else { return [] }
        let key = timelinePlanPageKey(forOffset: offset)
        if let cached = timelinePlanDataByPage[key] {
            return cached
        }
        return []
    }

    private func reloadTimelinePlanData() {
        performWithoutAnimation {
            timelinePlanDataByPage.removeAll()
        }
        ensureTimelinePlanPagesAroundCurrentOffset()
    }

    private func fetchTimelinePlans(for interval: DateInterval) -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate {
                $0.startTime < interval.end && $0.endTime > interval.start
            },
            sortBy: [SortDescriptor(\.startTime), SortDescriptor(\.createdAt)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch timeline plans: \(String(describing: error))")
            return []
        }
    }

    private func resetTimelineInteractionState() {
        timelineScheduleInteractionActive = false
    }

    private func handleTimelineScroll(to newValue: Int?) {
        guard displayMode != .month, let newValue else { return }
        ensureTimelinePlanPages(around: newValue)
        pruneTimelinePlanData(around: newValue)
        LiminalHaptics.selection()
    }

    private func syncMonthToTimelineAnchor() {
        let targetDate = visibleTimelineDate
        let targetMonth = monthStart(for: targetDate)
        performWithoutAnimation {
            timelineAnchorDate = targetDate
            timelineScrolledOffset = 0
        }
        scrollMonth(to: targetMonth)
    }

    private func setDisplayMode(_ mode: CalendarDisplayMode) {
        guard displayMode != mode else { return }
        let targetTimelineDate = displayMode == .month ? preferredTimelineAnchorDate : visibleTimelineDate
        if displayMode == .month, mode != .month {
            timelineAnchorDate = targetTimelineDate
            timelineScrolledOffset = 0
        } else if displayMode != .month, mode == .month {
            timelineAnchorDate = targetTimelineDate
        } else if displayMode != .month, mode != .month {
            timelineAnchorDate = targetTimelineDate
            timelineScrolledOffset = 0
        }
        performWithoutAnimation {
            displayMode = mode
        }
        if mode != .month {
            ensureTimelinePlanPagesAroundCurrentOffset()
            pruneTimelinePlanData(around: currentTimelineOffset)
        }
    }

    private var allCategoryIDs: Set<UUID> {
        Set(categories.map(\.id))
    }

    private var selectedCategoryIDs: Set<UUID> {
        guard usesCustomCategoryFilter else { return allCategoryIDs }
        return decodedUUIDSet(storedCategoryFilterIDs).intersection(allCategoryIDs)
    }

    private var timelineSelectableCategories: [Category] {
        guard usesCustomCategoryFilter else { return categories }
        let visibleIDs = selectedCategoryIDs
        return categories.filter { visibleIDs.contains($0.id) }
    }

    private func normalizeSelectedTimelineCategory() {
        let categoryIDs = Set(timelineSelectableCategories.map(\.id))
        if let selectedTimelineCategoryID, categoryIDs.contains(selectedTimelineCategoryID) {
            return
        }
        selectedTimelineCategoryID = timelineSelectableCategories.first?.id
    }

    private func handleCreatedTimelineCategory(_ category: Category) {
        pendingCreatedTimelineCategoryID = category.id
        if usesCustomCategoryFilter {
            let updatedIDs = decodedUUIDSet(storedCategoryFilterIDs).union([category.id])
            storedCategoryFilterIDs = encodedUUIDSet(updatedIDs)
        }
        resolvePendingCreatedTimelineCategory()
    }

    private func resolvePendingCreatedTimelineCategory() {
        guard let pendingCreatedTimelineCategoryID else { return }
        guard let selection = TimelineCreatedCategorySelection.resolve(
            createdCategoryID: pendingCreatedTimelineCategoryID,
            availableCategoryIDs: allCategoryIDs,
            usesCustomFilter: usesCustomCategoryFilter,
            storedFilterIDs: decodedUUIDSet(storedCategoryFilterIDs)
        ) else { return }

        if let customFilterIDs = selection.customFilterIDs {
            storedCategoryFilterIDs = encodedUUIDSet(customFilterIDs)
        }
        selectedTimelineCategoryID = selection.selectedCategoryID
        self.pendingCreatedTimelineCategoryID = nil
    }

    private var acceptedFriends: [Friend] {
        friends
            .filter { $0.status == .accepted }
            .sorted {
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var selectedOverlayFriendIDs: Set<UUID> {
        decodedUUIDSet(storedOverlayFriendIDs).intersection(Set(acceptedFriends.map(\.id)))
    }

    private var selectedOverlayFriends: [Friend] {
        let selectedIDs = selectedOverlayFriendIDs
        return acceptedFriends.filter { selectedIDs.contains($0.id) }
    }

    private var isCalendarFilterActive: Bool {
        usesCustomCategoryFilter || !selectedOverlayFriendIDs.isEmpty
    }

    private func prepareMonthPicker() {
        let sourceDate = displayMode == .month ? visibleMonth : visibleTimelineDate
        pickerYear = calendar.component(.year, from: sourceDate)
        pickerMonth = calendar.component(.month, from: sourceDate)
        pickerDay = calendar.component(.day, from: sourceDate)
    }

    private func applyPickedPeriod() {
        let day = displayMode == .day ? min(pickerDay, daysInPickerMonth) : 1
        let components = DateComponents(year: pickerYear, month: pickerMonth, day: day)
        jump(to: calendar.date(from: components) ?? visibleMonth)
    }

    private var daysInPickerMonth: Int {
        let components = DateComponents(year: pickerYear, month: pickerMonth, day: 1)
        guard let month = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: month)
        else { return 31 }
        return range.count
    }

    private func monthGridDates(for month: Date) -> [Date] {
        let monthStart = monthStart(for: month)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let dayCount = calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = (weekdayOffset + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        let weekCount = max(5, min(6, Int(ceil(Double(normalizedOffset + dayCount) / 7.0))))
        return (0..<(weekCount * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func toggleCategoryFilter(_ category: Category) {
        var selectedIDs = selectedCategoryIDs
        if selectedIDs.contains(category.id) {
            selectedIDs.remove(category.id)
        } else {
            selectedIDs.insert(category.id)
        }

        if selectedIDs == allCategoryIDs {
            usesCustomCategoryFilter = false
            storedCategoryFilterIDs = ""
        } else {
            usesCustomCategoryFilter = true
            storedCategoryFilterIDs = encodedUUIDSet(selectedIDs)
        }
        reloadVisibleData()
    }

    private func toggleOverlayFriend(_ friend: Friend) {
        var selectedIDs = selectedOverlayFriendIDs
        if selectedIDs.contains(friend.id) {
            selectedIDs.remove(friend.id)
        } else {
            selectedIDs.insert(friend.id)
        }
        storedOverlayFriendIDs = encodedUUIDSet(selectedIDs)
        reloadVisibleData()
    }

    private func resetCalendarFilter() {
        usesCustomCategoryFilter = false
        storedCategoryFilterIDs = ""
        storedOverlayFriendIDs = ""
        reloadVisibleData()
    }

    private func pruneCalendarFilterStorage() {
        let validCategoryIDs = allCategoryIDs
        let storedCategoryIDs = decodedUUIDSet(storedCategoryFilterIDs)
        let prunedCategoryIDs = storedCategoryIDs.intersection(validCategoryIDs)
        if usesCustomCategoryFilter {
            if !storedCategoryIDs.isEmpty && prunedCategoryIDs.isEmpty && !validCategoryIDs.isEmpty {
                usesCustomCategoryFilter = false
                storedCategoryFilterIDs = ""
            } else if prunedCategoryIDs == validCategoryIDs {
                usesCustomCategoryFilter = false
                storedCategoryFilterIDs = ""
            } else if prunedCategoryIDs != storedCategoryIDs {
                storedCategoryFilterIDs = encodedUUIDSet(prunedCategoryIDs)
            }
        } else if !storedCategoryIDs.isEmpty {
            storedCategoryFilterIDs = ""
        }

        let validFriendIDs = Set(acceptedFriends.map(\.id))
        let storedFriendIDs = decodedUUIDSet(storedOverlayFriendIDs)
        let prunedFriendIDs = storedFriendIDs.intersection(validFriendIDs)
        if prunedFriendIDs != storedFriendIDs {
            storedOverlayFriendIDs = encodedUUIDSet(prunedFriendIDs)
        }
    }

    private func decodedUUIDSet(_ rawValue: String) -> Set<UUID> {
        Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func encodedUUIDSet(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func performWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    // MARK: - ページング / データ取得（遅延・月単位キャッシュ）

    private func month(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
    }

    private func offset(forMonth month: Date) -> Int {
        calendar.dateComponents([.month], from: anchorMonth, to: monthStart(for: month)).month ?? 0
    }

    private func handleMonthScroll(to newValue: Int?) {
        guard let newValue else { return }
        let month = monthStart(for: month(forOffset: newValue))
        if visibleMonth != month {
            visibleMonth = month
            LiminalHaptics.selection()
        }
        ensureData(around: newValue)
    }

    private func scrollMonth(to month: Date) {
        let targetMonth = monthStart(for: month)
        let targetOffset = offset(forMonth: targetMonth)
        if monthPageOffsets.contains(targetOffset) {
            performWithoutAnimation {
                visibleMonth = targetMonth
                monthScrolledOffset = targetOffset
            }
            ensureData(around: targetOffset)
            return
        }

        performWithoutAnimation {
            anchorMonth = targetMonth
            visibleMonth = targetMonth
            monthScrolledOffset = 0
        }
        ensureData(around: 0)
    }

    /// 月ピッカー・検索からの任意月ジャンプ。
    private func jump(to date: Date) {
        let targetMonth = monthStart(for: date)
        resetTimelineInteractionState()
        performWithoutAnimation {
            timelineAnchorDate = calendar.startOfDay(for: date)
            timelineScrolledOffset = 0
        }
        scrollMonth(to: targetMonth)
        if displayMode != .month {
            reloadTimelinePlanData()
        }
    }

    /// データ変更後（日編集シートを閉じた等）にキャッシュを破棄して現在月周辺を作り直す。
    private func reloadVisibleData() {
        TabPerformanceDiagnostics.measure("Calendar reload visible data") {
            let monthOffset = currentMonthOffset
            performWithoutAnimation {
                pageDataByMonth.removeAll()
                timelinePlanDataByPage.removeAll()
            }
            ensureData(around: monthOffset)
            if displayMode != .month {
                ensureTimelinePlanPagesAroundCurrentOffset()
            }
            loadedContentRevision = store.contentRevision
            loadedExternalRefreshRevision = externalRefreshRevision
        }
    }

    /// キャッシュ済み画面を先に表示してから、時刻依存スコアと変更データを更新する。
    /// 表示範囲全体の更新も1ヶ月ずつyieldし、タブ選択フレームを同期計算で塞がない。
    @MainActor
    private func performDeferredTabRefresh(
        _ plan: CalendarTabCacheRefreshPlan,
        targetContentRevision: Int
    ) async {
        let visibleOffset = currentMonthOffset
        let offsets: [Int]
        switch plan {
        case .immediateVisibleRange:
            return
        case .deferredCurrentMonth:
            offsets = [visibleOffset]
        case .deferredVisibleRange:
            offsets = [visibleOffset, visibleOffset - 1, visibleOffset + 1]
        }

        for (index, offset) in offsets.enumerated() {
            guard !Task.isCancelled else { return }
            let visibleMonth = month(forOffset: offset)
            let key = monthStart(for: visibleMonth)
            let pageData = TabPerformanceDiagnostics.measure("Calendar refresh one month") {
                computePageData(for: visibleMonth, now: clock.now)
            }
            performWithoutAnimation {
                pageDataByMonth[key] = pageData
            }
            if index < offsets.count - 1 {
                await Task.yield()
            }
        }

        pruneMonthPageData(around: visibleOffset)
        performWithoutAnimation {
            timelinePlanDataByPage.removeAll()
        }
        if displayMode != .month {
            ensureTimelinePlanPagesAroundCurrentOffset()
        }
        loadedContentRevision = targetContentRevision
    }

    private func reloadVisibleData(forSharedRecordChange notification: Notification) {
        let change = SharedRecordChangeNotification(notification)
        let currentOffset = currentMonthOffset
        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: change,
            anchorMonth: anchorMonth,
            currentOffset: currentOffset,
            calendar: calendar
        )
        if plan.shouldClearAll {
            reloadVisibleData()
            return
        }
        for month in plan.monthsToRemove {
            performWithoutAnimation {
                pageDataByMonth.removeValue(forKey: month)
            }
        }
        if plan.shouldEnsureVisibleData {
            ensureData(around: currentOffset)
        }
    }

    private func shouldReloadForSharedRecordChange(_ notification: Notification) -> Bool {
        guard !selectedOverlayFriendIDs.isEmpty else { return false }
        let change = SharedRecordChangeNotification(notification)
        guard let friendID = change.friendID else { return true }
        return selectedOverlayFriendIDs.contains(friendID)
    }

    /// 表示月と前後1ヶ月だけを用意し、body内のキャッシュミスでは重い計算をしない。
    private func ensureData(around offset: Int) {
        for pageOffset in (offset - 1)...(offset + 1) {
            ensurePageData(forOffset: pageOffset)
        }
        pruneMonthPageData(around: offset)
    }

    private func ensurePageData(forOffset offset: Int) {
        let now = clock.now
        let month = month(forOffset: offset)
        let key = monthStart(for: month)
        if pageDataByMonth[key] == nil {
            performWithoutAnimation {
                pageDataByMonth[key] = computePageData(for: month, now: now)
            }
        }
    }

    private func pruneMonthPageData(around offset: Int) {
        let retainedMonths = Set(((offset - 1)...(offset + 1)).map { pageOffset in
            monthStart(for: month(forOffset: pageOffset))
        })
        performWithoutAnimation {
            pageDataByMonth = pageDataByMonth.filter { retainedMonths.contains($0.key) }
        }
    }

    /// 描画時は同期計算しない。重い月データ作成は `ensureData` / `reloadVisibleData` に寄せる。
    private func cachedPageData(for month: Date) -> CalendarMonthPageData {
        let key = monthStart(for: month)
        if let cached = pageDataByMonth[key] {
            return cached
        }
        return emptyPageData(for: month)
    }

    private func emptyPageData(for month: Date) -> CalendarMonthPageData {
        CalendarMonthPageData(
            dates: monthGridDates(for: month),
            visibleMonth: monthStart(for: month),
            importantPlansByDay: [:],
            scoreSummariesByDay: [:],
            didFailToLoadRecords: false
        )
    }

    /// 1ヶ月分のグリッドデータを、その月のグリッド範囲だけ自前で fetch して計算する。
    private func computePageData(for month: Date, now: Date) -> CalendarMonthPageData {
        let dates = monthGridDates(for: month)
        guard let gridStart = dates.first.map({ calendar.startOfDay(for: $0) }),
              let lastDate = dates.last,
              let gridEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return CalendarMonthPageData(
                dates: dates,
                visibleMonth: month,
                importantPlansByDay: [:],
                scoreSummariesByDay: [:],
                didFailToLoadRecords: false
            )
        }

        let planDescriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < gridEnd && $0.endTime > gridStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var didFailToLoadRecords = false
        let plansInGrid: [PlanBlock]
        do {
            plansInGrid = try modelContext.fetch(planDescriptor).sorted(by: planSort)
        } catch {
            NSLog("Liminalog: failed to fetch calendar plans: \(String(describing: error))")
            didFailToLoadRecords = true
            plansInGrid = []
        }
        let categoryFilterIsActive = usesCustomCategoryFilter
        let visibleCategoryIDs = selectedCategoryIDs
        let visiblePlansInGrid = categoryFilterIsActive
            ? plansInGrid.filter { plan in
                guard let categoryID = plan.category?.id else { return false }
                return visibleCategoryIDs.contains(categoryID)
            }
            : plansInGrid
        let deduplicatedVisiblePlansInGrid = deduplicatedCalendarPlans(visiblePlansInGrid)

        let lookbackStart = calendar.date(byAdding: .day, value: -14, to: gridStart) ?? gridStart
        let chapterDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= lookbackStart && $0.startTime < gridEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let activeDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var chapters: [Chapter]
        do {
            chapters = try modelContext.fetch(chapterDescriptor)
                .filter { ($0.endTime ?? now) > gridStart }
        } catch {
            NSLog("Liminalog: failed to fetch calendar chapters: \(String(describing: error))")
            didFailToLoadRecords = true
            chapters = []
        }
        let activeChapters: [Chapter]
        do {
            activeChapters = try modelContext.fetch(activeDescriptor)
                .filter { $0.startTime < gridEnd && ($0.endTime ?? now) > gridStart }
        } catch {
            NSLog("Liminalog: failed to fetch active calendar chapters: \(String(describing: error))")
            didFailToLoadRecords = true
            activeChapters = []
        }
        let existingIDs = Set(chapters.map(\.id))
        chapters.append(contentsOf: activeChapters.filter { !existingIDs.contains($0.id) })
        let chaptersInGrid = chapters
            .filter { chapter in
                guard categoryFilterIsActive else { return true }
                guard let categoryID = chapter.category?.id else { return false }
                return visibleCategoryIDs.contains(categoryID)
            }
            .sorted { $0.startTime < $1.startTime }

        // docs/20: 友達の予定はグリッド範囲だけを個別行キャッシュから引く。
        let friendRecordStore = FriendSharedRecordStore(modelContext: modelContext)
        let friendPlansInGrid = selectedOverlayFriends.map { friend in
            CalendarFriendPlanSource(
                friend: friend,
                plans: friendRecordStore.plans(friendID: friend.id, overlapping: gridStart..<gridEnd)
            )
        }

        var plansByDay = Dictionary(uniqueKeysWithValues: dates.map { (calendar.startOfDay(for: $0), [PlanBlock]()) })
        for plan in deduplicatedVisiblePlansInGrid {
            for dayStart in dayStartsOverlapping(start: plan.startTime, end: plan.endTime, gridStart: gridStart, gridEnd: gridEnd) {
                plansByDay[dayStart, default: []].append(plan)
            }
        }

        var chaptersByDay = Dictionary(uniqueKeysWithValues: dates.map { (calendar.startOfDay(for: $0), [Chapter]()) })
        for chapter in chaptersInGrid {
            for dayStart in dayStartsOverlapping(start: chapter.startTime, end: chapter.endTime ?? now, gridStart: gridStart, gridEnd: gridEnd) {
                chaptersByDay[dayStart, default: []].append(chapter)
            }
        }

        var friendImportantPlansByDay = Dictionary(uniqueKeysWithValues: dates.map { (calendar.startOfDay(for: $0), [CalendarDisplayPlan]()) })
        for source in friendPlansInGrid {
            for plan in source.plans where plan.showsInCalendarAsImportant {
                for dayStart in dayStartsOverlapping(start: plan.startTime, end: plan.endTime, gridStart: gridStart, gridEnd: gridEnd) {
                    friendImportantPlansByDay[dayStart, default: []].append(
                        CalendarDisplayPlan(friendPlan: plan, friendName: source.friend.displayName)
                    )
                }
            }
        }

        var importantPlansByDay: [Date: [CalendarDisplayPlan]] = [:]
        var scoreSummariesByDay: [Date: CalendarDisplayScore] = [:]

        for date in dates {
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plansByDay[boundary.dayStart] ?? []
            let dayChapters = chaptersByDay[boundary.dayStart] ?? []
            let importantPlans = dayPlans
                .filter(\.showsInCalendarAsImportant)
                .sorted(by: planSort)
                .map { CalendarDisplayPlan(plan: $0) }
            let friendImportantPlans = friendImportantPlansByDay[boundary.dayStart] ?? []
            let displayPlans = (importantPlans + friendImportantPlans).sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }

            // データのない日はスコアバッジも重要予定も出ないため、計算自体を省く。
            guard !displayPlans.isEmpty || !dayPlans.isEmpty || !dayChapters.isEmpty else { continue }
            if !displayPlans.isEmpty {
                importantPlansByDay[boundary.dayStart] = displayPlans
            }
            scoreSummariesByDay[boundary.dayStart] = CalendarDisplayScore(
                summary: CalendarDayScoreCache.summary(
                    date: date,
                    dayStart: boundary.dayStart,
                    plans: dayPlans,
                    chapters: dayChapters,
                    calendar: calendar,
                    now: now
                )
            )
        }

        return CalendarMonthPageData(
            dates: dates,
            visibleMonth: month,
            importantPlansByDay: importantPlansByDay,
            scoreSummariesByDay: scoreSummariesByDay,
            didFailToLoadRecords: didFailToLoadRecords
        )
    }

    private func dayStartsOverlapping(start: Date, end: Date, gridStart: Date, gridEnd: Date) -> [Date] {
        let clippedStart = max(start, gridStart)
        let clippedEnd = min(end, gridEnd)
        guard clippedStart < clippedEnd else { return [] }

        var result: [Date] = []
        var dayStart = calendar.startOfDay(for: clippedStart)
        while dayStart < clippedEnd {
            result.append(dayStart)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = nextDay
        }
        return result
    }

    private func planSort(_ lhs: PlanBlock, _ rhs: PlanBlock) -> Bool {
        if lhs.startTime == rhs.startTime {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.startTime < rhs.startTime
    }

    private func deduplicatedCalendarPlans(_ plans: [PlanBlock]) -> [PlanBlock] {
        var seenKeys: Set<CalendarPlanDuplicateKey> = []
        return plans.filter { plan in
            seenKeys.insert(calendarDuplicateKey(for: plan)).inserted
        }
    }

    private func calendarDuplicateKey(for plan: PlanBlock) -> CalendarPlanDuplicateKey {
        if let sourceEventID = plan.sourceEventID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceEventID.isEmpty {
            return .source(sourceEventID)
        }
        let categoryKey = plan.category.map {
            CalendarPlanDuplicateCategoryKey(
                isDefault: $0.isDefault,
                normalizedName: normalizedCalendarText($0.name)
            )
        }
        return .manual(
            category: categoryKey,
            normalizedTitle: normalizedCalendarText(plan.title),
            startMinute: calendarMinuteKey(plan.startTime),
            endMinute: calendarMinuteKey(plan.endTime),
            isAllDay: plan.isAllDay,
            normalizedNote: plan.note.map(normalizedCalendarText) ?? ""
        )
    }

    private func normalizedCalendarText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }

    private func calendarMinuteKey(_ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded())
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func weekdayColor(_ weekday: String) -> Color {
        switch weekday {
        case "日": .red
        case "土": .blue
        default: .secondary
        }
    }
}

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .day:
            "日"
        case .week:
            "週"
        case .month:
            "月"
        }
    }

    var menuTitle: String {
        switch self {
        case .day:
            "日間"
        case .week:
            "週間"
        case .month:
            "月間"
        }
    }

    var systemImage: String {
        switch self {
        case .day:
            "calendar.day.timeline.left"
        case .week:
            "calendar.badge.clock"
        case .month:
            "calendar"
        }
    }
}

private struct CalendarTimelinePlanPageKey: Hashable {
    let mode: CalendarDisplayMode
    let start: Date
}

private struct CalendarTimelineDayPresetRequest: Identifiable {
    let id = UUID()
    let date: Date
    let existingPlans: [PlanBlock]
}

enum CalendarTimelineCardMetrics {
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 8
}

struct CalendarDayTimelineContainer: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let categories: [Category]
    let planPresets: [PlanPreset]
    let visibleCategoryIDs: Set<UUID>?
    let plans: [PlanBlock]
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let isInteractionEnabled: Bool
    let isPageSwipeActive: Bool
    let presetInteractionCoordinator: TimelinePlanPresetInteractionCoordinator?
    let presetExternalCoordinateSpaceName: String?
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onOpenDay: ((Date) -> Void)?
    let onEditPlan: (PlanBlock) -> Void
    let onScheduleChanged: () -> Void
    init(
        date: Date,
        categories: [Category],
        planPresets: [PlanPreset],
        visibleCategoryIDs: Set<UUID>?,
        plans: [PlanBlock],
        planTitleFontSize: Double,
        planTitleBold: Bool,
        isInteractionEnabled: Bool,
        isPageSwipeActive: Bool,
        presetInteractionCoordinator: TimelinePlanPresetInteractionCoordinator? = nil,
        presetExternalCoordinateSpaceName: String? = nil,
        visibleHour: Binding<Int>,
        selectedCategoryID: Binding<UUID?>,
        isScheduleInteractionActive: Binding<Bool>,
        onOpenDay: ((Date) -> Void)? = nil,
        onEditPlan: @escaping (PlanBlock) -> Void,
        onScheduleChanged: @escaping () -> Void
    ) {
        let dayStart = DayBoundary.dayStart(for: date, calendar: .japanese)
        self.date = dayStart
        self.categories = categories
        self.planPresets = planPresets
        self.visibleCategoryIDs = visibleCategoryIDs
        self.plans = plans
        self.planTitleFontSize = planTitleFontSize
        self.planTitleBold = planTitleBold
        self.isInteractionEnabled = isInteractionEnabled
        self.isPageSwipeActive = isPageSwipeActive
        self.presetInteractionCoordinator = presetInteractionCoordinator
        self.presetExternalCoordinateSpaceName = presetExternalCoordinateSpaceName
        self._visibleHour = visibleHour
        self._selectedCategoryID = selectedCategoryID
        self._isScheduleInteractionActive = isScheduleInteractionActive
        self.onOpenDay = onOpenDay
        self.onEditPlan = onEditPlan
        self.onScheduleChanged = onScheduleChanged
    }

    var body: some View {
        GeometryReader { proxy in
            let timelineWidth = max(1, proxy.size.width - CalendarTimelineCardMetrics.horizontalPadding * 2)
            let cardHeight = max(
                1,
                proxy.size.height
                    - CalendarTimelineCardMetrics.topPadding
                    - CalendarTimelineCardMetrics.bottomPadding
            )
            let allDayHeaderHeight = CalendarDayTimelineAllDayHeader.height(
                forPlanCount: allDayPlans.count,
                planTitleFontSize: planTitleFontSize
            )
            VStack(spacing: 0) {
                CalendarDayTimelineAllDayHeader(
                    date: date,
                    plans: allDayPlans,
                    planTitleFontSize: planTitleFontSize,
                    onOpenDay: onOpenDay,
                    onOpenPlan: onEditPlan
                )
                .frame(width: timelineWidth, height: allDayHeaderHeight)

                EditablePlanTimelineView(
                    date: date,
                    plans: plans,
                    categories: categories,
                    planPresets: planPresets,
                    visibleCategoryIDs: visibleCategoryIDs,
                    isEditingEnabled: store.canCreatePlan(startTime: date, isAllDay: false),
                    planTitleFontSize: planTitleFontSize,
                    planTitleBold: planTitleBold,
                    isInteractionEnabled: isInteractionEnabled,
                    isPageSwipeActive: isPageSwipeActive,
                    presetInteractionCoordinator: presetInteractionCoordinator,
                    presetExternalCoordinateSpaceName: presetExternalCoordinateSpaceName,
                    showsChrome: false,
                    colorStyle: .calendarGrid,
                    visibleHour: $visibleHour,
                    selectedCategoryID: $selectedCategoryID,
                    isScheduleInteractionActive: $isScheduleInteractionActive,
                    onEditPlan: onEditPlan,
                    onScheduleChanged: onScheduleChanged
                )
                .frame(
                    width: timelineWidth,
                    height: max(1, cardHeight - allDayHeaderHeight),
                    alignment: .top
                )
            }
            .frame(width: timelineWidth, height: cardHeight, alignment: .top)
            .background(dayTimelineBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dayTimelineStroke, lineWidth: 1)
            )
            .padding(.horizontal, CalendarTimelineCardMetrics.horizontalPadding)
            .padding(.top, CalendarTimelineCardMetrics.topPadding)
        }
    }

    private var allDayPlans: [PlanBlock] {
        plans
            .filter { $0.isAllDay && isPlanVisible($0) }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func isPlanVisible(_ plan: PlanBlock) -> Bool {
        guard let visibleCategoryIDs else { return true }
        guard let categoryID = plan.category?.id else { return false }
        return visibleCategoryIDs.contains(categoryID)
    }

    private var dayTimelineBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.035, green: 0.037, blue: 0.043)
            : Color(red: 0.985, green: 0.985, blue: 0.98)
    }

    private var dayTimelineStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

}

private struct CalendarDayTimelineAllDayHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let plans: [PlanBlock]
    let planTitleFontSize: Double
    let onOpenDay: ((Date) -> Void)?
    let onOpenPlan: (PlanBlock) -> Void
    private let calendar = Calendar.japanese

    static func height(forPlanCount planCount: Int, planTitleFontSize: Double) -> CGFloat {
        dayHeaderHeight + allDayLaneHeight(
            forPlanCount: planCount,
            planTitleFontSize: planTitleFontSize
        )
    }

    private static func allDayLaneHeight(forPlanCount planCount: Int, planTitleFontSize: Double) -> CGFloat {
        let visibleCount = min(planCount, visibleRowLimit)
        guard visibleCount > 0 else { return 1 }
        let itemHeight = CalendarDayTimelineAllDayRow.height(forTitleFontSize: planTitleFontSize)
        return laneVerticalPadding * 2
            + CGFloat(visibleCount) * itemHeight
            + CGFloat(max(visibleCount - 1, 0)) * itemSpacing
    }

    private static let visibleRowLimit = 2
    private static let dayHeaderHeight: CGFloat = 46
    private static let hourColumnWidth = TimelineHourAxisMetrics.columnWidth
    private static let daySpacing: CGFloat = 1
    private static let itemSpacing: CGFloat = 1.5
    private static let laneVerticalPadding: CGFloat = 2

    private var visiblePlans: ArraySlice<PlanBlock> {
        plans.prefix(Self.visibleRowLimit)
    }

    private var hiddenCount: Int {
        max(0, plans.count - Self.visibleRowLimit)
    }

    private var allDayLaneHeight: CGFloat {
        Self.allDayLaneHeight(
            forPlanCount: plans.count,
            planTitleFontSize: planTitleFontSize
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.daySpacing) {
                Rectangle()
                    .fill(hourColumnBackground)
                    .frame(width: Self.hourColumnWidth, height: Self.dayHeaderHeight)

                dateHeader
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.dayHeaderHeight)
                    .background(dayHeaderBackground)
            }
            .frame(height: Self.dayHeaderHeight)
            .background(gridLine)

            HStack(alignment: .top, spacing: Self.daySpacing) {
                Rectangle()
                    .fill(hourColumnBackground)
                    .frame(width: Self.hourColumnWidth)
                    .frame(height: allDayLaneHeight)

                VStack(alignment: .leading, spacing: Self.itemSpacing) {
                    ForEach(visiblePlans) { plan in
                        Button {
                            LiminalHaptics.openSheet()
                            onOpenPlan(plan)
                        } label: {
                            CalendarDayTimelineAllDayRow(
                                title: plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title,
                                tint: plan.category?.displayColor ?? LiminalTheme.accent,
                                titleFontSize: planTitleFontSize
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, Self.laneVerticalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: allDayLaneHeight, alignment: .topLeading)
                .background(dayColumnBackground)
            }
            .frame(height: allDayLaneHeight)
        }
        .background(gridLine)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(gridLine)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var dateHeader: some View {
        if let onOpenDay {
            Button {
                onOpenDay(date)
            } label: {
                dateHeaderLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(date.japaneseMonthDayShortWeekday)を開く")
        } else {
            dateHeaderLabel
        }
    }

    private var dateHeaderLabel: some View {
        VStack(spacing: 2) {
            Text(dayNumberText)
                .font(.system(size: 14, weight: isToday ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(dayNumberColor)
                .frame(width: 27, height: 27)
                .background {
                    if isToday {
                        Circle()
                            .fill(LiminalTheme.accent.opacity(0.82))
                    }
                }

            Text(weekdayText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(weekdayColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var dayNumberText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var weekdayText: String {
        let index = calendar.component(.weekday, from: date) - 1
        return Calendar.japaneseShortWeekdaySymbols[max(0, min(index, Calendar.japaneseShortWeekdaySymbols.count - 1))]
    }

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var weekdayColor: Color {
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return LiminalTheme.secondaryText
    }

    private var dayNumberColor: Color {
        isToday ? .white : weekdayColor
    }

    private var dayHeaderBackground: Color {
        timelineBackground
    }

    private var dayColumnBackground: Color {
        timelineBackground
    }

    private var timelineBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.035, green: 0.037, blue: 0.043)
            : Color(red: 0.985, green: 0.985, blue: 0.98)
    }

    private var hourColumnBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.05, green: 0.052, blue: 0.06)
            : Color(red: 0.955, green: 0.955, blue: 0.945)
    }

    private var gridLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.13)
    }
}

struct CalendarDayTimelineAllDayRow: View {
    let title: String
    let tint: Color
    let titleFontSize: Double

    static func height(forTitleFontSize titleFontSize: Double) -> CGFloat {
        max(13, ceil(displayTitleFontSize(for: titleFontSize) + 2))
    }

    private static func displayTitleFontSize(for titleFontSize: Double) -> CGFloat {
        CalendarPlanTitleMetrics.timelineBlockTitleSize(titleFontSize)
    }

    var body: some View {
        Text(title)
            .font(.system(size: displayTitleFontSize, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height(forTitleFontSize: titleFontSize))
            .background(tint.opacity(0.68), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }

    private var displayTitleFontSize: CGFloat {
        Self.displayTitleFontSize(for: titleFontSize)
    }
}

private struct CalendarDayPagerSheet: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let highlightedPlanID: UUID?

    @State private var scrolledOffset: Int? = 0
    @State private var pendingCreateDate: Date
    @State private var pendingPlanStartsAsAllDay = false
    @State private var showingPlanSheet = false
    @State private var operationError: String?
    private let pageOffsets = Array(-240...240)

    init(initialDate: Date, highlightedPlanID: UUID?) {
        self.initialDate = Calendar.japanese.startOfDay(for: initialDate)
        self.highlightedPlanID = highlightedPlanID
        _pendingCreateDate = State(initialValue: Calendar.japanese.startOfDay(for: initialDate))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(pageOffsets, id: \.self) { offset in
                    CalendarDayView(
                        date: pageDate(offset),
                        highlightedPlanID: highlightedPlanID(for: pageDate(offset)),
                        showsNavigationControls: false,
                        allowsDayNavigation: false
                    )
                    .containerRelativeFrame(.horizontal)
                    .accessibilityHidden(offset != currentOffset)
                    .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledOffset, anchor: .center)
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
        .contentShape(Rectangle())
        .onAppear {
            if scrolledOffset == nil {
                scrolledOffset = 0
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    LiminalHaptics.lightImpact(intensity: 0.45)
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    dayVisibilityMenu
                    if canCreatePlansForDay {
                        Button {
                            LiminalHaptics.openSheet()
                            preparePlanCreation()
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(LiminalTheme.accent)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("予定を追加")
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsAllDay)
        }
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var currentOffset: Int {
        scrolledOffset ?? 0
    }

    private var currentDate: Date {
        pageDate(currentOffset)
    }

    private func pageDate(_ offset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: offset, to: initialDate) ?? initialDate
    }

    private func highlightedPlanID(for date: Date) -> UUID? {
        Calendar.japanese.isDate(date, inSameDayAs: initialDate) ? highlightedPlanID : nil
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

    private var dayVisibilityMenu: some View {
        let visibleDayChapters = dayChapters
        let allPublic = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy(\.isPublic)
        let allPrivate = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy { !$0.isPublic }
        let isMixed = !visibleDayChapters.isEmpty && !allPublic && !allPrivate

        return Menu {
            if visibleDayChapters.isEmpty {
                Text("この日にチャプターはありません")
            } else {
                if isMixed {
                    Text("公開/非公開が混在しています")
                        .font(.caption)
                }
                Button {
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: true) else {
                        LiminalHaptics.failure()
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                    LiminalHaptics.selection()
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: false) else {
                        LiminalHaptics.failure()
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                    LiminalHaptics.selection()
                } label: {
                    Label("すべて非公開", systemImage: "eye.slash")
                }
                .disabled(allPrivate)

                Divider()
                Text("\(visibleDayChapters.count)件のチャプター")
                    .font(.caption)
            }
        } label: {
            Image(systemName: allPrivate ? "eye.slash" : (isMixed ? "eye.fill" : "eye"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(LiminalTheme.accent)
        }
        .accessibilityLabel("この日の公開設定")
    }

    private var dayChapters: [Chapter] {
        let boundary = DayBoundary(date: currentDate, calendar: .japanese)
        return ScoreSnapshotLoader.chapters(
            in: DateInterval(start: boundary.dayStart, end: boundary.dayEnd),
            modelContext: modelContext,
            now: Date(),
            calendar: .japanese
        )
    }

    private var canCreateTimedPlansForDay: Bool {
        store.canCreatePlan(startTime: currentDate, isAllDay: false)
    }

    private var canCreatePlansForDay: Bool {
        CalendarPlanCreationPreset.allowsCreation(for: currentDate)
    }

    private func preparePlanCreation() {
        guard let preset = CalendarPlanCreationPreset.make(
            for: currentDate,
            canCreateTimedPlan: canCreateTimedPlansForDay
        ) else { return }
        pendingCreateDate = preset.initialDate
        pendingPlanStartsAsAllDay = preset.startsAsAllDay
        showingPlanSheet = true
    }
}

private struct CalendarPlanCreationRequest: Identifiable {
    let id = UUID()
    let preset: CalendarPlanCreationPreset
}

private struct CalendarDayPresentation: Identifiable, Hashable {
    let date: Date
    let planID: UUID?

    var id: String {
        let day = Calendar.japanese.startOfDay(for: date).timeIntervalSince1970
        return "\(day)-\(planID?.uuidString ?? "day")"
    }
}

enum CalendarPlanLabelStyle: String, CaseIterable, Identifiable {
    case background
    case textOnly
    case underline

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .background:
            return "背景色"
        case .textOnly:
            return "文字色"
        case .underline:
            return "下線＋文字色"
        }
    }
}

struct CalendarSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CalendarSettingsContent()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

struct CalendarFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = CalendarFilterTab.categories

    let categories: [Category]
    let friends: [Friend]
    let isResetEnabled: Bool
    let isCategorySelected: (Category) -> Bool
    let onToggleCategory: (Category) -> Void
    let isFriendSelected: (Friend) -> Bool
    let onToggleFriend: (Friend) -> Void
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("表示対象", selection: $selectedTab) {
                    ForEach(CalendarFilterTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTab) { oldTab, newTab in
                    guard oldTab != newTab else { return }
                    LiminalHaptics.selection()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                TabView(selection: $selectedTab) {
                    CalendarCategoryFilterList(
                        categories: categories,
                        isResetEnabled: isResetEnabled,
                        isCategorySelected: isCategorySelected,
                        onToggleCategory: onToggleCategory,
                        onReset: onReset
                    )
                    .tag(CalendarFilterTab.categories)

                    CalendarFriendFilterList(
                        friends: friends,
                        isResetEnabled: isResetEnabled,
                        isFriendSelected: isFriendSelected,
                        onToggleFriend: onToggleFriend,
                        onReset: onReset
                    )
                    .tag(CalendarFilterTab.friends)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("表示フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .tint(LiminalTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum CalendarFilterTab: String, CaseIterable, Identifiable {
    case categories
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categories:
            "カテゴリ"
        case .friends:
            "友達"
        }
    }

    var systemImage: String {
        switch self {
        case .categories:
            "square.grid.2x2"
        case .friends:
            "person.2"
        }
    }
}

private struct CalendarCategoryFilterList: View {
    let categories: [Category]
    let isResetEnabled: Bool
    let isCategorySelected: (Category) -> Bool
    let onToggleCategory: (Category) -> Void
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                if categories.isEmpty {
                    Text("カテゴリがありません")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } else {
                    ForEach(categories) { category in
                        CalendarCategoryFilterRow(
                            category: category,
                            isSelected: isCategorySelected(category),
                            onToggle: { onToggleCategory(category) }
                        )
                    }
                }
            } header: {
                Text("カテゴリ")
            } footer: {
                Text("オフにしたカテゴリの予定と実績はカレンダー上で非表示になります。")
            }

            Section {
                Button("すべて表示に戻す") {
                    LiminalHaptics.selection()
                    onReset()
                }
                .disabled(!isResetEnabled)
            }
        }
    }
}

private struct CalendarFriendFilterList: View {
    let friends: [Friend]
    let isResetEnabled: Bool
    let isFriendSelected: (Friend) -> Bool
    let onToggleFriend: (Friend) -> Void
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                if friends.isEmpty {
                    Text("選べる友達がいません")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } else {
                    ForEach(friends) { friend in
                        CalendarFriendFilterRow(
                            friend: friend,
                            isSelected: isFriendSelected(friend),
                            onToggle: { onToggleFriend(friend) }
                        )
                    }
                }
            } header: {
                Text("友達")
            } footer: {
                Text("選んだ友達の予定を自分のカレンダーに重ねて表示します。")
            }

            Section {
                Button("すべて表示に戻す") {
                    LiminalHaptics.selection()
                    onReset()
                }
                .disabled(!isResetEnabled)
            }
        }
    }
}

private struct CalendarCategoryFilterRow: View {
    let category: Category
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in
                LiminalHaptics.selection()
                onToggle()
            }
        )) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(category.displayColor.opacity(0.18))
                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.displayColor)
                }
                .frame(width: 30, height: 30)

                Text(category.name)
                    .foregroundStyle(LiminalTheme.text)
            }
        }
    }
}

private struct CalendarFriendFilterRow: View {
    let friend: Friend
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in
                LiminalHaptics.selection()
                onToggle()
            }
        )) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cachedDisplayHex(friend.accentColorHex).opacity(0.18))
                    Image(systemName: friend.avatarSystemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cachedDisplayHex(friend.accentColorHex))
                }
                .frame(width: 30, height: 30)

                Text(friend.displayName)
                    .foregroundStyle(LiminalTheme.text)
            }
        }
    }
}

struct CalendarSettingsContent: View {
    @AppStorage("calendarTimedPlanLabelStyle") private var timedPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarAllDayPlanLabelStyle") private var allDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarMultiDayPlanLabelStyle") private var multiDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false
    @AppStorage(TimelineSnapPrecision.userDefaultsKey)
    private var storedSnapPrecisionMinutes = TimelineSnapPrecision.quarterHour.minutes

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PlanPresetSettingsView()
                } label: {
                    Label("予定プリセット", systemImage: "bookmark")
                }

                NavigationLink {
                    DayPresetSettingsView()
                } label: {
                    Label("一日プリセット", systemImage: "calendar.badge.clock")
                }
            } header: {
                SettingsSectionHeader(
                    title: "プリセット",
                    explanation: "予定プリセットは、よく使う予定を保存してタイムラインに追加できます。一日プリセットは、一日分の予定をまとめて作成・適用できます。"
                )
            }

            Section {
                CalendarLabelStyleSettingRow(
                    title: "時刻指定",
                    selectionRaw: $timedPlanLabelStyleRaw,
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: "9:30"
                )

                CalendarLabelStyleSettingRow(
                    title: "終日",
                    selectionRaw: $allDayPlanLabelStyleRaw,
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )

                CalendarLabelStyleSettingRow(
                    title: "複数日",
                    selectionRaw: $multiDayPlanLabelStyleRaw,
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )
            } header: {
                SettingsSectionHeader(
                    title: "予定",
                    explanation: "月間カレンダーの予定の見た目を変更します。時刻指定・終日・複数日の予定ごとに、背景や下線などの表示形式を選べます。"
                )
            }

            Section {
                CalendarFontSizeSlider(value: normalizedPlanTitleFontSizeBinding)
                Toggle("太字", isOn: $planTitleBold)
            } header: {
                SettingsSectionHeader(
                    title: "フォント",
                    explanation: "カレンダーに表示する予定名の文字サイズと太さを変更します。タイムラインの予定名にも反映されます。"
                )
            }

            Section {
                TimelineSnapPrecisionSelector(precision: snapPrecisionBinding)
                    .padding(.vertical, 4)
            } header: {
                SettingsSectionHeader(
                    title: "タイムライン操作",
                    explanation: "日間・週間タイムラインで、予定を移動したり長さを変えたりするときの刻み幅です。小さい値ほど細かく調整できます。"
                )
            }

            Section {
                Toggle("過去の予定を薄くする", isOn: $dimPastPlans)
                Toggle("打ち消し線を入れる", isOn: $strikePastPlans)
            } header: {
                SettingsSectionHeader(
                    title: "過去の予定",
                    explanation: "過去の予定を薄く表示するか、打ち消し線を入れるかを変更します。それぞれ独立して選べるため、薄くせず打ち消し線だけを入れることもできます。"
                )
            }
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            normalizePlanTitleFontSize()
            normalizePlanLabelStyleRawValues()
            normalizeSnapPrecision()
        }
        .onChange(of: planTitleFontSize) { _, _ in
            normalizePlanTitleFontSize()
        }
        .onChange(of: timedPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: allDayPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: multiDayPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: storedSnapPrecisionMinutes) { _, _ in
            normalizeSnapPrecision()
        }
    }

    private var normalizedPlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
    }

    private var normalizedPlanTitleFontSizeBinding: Binding<Double> {
        Binding {
            normalizedPlanTitleFontSize
        } set: { newValue in
            planTitleFontSize = CalendarPlanTitleMetrics.clamped(newValue)
        }
    }

    private var snapPrecisionBinding: Binding<TimelineSnapPrecision> {
        Binding(
            get: {
                TimelineSnapPrecision.normalized(minutes: storedSnapPrecisionMinutes)
            },
            set: { newValue in
                storedSnapPrecisionMinutes = newValue.minutes
            }
        )
    }

    private func normalizePlanTitleFontSize() {
        let normalized = normalizedPlanTitleFontSize
        guard planTitleFontSize != normalized else { return }
        planTitleFontSize = normalized
    }

    private func normalizeSnapPrecision() {
        let normalized = TimelineSnapPrecision.normalized(minutes: storedSnapPrecisionMinutes).minutes
        guard storedSnapPrecisionMinutes != normalized else { return }
        storedSnapPrecisionMinutes = normalized
    }

    private func normalizePlanLabelStyleRawValues() {
        let defaultRawValue = CalendarPlanLabelStyle.background.rawValue
        let normalizedTimed = CalendarPlanLabelStyle(rawValue: timedPlanLabelStyleRaw)?.rawValue ?? defaultRawValue
        let normalizedAllDay = CalendarPlanLabelStyle(rawValue: allDayPlanLabelStyleRaw)?.rawValue ?? defaultRawValue
        let normalizedMultiDay = CalendarPlanLabelStyle(rawValue: multiDayPlanLabelStyleRaw)?.rawValue ?? defaultRawValue

        if timedPlanLabelStyleRaw != normalizedTimed {
            timedPlanLabelStyleRaw = normalizedTimed
        }
        if allDayPlanLabelStyleRaw != normalizedAllDay {
            allDayPlanLabelStyleRaw = normalizedAllDay
        }
        if multiDayPlanLabelStyleRaw != normalizedMultiDay {
            multiDayPlanLabelStyleRaw = normalizedMultiDay
        }
    }
}

enum CalendarPlanTitleMetrics {
    static let defaultSize = 6.0
    static let minSize = 5.0
    static let maxSize = 9.0
    static let step = 0.5

    static var stepCount: Int {
        Int(((maxSize - minSize) / step).rounded()) + 1
    }

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSize }
        return min(max(value, minSize), maxSize)
    }

    static func timelineBlockTitleSize(_ value: Double) -> CGFloat {
        let normalized = clamped(value)
        return CGFloat(10.8 + (normalized - defaultSize) * 0.62)
    }
}

private struct CalendarLabelStyleSettingRow: View {
    let title: String
    @Binding var selectionRaw: String
    let fontSize: Double
    let isBold: Bool
    let sampleTime: String?

    private let sampleColor = Color.blue
    private var selectedStyle: CalendarPlanLabelStyle {
        CalendarPlanLabelStyle(rawValue: selectionRaw) ?? .background
    }

    var body: some View {
        NavigationLink {
            CalendarLabelStyleSelectionView(
                title: title,
                selectionRaw: $selectionRaw,
                fontSize: fontSize,
                isBold: isBold,
                sampleTime: sampleTime,
                sampleColor: sampleColor
            )
        } label: {
            HStack(spacing: 16) {
                Text(title)
                    .font(.body.weight(.medium))

                Spacer(minLength: 12)

                CalendarLabelStylePreview(
                    style: selectedStyle,
                    color: sampleColor,
                    fontSize: previewFontSize,
                    isBold: true,
                    timeText: sampleTime
                )
                .frame(width: 128, height: 22, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var previewFontSize: Double {
        sampleTime == nil ? 9 : 8
    }
}

private struct CalendarLabelStyleSelectionView: View {
    let title: String
    @Binding var selectionRaw: String
    let fontSize: Double
    let isBold: Bool
    let sampleTime: String?
    let sampleColor: Color

    var body: some View {
        Form {
            Section {
                ForEach(CalendarPlanLabelStyle.allCases) { style in
                    Button {
                        selectionRaw = style.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            if selectionRaw == style.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 22)
                            } else {
                                Color.clear
                                    .frame(width: 22)
                            }

                            Text(style.label)
                                .foregroundStyle(LiminalTheme.text)

                            Spacer(minLength: 16)

                            CalendarLabelStylePreview(
                                style: style,
                                color: sampleColor,
                                fontSize: previewFontSize,
                                isBold: true,
                                timeText: sampleTime
                            )
                            .frame(width: 160, height: 24, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewFontSize: Double {
        sampleTime == nil ? 10 : 9
    }
}

private struct CalendarFontSizeSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text("A")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 0) {
                Slider(value: $value, in: CalendarPlanTitleMetrics.minSize...CalendarPlanTitleMetrics.maxSize, step: CalendarPlanTitleMetrics.step)

                HStack {
                    ForEach(0..<CalendarPlanTitleMetrics.stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == selectedStepIndex ? LiminalTheme.accent : LiminalTheme.secondaryText.opacity(0.42))
                            .frame(width: index == selectedStepIndex ? 5 : 3, height: index == selectedStepIndex ? 5 : 3)

                        if index < CalendarPlanTitleMetrics.stepCount - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, -2)
                .allowsHitTesting(false)
            }

            Text("A")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    private var selectedStepIndex: Int {
        let normalized = CalendarPlanTitleMetrics.clamped(value)
        let rawIndex = Int(((normalized - CalendarPlanTitleMetrics.minSize) / CalendarPlanTitleMetrics.step).rounded())
        return min(max(rawIndex, 0), CalendarPlanTitleMetrics.stepCount - 1)
    }
}

private struct CalendarLabelStylePreview: View {
    let style: CalendarPlanLabelStyle
    let color: Color
    let fontSize: Double
    let isBold: Bool
    let timeText: String?

    var body: some View {
        HStack(spacing: 3) {
            if let timeText {
                Text(timeText)
                    .font(.system(size: max(4, displayFontSize - 1), weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Text("予定")
                .font(.system(size: displayFontSize, weight: isBold ? .bold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(9, CGFloat(displayFontSize) + 3))
        .padding(.horizontal, 3)
        .offset(y: textVerticalOffset)
        .background {
            if style == .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.18))
            }
        }
        .overlay {
            if style == .background {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.34), lineWidth: 0.8)
            }
        }
        .overlay(alignment: .bottom) {
            if style == .underline {
                Rectangle()
                    .fill(color.opacity(0.28))
                    .frame(height: markerHeight)
                    .padding(.bottom, markerBottomPadding)
            }
        }
        .clipped()
    }

    private var titleColor: Color {
        style == .background ? .primary : color
    }

    private var timeColor: Color {
        style == .background ? .secondary : color.opacity(0.75)
    }

    private var markerHeight: CGFloat {
        max(2, CGFloat(displayFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        max(0.5, CGFloat(displayFontSize) * 0.05)
    }

    private var textVerticalOffset: CGFloat {
        style == .underline ? -max(0.5, CGFloat(displayFontSize) * 0.1) : 0
    }

    private var displayFontSize: Double {
        CalendarPlanTitleMetrics.clamped(fontSize)
    }
}

struct CalendarMonthPickerSheet: View {
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    @Binding var selectedDay: Int
    let includesDay: Bool
    let yearRange: ClosedRange<Int>
    let onCancel: () -> Void
    let onDone: () -> Void

    private let calendar = Calendar.japanese

    init(
        selectedYear: Binding<Int>,
        selectedMonth: Binding<Int>,
        selectedDay: Binding<Int> = .constant(1),
        includesDay: Bool = false,
        yearRange: ClosedRange<Int>,
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        _selectedYear = selectedYear
        _selectedMonth = selectedMonth
        _selectedDay = selectedDay
        self.includesDay = includesDay
        self.yearRange = yearRange
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $selectedYear) {
                    ForEach(Array(yearRange), id: \.self) { year in
                        Text(verbatim: "\(year)年").tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("月", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                if includesDay {
                    Picker("日", selection: $selectedDay) {
                        ForEach(1...daysInSelectedMonth, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .navigationTitle(includesDay ? "日付を選択" : "年月を選択")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedYear) { _, _ in
                clampSelectedDay()
            }
            .onChange(of: selectedMonth) { _, _ in
                clampSelectedDay()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了", action: onDone)
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    private var daysInSelectedMonth: Int {
        let components = DateComponents(year: selectedYear, month: selectedMonth, day: 1)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 31 }
        return range.count
    }

    private func clampSelectedDay() {
        selectedDay = min(selectedDay, daysInSelectedMonth)
    }
}

private struct CalendarPlanSearchSheet: View {
    let onOpenDay: (PlanBlock) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PlanBlock.startTime)]) private var plans: [PlanBlock]
    @State private var query = ""
    @State private var editingPlan: PlanBlock?

    private let calendar = Calendar.japanese

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if plans.isEmpty {
                                ContentUnavailableView(
                                    "検索できる予定がありません",
                                    systemImage: "calendar",
                                    description: Text("予定を作成すると、ここから探せます")
                                )
                                .padding(.top, 72)
                            } else if trimmedQuery.isEmpty {
                                ContentUnavailableView(
                                    "予定名を入力",
                                    systemImage: "magnifyingglass",
                                    description: Text("検索欄に入力すると候補を表示します")
                                )
                                .padding(.top, 72)
                            } else if filteredPlans.isEmpty {
                                ContentUnavailableView(
                                    "該当する予定はありません",
                                    systemImage: "magnifyingglass",
                                    description: Text("別の予定名で検索してください")
                                )
                                .padding(.top, 72)
                            } else {
                                ForEach(filteredPlans) { plan in
                                    CalendarPlanSearchRow(
                                        plan: plan,
                                        now: Date(),
                                        onEdit: {
                                            editingPlan = plan
                                        }
                                    )
                                        .id(plan.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            LiminalHaptics.openSheet()
                                            onOpenDay(plan)
                                        }
                                        .contextMenu {
                                            Button {
                                                LiminalHaptics.openSheet()
                                                editingPlan = plan
                                            } label: {
                                                Label("編集", systemImage: "pencil")
                                            }
                                        }

                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    .onAppear {
                        scrollToNearestFuture(using: proxy)
                    }
                    .onChange(of: query) {
                        scrollToNearestFuture(using: proxy)
                    }
                }

                Text(searchResultText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LiminalTheme.surface)
            }
            .navigationTitle("予定を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $editingPlan) { plan in
            PlanCreateSheet(plan: plan)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResultText: String {
        if plans.isEmpty { return "検索できる予定はありません" }
        if trimmedQuery.isEmpty { return "予定名を入力してください" }
        if filteredPlans.isEmpty { return "該当する予定はありません" }
        return "\(filteredPlans.count)件見つかりました"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(LiminalTheme.secondaryText)

            TextField("予定名で検索", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title3.weight(.medium))

            if !query.isEmpty {
                Button {
                    LiminalHaptics.selection()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            Capsule()
                .fill(LiminalTheme.surface)
        )
        .overlay(
            Capsule()
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
        )
    }

    private var filteredPlans: [PlanBlock] {
        guard !trimmedQuery.isEmpty else { return [] }

        let sortedPlans = plans.sorted {
            let lhsDate = searchSortDate(for: $0)
            let rhsDate = searchSortDate(for: $1)
            if lhsDate == rhsDate {
                return $0.createdAt < $1.createdAt
            }
            return lhsDate < rhsDate
        }

        return sortedPlans.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func scrollToNearestFuture(using proxy: ScrollViewProxy) {
        guard let target = filteredPlans.first(where: { searchSortDate(for: $0) >= Date() }) else { return }
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func searchSortDate(for plan: PlanBlock) -> Date {
        guard plan.isAllDay else { return plan.startTime }
        let dayStart = calendar.startOfDay(for: plan.startTime)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? plan.startTime
    }
}

private struct CalendarPlanSearchRow: View {
    let plan: PlanBlock
    let now: Date
    let onEdit: () -> Void

    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    private var isPast: Bool {
        sortDate < now
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.startTime.japaneseYear)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)

                Text(monthDayText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isPast ? LiminalTheme.secondaryText : Color.red)
                    .monospacedDigit()

                Text(weekdayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPast ? LiminalTheme.secondaryText : Color.red)
            }
            .frame(width: 88, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Circle()
                        .fill(plan.category?.displayColor ?? LiminalTheme.accent)
                        .frame(width: 6, height: 6)

                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1)
                        .strikethrough(isPast && strikePastPlans, color: LiminalTheme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                LiminalHaptics.openSheet()
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LiminalTheme.elevated)
                    )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(plan.title)を編集")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .opacity(isPast && dimPastPlans ? 0.38 : 1)
        .accessibilityLabel("\(plan.title) \(plan.startTime.japaneseMonthDayShortWeekday)")
    }

    private var sortDate: Date {
        guard plan.isAllDay else { return plan.startTime }
        let dayStart = Calendar.japanese.startOfDay(for: plan.startTime)
        return Calendar.japanese.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? plan.startTime
    }

    private var monthDayText: String {
        let month = Calendar.japanese.component(.month, from: plan.startTime)
        let day = Calendar.japanese.component(.day, from: plan.startTime)
        return "\(month)月\(day)日"
    }

    private var weekdayText: String {
        let weekdayIndex = Calendar.japanese.component(.weekday, from: plan.startTime) - 1
        let weekday = Calendar.japaneseShortWeekdaySymbols[max(0, min(weekdayIndex, Calendar.japaneseShortWeekdaySymbols.count - 1))]
        return "\(weekday)曜日"
    }

    private var timeText: String {
        if plan.isAllDay {
            return "終日"
        }
        return "\(plan.startTime.shortTime) - \(plan.endTime.shortTime)"
    }
}

private extension PlanBlock {
    var showsInCalendarAsImportant: Bool {
        isAllDay || isImportant
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = isAllDay ? endTime.addingTimeInterval(-1) : endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let calendar = Calendar.japanese
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

private struct CalendarMonthPage: View {
    let weekdays: [String]
    let weekdayColor: (String) -> Color
    let pageData: CalendarMonthPageData
    let onOpenDay: (Date, UUID?) -> Void
    let onCreatePlan: (Date) -> Void

    private let spacing: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: spacing) {
                CalendarWeekdayHeader(
                    weekdays: weekdays,
                    weekdayColor: weekdayColor
                )

                CalendarMonthGrid(
                    pageData: pageData,
                    onOpenDay: onOpenDay,
                    onCreatePlan: onCreatePlan
                )
            }

            if pageData.didFailToLoadRecords {
                Text("一部を読み込めませんでした")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(LiminalTheme.elevated.opacity(0.94))
                    )
                    .overlay(
                        Capsule()
                            .stroke(LiminalTheme.divider.opacity(0.7), lineWidth: 0.5)
                    )
                    .padding(.top, 30)
            }
        }
        .frame(height: Self.height(forWeekCount: weekCount), alignment: .top)
        .background(LiminalTheme.divider.opacity(0.56))
    }

    static func height(forWeekCount weekCount: Int) -> CGFloat {
        let clampedWeekCount = max(5, min(6, weekCount))
        let gridHeight = CGFloat(clampedWeekCount) * CalendarMonthDayCell.cellHeight(forWeekCount: clampedWeekCount)
        let gridSpacing = CGFloat(clampedWeekCount - 1)
        return 28 + 1 + gridHeight + gridSpacing
    }

    private var weekCount: Int {
        pageData.dates.count / 7
    }
}

private struct CalendarFriendPlanSource {
    let friend: Friend
    let plans: [FriendSharedPlanSnapshot]
}

struct CalendarWeekdayHeader: View {
    let weekdays: [String]
    let weekdayColor: (String) -> Color

    private let spacing: CGFloat = 1

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(weekday))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(LiminalTheme.surface)
            }
        }
        .background(LiminalTheme.divider.opacity(0.56))
    }
}

struct CalendarDisplayScore: Hashable {
    enum Kind: Hashable {
        case score
        case sharedData
    }

    let value: Double
    let hasData: Bool
    let kind: Kind

    init(value: Double, hasData: Bool, kind: Kind = .score) {
        self.value = value
        self.hasData = hasData
        self.kind = kind
    }

    init(summary: ScoreSummary) {
        self.value = summary.totalScore
        self.hasData = summary.plannedDuration > 0
        self.kind = .score
    }

    init(sharedScore: FriendSharedDailyScoreSnapshot) {
        self.value = Double(sharedScore.score)
        self.hasData = sharedScore.hasData
        self.kind = .score
    }

    static var sharedDataMarker: CalendarDisplayScore {
        CalendarDisplayScore(value: 0, hasData: true, kind: .sharedData)
    }

    static var emptyScoreMarker: CalendarDisplayScore {
        CalendarDisplayScore(value: 0, hasData: false)
    }
}

struct CalendarDisplayPlan: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let categoryColorHex: String
    let createdAt: Date

    init(
        id: UUID,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        categoryColorHex: String,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.categoryColorHex = categoryColorHex
        self.createdAt = createdAt
    }

    init(plan: PlanBlock) {
        self.init(
            id: plan.id,
            title: plan.title,
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.category?.colorHex ?? "#2F80ED",
            createdAt: plan.createdAt
        )
    }

    init(friendPlan plan: FriendSharedPlanSnapshot, friendName: String) {
        self.init(
            id: plan.id,
            title: "\(friendName): \(plan.title)",
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.categoryColorHex,
            createdAt: plan.updatedAt
        )
    }

    var color: Color {
        Color.cachedDisplayHex(categoryColorHex)
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = isAllDay ? endTime.addingTimeInterval(-1) : endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let calendar = Calendar.japanese
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

struct CalendarMonthPageData {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlansByDay: [Date: [CalendarDisplayPlan]]
    let scoreSummariesByDay: [Date: CalendarDisplayScore]
    let didFailToLoadRecords: Bool
}

struct CalendarMonthGrid: View {
    let pageData: CalendarMonthPageData
    let onOpenDay: (Date, UUID?) -> Void
    let onCreatePlan: ((Date) -> Void)?

    private let spacing: CGFloat = 1

    var body: some View {
        VStack(spacing: spacing) {

            ForEach(Array(weekDates.enumerated()), id: \.offset) { _, dates in
                CalendarMonthWeekRow(
                    dates: dates,
                    visibleMonth: pageData.visibleMonth,
                    importantPlansByDay: pageData.importantPlansByDay,
                    scoreSummariesByDay: pageData.scoreSummariesByDay,
                    onOpenDay: onOpenDay,
                    onCreatePlan: onCreatePlan,
                    spacing: spacing,
                    cellHeight: cellHeight
                )
            }
        }
        .background(gridDividerColor)
    }

    private var weekDates: [[Date]] {
        stride(from: 0, to: pageData.dates.count, by: 7).map { start in
            Array(pageData.dates[start..<min(start + 7, pageData.dates.count)])
        }
    }

    private var cellHeight: CGFloat {
        CalendarMonthDayCell.cellHeight(forWeekCount: weekDates.count)
    }

    private var gridDividerColor: Color {
        LiminalTheme.divider.opacity(0.58)
    }

}

private struct CalendarMonthWeekRow: View {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlansByDay: [Date: [CalendarDisplayPlan]]
    let scoreSummariesByDay: [Date: CalendarDisplayScore]
    let onOpenDay: (Date, UUID?) -> Void
    let onCreatePlan: ((Date) -> Void)?
    let spacing: CGFloat
    let cellHeight: CGFloat

    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0
    @AppStorage("calendarTimedPlanLabelStyle") private var timedPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarAllDayPlanLabelStyle") private var allDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    private let calendar = Calendar.japanese

    var body: some View {
        let placements = visibleMultiDayPlacements
        let cellModels = dayCellModels(placements: placements)

        ZStack(alignment: .topLeading) {
            HStack(spacing: spacing) {
                ForEach(cellModels) { model in
                    dayCellButton(model)
                }
            }

            GeometryReader { proxy in
                ForEach(placements) { placement in
                    if let frame = segmentFrame(for: placement, in: proxy.size) {
                        Button {
                            onOpenDay(placement.plan.startTime, placement.plan.id)
                        } label: {
                            CalendarMultiDayPlanBar(
                                plan: placement.plan,
                                roundsLeading: roundsLeadingEdge(for: placement.plan),
                                roundsTrailing: roundsTrailingEdge(for: placement.plan)
                            )
                            .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(placement.plan.title) 複数日に跨る重要な予定")
                        .frame(width: frame.width, height: labelHeight)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: cellHeight)
        }
        .frame(height: cellHeight)
    }

    @ViewBuilder
    private func dayCellButton(_ model: CalendarMonthDayCellModel) -> some View {
        if let onCreatePlan,
           CalendarPlanCreationPreset.allowsCreation(for: model.date, calendar: calendar) {
            baseDayCellButton(model)
                .contextMenu {
                    Button {
                        LiminalHaptics.openSheet()
                        onCreatePlan(model.date)
                    } label: {
                        Label("この日に予定を追加", systemImage: "calendar.badge.plus")
                    }
                }
                .accessibilityAction(named: "この日に予定を追加") {
                    LiminalHaptics.openSheet()
                    onCreatePlan(model.date)
                }
        } else {
            baseDayCellButton(model)
        }
    }

    private func baseDayCellButton(_ model: CalendarMonthDayCellModel) -> some View {
        Button {
            onOpenDay(model.date, nil)
        } label: {
            CalendarMonthDayCell(
                date: model.date,
                visibleMonth: visibleMonth,
                visibleImportantPlans: model.visibleImportantPlans,
                overflowCount: model.overflowCount,
                reservedPlanRows: model.reservedPlanRows,
                scoreSummary: model.scoreSummary,
                cellHeight: cellHeight,
                labelConfiguration: labelConfiguration
            )
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityText)
        .accessibilityHint(onCreatePlan == nil ? "日を開きます" : "タップで日を開き、長押しで予定を追加できます")
        .accessibilityIdentifier(
            "calendar-month-day-\(DailyCardSnapshot.dayIdentifier(for: model.date, calendar: calendar))"
        )
    }

    private var visibleMultiDayPlacements: [CalendarMultiDayPlacement] {
        let capacity = maxVisiblePlanRows
        guard capacity > 0 else { return [] }
        return multiDayPlacements.filter { $0.lane < capacity }
    }

    private var multiDayPlacements: [CalendarMultiDayPlacement] {
        let orderedPlans = multiDayPlans.compactMap { plan -> CalendarMultiDayPlacementSeed? in
            guard let span = clippedSpan(for: plan) else { return nil }
            return CalendarMultiDayPlacementSeed(plan: plan, startIndex: span.startIndex, endIndex: span.endIndex)
        }
        .sorted { lhs, rhs in
            if lhs.startIndex != rhs.startIndex {
                return lhs.startIndex < rhs.startIndex
            }
            if lhs.endIndex != rhs.endIndex {
                return lhs.endIndex > rhs.endIndex
            }
            if lhs.plan.startTime != rhs.plan.startTime {
                return lhs.plan.startTime < rhs.plan.startTime
            }
            return lhs.plan.createdAt < rhs.plan.createdAt
        }

        var laneEndIndices: [Int] = []
        return orderedPlans.map { seed in
            let lane = laneEndIndices.firstIndex { $0 <= seed.startIndex } ?? laneEndIndices.count
            if lane == laneEndIndices.count {
                laneEndIndices.append(seed.endIndex)
            } else {
                laneEndIndices[lane] = seed.endIndex
            }
            return CalendarMultiDayPlacement(
                plan: seed.plan,
                lane: lane,
                startIndex: seed.startIndex,
                endIndex: seed.endIndex
            )
        }
    }

    private var multiDayPlans: [CalendarDisplayPlan] {
        var seenIDs = Set<UUID>()
        return dates
            .flatMap { importantPlans(on: $0) }
            .filter(\.spansMultipleCalendarDays)
            .filter { plan in
                guard !seenIDs.contains(plan.id) else { return false }
                seenIDs.insert(plan.id)
                return true
            }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func reservedPlanRows(on date: Date, placements: [CalendarMultiDayPlacement]) -> Int {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)) else { return 0 }
        let dayIndex = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: date)).day ?? 0
        return (placements
            .filter { $0.startIndex <= dayIndex && dayIndex < $0.endIndex }
            .map(\.lane)
            .max() ?? -1) + 1
    }

    private func importantPlans(on date: Date) -> [CalendarDisplayPlan] {
        importantPlansByDay[calendar.startOfDay(for: date)] ?? []
    }

    private func scoreSummary(on date: Date) -> CalendarDisplayScore {
        scoreSummariesByDay[calendar.startOfDay(for: date)] ?? CalendarDisplayScore(value: 0, hasData: false)
    }

    private func dayCellModels(placements: [CalendarMultiDayPlacement]) -> [CalendarMonthDayCellModel] {
        dates.map { date in
            let importantPlans = importantPlans(on: date)
            let singleDayPlans = sortedSingleDayPlans(from: importantPlans)
            let reservedPlanRows = reservedPlanRows(on: date, placements: placements)
            let scoreSummary = scoreSummary(on: date)
            let visiblePlans = visibleSingleDayPlans(from: singleDayPlans, reservedPlanRows: reservedPlanRows)
            return CalendarMonthDayCellModel(
                date: date,
                visibleImportantPlans: visiblePlans,
                overflowCount: max(singleDayPlans.count - visiblePlans.count, 0),
                reservedPlanRows: reservedPlanRows,
                scoreSummary: scoreSummary,
                accessibilityText: dayAccessibilityText(
                    for: date,
                    plans: importantPlans,
                    score: scoreSummary
                )
            )
        }
    }

    private func sortedSingleDayPlans(from plans: [CalendarDisplayPlan]) -> [CalendarDisplayPlan] {
        plans
            .filter { !$0.spansMultipleCalendarDays }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func visibleSingleDayPlans(
        from plans: [CalendarDisplayPlan],
        reservedPlanRows: Int
    ) -> [CalendarDisplayPlan] {
        let capacity = maxVisiblePlanRows(reservedPlanRows: reservedPlanRows)
        guard capacity > 0 else { return [] }
        guard plans.count > capacity else { return plans }
        return Array(plans.prefix(max(capacity - 1, 0)))
    }

    private func dayAccessibilityText(
        for date: Date,
        plans: [CalendarDisplayPlan],
        score: CalendarDisplayScore
    ) -> String {
        var parts = [date.japaneseMonthDayShortWeekday]
        if score.hasData {
            if score.kind == .sharedData {
                parts.append("共有データあり")
            } else {
                parts.append("スコア \(Int(score.value.rounded()))")
            }
        } else {
            parts.append("スコアなし")
        }
        if !plans.isEmpty {
            let titles = plans.prefix(3).map(\.title).joined(separator: "、")
            parts.append("予定 \(titles)")
            if plans.count > 3 {
                parts.append("ほか\(plans.count - 3)件")
            }
        }
        return parts.joined(separator: "、")
    }

    private func maxVisiblePlanRows(reservedPlanRows: Int) -> Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride) - reservedPlanRows, 0)
    }

    private func segmentFrame(for placement: CalendarMultiDayPlacement, in size: CGSize) -> CGRect? {
        let columnWidth = (size.width - spacing * 6) / 7
        let columnCount = placement.endIndex - placement.startIndex
        guard columnCount > 0 else { return nil }
        let edgeInset: CGFloat = 1
        let x = CGFloat(placement.startIndex) * (columnWidth + spacing) + edgeInset
        let width = CGFloat(columnCount) * columnWidth
            + CGFloat(columnCount - 1) * spacing
            - edgeInset * 2
        let y = planListTop + CGFloat(placement.lane) * rowStride
        return CGRect(x: x, y: y, width: max(width, 2), height: labelHeight)
    }

    private func clippedSpan(for plan: CalendarDisplayPlan) -> (startIndex: Int, endIndex: Int)? {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)),
              let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return nil
        }

        let clippedStart = max(calendar.startOfDay(for: plan.startTime), weekStart)
        let clippedEnd = min(plan.endTime, weekEnd)
        let startIndex = max(0, calendar.dateComponents([.day], from: weekStart, to: clippedStart).day ?? 0)
        let endIndex = min(7, exclusiveDayIndex(for: clippedEnd, from: weekStart))
        guard endIndex > startIndex else { return nil }
        return (startIndex, endIndex)
    }

    private func exclusiveDayIndex(for end: Date, from weekStart: Date) -> Int {
        let endDay = calendar.startOfDay(for: end)
        let exclusiveEndDay: Date
        if abs(end.timeIntervalSince(endDay)) < 0.001 {
            exclusiveEndDay = endDay
        } else {
            exclusiveEndDay = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        }
        return calendar.dateComponents([.day], from: weekStart, to: exclusiveEndDay).day ?? 0
    }

    private func roundsLeadingEdge(for plan: CalendarDisplayPlan) -> Bool {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)) else { return true }
        return plan.startTime >= weekStart
    }

    private func roundsTrailingEdge(for plan: CalendarDisplayPlan) -> Bool {
        guard let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return true
        }
        return plan.endTime <= weekEnd
    }

    private var maxVisiblePlanRows: Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride), 0)
    }

    private var planListTop: CGFloat {
        4 + 22 + 4
    }

    private var labelHeight: CGFloat {
        max(9, CGFloat(displayPlanTitleFontSize) + 3)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }

    private var displayPlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
    }

    private var labelConfiguration: CalendarMonthPlanLabelConfiguration {
        CalendarMonthPlanLabelConfiguration(
            timedPlanLabelStyle: CalendarPlanLabelStyle(rawValue: timedPlanLabelStyleRaw) ?? .background,
            allDayPlanLabelStyle: CalendarPlanLabelStyle(rawValue: allDayPlanLabelStyleRaw) ?? .background,
            titleFontSize: displayPlanTitleFontSize,
            titleBold: planTitleBold,
            dimPastPlans: dimPastPlans,
            strikePastPlans: strikePastPlans
        )
    }
}

private struct CalendarMonthDayCellModel: Identifiable {
    var id: Date { date }
    let date: Date
    let visibleImportantPlans: [CalendarDisplayPlan]
    let overflowCount: Int
    let reservedPlanRows: Int
    let scoreSummary: CalendarDisplayScore
    let accessibilityText: String
}

private struct CalendarMultiDayPlacementSeed {
    let plan: CalendarDisplayPlan
    let startIndex: Int
    let endIndex: Int
}

private struct CalendarMultiDayPlacement: Identifiable {
    var id: UUID { plan.id }
    let plan: CalendarDisplayPlan
    let lane: Int
    let startIndex: Int
    let endIndex: Int
}

private struct CalendarMonthDayCell: View {
    static func cellHeight(forWeekCount weekCount: Int) -> CGFloat {
        weekCount <= 5 ? 110 : 92
    }

    let date: Date
    let visibleMonth: Date
    let visibleImportantPlans: [CalendarDisplayPlan]
    let overflowCount: Int
    let reservedPlanRows: Int
    let scoreSummary: CalendarDisplayScore
    let cellHeight: CGFloat
    let labelConfiguration: CalendarMonthPlanLabelConfiguration

    private var isToday: Bool {
        Calendar.japanese.isDateInToday(date)
    }

    private var isInVisibleMonth: Bool {
        Calendar.japanese.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Calendar.japanese.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? .white : dateNumberColor)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(LiminalTheme.accent)
                        }
                    }

                Spacer(minLength: 0)

                CalendarScoreBadge(summary: scoreSummary)
            }
            .padding(.horizontal, 3)

            VStack(alignment: .leading, spacing: 2) {
                if reservedPlanRows > 0 {
                    Color.clear
                        .frame(height: CGFloat(reservedPlanRows) * rowStride)
                }

                ForEach(visibleImportantPlans) { plan in
                    CalendarImportantPlanLabel(
                        plan: plan,
                        date: date,
                        configuration: labelConfiguration
                    )
                }

                if overflowCount > 0 {
                    Text("+\(overflowCount)件")
                        .font(.system(size: 6, weight: .regular))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(isInVisibleMonth ? LiminalTheme.surface : LiminalTheme.elevated.opacity(0.5))
        )
        .overlay(
            Rectangle()
                .strokeBorder(isToday ? LiminalTheme.accent : Color.clear, lineWidth: isToday ? 2 : 0)
        )
        .opacity(isInVisibleMonth ? 1 : 0.48)
    }

    private var dateNumberColor: Color {
        let weekday = Calendar.japanese.component(.weekday, from: date)
        if weekday == 1 {
            return .red
        }
        if weekday == 7 {
            return .blue
        }
        return LiminalTheme.text
    }

    private var labelHeight: CGFloat {
        max(9, CGFloat(labelConfiguration.titleFontSize) + 3)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }

}

private struct CalendarMonthPlanLabelConfiguration: Equatable {
    let timedPlanLabelStyle: CalendarPlanLabelStyle
    let allDayPlanLabelStyle: CalendarPlanLabelStyle
    let titleFontSize: Double
    let titleBold: Bool
    let dimPastPlans: Bool
    let strikePastPlans: Bool
}

private struct CalendarScoreBadge: View {
    let summary: CalendarDisplayScore

    var body: some View {
        ZStack {
            Circle()
                .stroke(scoreColor.opacity(summary.hasData ? 0.18 : 0.12), lineWidth: 2)

            if summary.hasData {
                Circle()
                    .trim(from: 0, to: scoreProgress)
                    .stroke(
                        scoreColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(accessibilityText)
    }

    private var scoreProgress: Double {
        if summary.kind == .sharedData {
            return 1
        }
        return min(max(summary.value / 100, 0), 1)
    }

    private var accessibilityText: String {
        guard summary.hasData else { return "スコアなし" }
        if summary.kind == .sharedData {
            return "共有データあり"
        }
        return "スコア \(Int(summary.value.rounded()))"
    }

    private var scoreColor: Color {
        if summary.kind == .sharedData {
            return LiminalTheme.accent
        }
        guard summary.hasData else {
            return .secondary
        }
        switch summary.value {
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
}

private struct CalendarImportantPlanLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let plan: CalendarDisplayPlan
    let date: Date
    let configuration: CalendarMonthPlanLabelConfiguration

    var body: some View {
        HStack(spacing: 1) {
            if let timePrefix {
                Text(timePrefix)
                    .font(.system(size: timeFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: timeColor)
            }

            clippedTitle
        }
            .padding(.horizontal, labelContentPadding)
            .offset(y: textVerticalOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: labelHeight)
            .background(backgroundShape)
            .overlay(borderShape)
            .padding(.horizontal, labelOuterInset)
            .padding(.leading, continuesFromPreviousDay ? -labelOuterInset : 0)
            .padding(.trailing, continuesToNextDay ? -labelOuterInset : 0)
            .opacity(labelOpacity)
            .accessibilityLabel("\(plan.title) 重要な予定")
    }

    private var clippedTitle: some View {
        Color.clear
            .overlay(alignment: .leading) {
                Text(plan.title)
                    .font(.system(size: displayTitleFontSize, weight: configuration.titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: titleColor)
            }
            .clipped()
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .fill(backgroundFillColor)
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .stroke(borderColor, lineWidth: 0.8)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(markerColor)
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
        }
    }

    private var color: Color {
        plan.color
    }

    private var labelStyle: CalendarPlanLabelStyle {
        plan.isAllDay ? configuration.allDayPlanLabelStyle : configuration.timedPlanLabelStyle
    }

    private var titleColor: Color {
        if labelStyle == .background {
            return .white
        }
        return color
    }

    private var timeColor: Color {
        if labelStyle == .background {
            return .white
        }
        return color
    }

    private var backgroundFillColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.82, alpha: 0.68)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.72 : 0.84
        )
    }

    private var borderColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.9, alpha: 0.84)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.98 : 0.96
        )
    }

    private var markerColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.86, alpha: 0.76)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 1 : 0.98
        )
    }

    private var labelOpacity: Double {
        usesLightPastDimStyle ? 1 : (isPastDimmed ? 0.38 : 1)
    }

    private var isPastDimmed: Bool {
        isPastPlan && configuration.dimPastPlans
    }

    private var usesLightPastDimStyle: Bool {
        colorScheme != .dark && isPastDimmed
    }

    private var timeFontSize: Double {
        max(4, displayTitleFontSize - 1)
    }

    private var labelContentPadding: CGFloat {
        labelStyle == .background ? 1.5 : 0.5
    }

    private var labelOuterInset: CGFloat {
        if labelStyle == .background {
            return 1.5
        }
        return isToday ? 2.5 : 0
    }

    private var isToday: Bool {
        Calendar.japanese.isDateInToday(date)
    }

    private var labelHeight: CGFloat {
        max(9, CGFloat(displayTitleFontSize) + 3)
    }

    private var markerHeight: CGFloat {
        max(2, CGFloat(displayTitleFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        max(0.5, CGFloat(displayTitleFontSize) * 0.05)
    }

    private var textVerticalOffset: CGFloat {
        labelStyle == .underline ? -max(0.5, CGFloat(displayTitleFontSize) * 0.1) : 0
    }

    private var displayTitleFontSize: Double {
        configuration.titleFontSize
    }

    private var isPastPlan: Bool {
        min(plan.endTime, dayEnd) <= Date()
    }

    private var shouldStrikePastPlan: Bool {
        isPastPlan && configuration.strikePastPlans
    }

    private var dayStart: Date {
        Calendar.japanese.startOfDay(for: date)
    }

    private var dayEnd: Date {
        Calendar.japanese.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var continuesFromPreviousDay: Bool {
        plan.startTime < dayStart
    }

    private var continuesToNextDay: Bool {
        plan.endTime > dayEnd
    }

    private var timePrefix: String? {
        if plan.isAllDay || continuesFromPreviousDay {
            return nil
        }
        return plan.startTime.shortTime
    }
}

private struct CalendarMultiDayPlanBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let plan: CalendarDisplayPlan
    let roundsLeading: Bool
    let roundsTrailing: Bool

    @AppStorage("calendarMultiDayPlanLabelStyle") private var multiDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var titleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var titleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        Color.clear
            .overlay {
                Text(plan.title)
                    .font(.system(size: displayTitleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(isPastPlan && strikePastPlans, color: titleColor)
                    .offset(y: textVerticalOffset)
            }
            .clipped()
            .background(backgroundShape)
            .overlay(decorationOverlay)
            .opacity(labelOpacity)
            .accessibilityLabel("\(plan.title) 複数日に跨る重要な予定")
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .fill(backgroundFillColor)
        }
    }

    @ViewBuilder
    private var decorationOverlay: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .stroke(borderColor, lineWidth: 0.8)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(markerColor)
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
                .offset(y: 0.5)
        }
    }

    private var labelStyle: CalendarPlanLabelStyle {
        CalendarPlanLabelStyle(rawValue: multiDayPlanLabelStyleRaw) ?? .background
    }

    private var color: Color {
        plan.color
    }

    private var titleColor: Color {
        if labelStyle == .background {
            return .white
        }
        return color
    }

    private var backgroundFillColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.82, alpha: 0.68)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.72 : 0.84
        )
    }

    private var borderColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.9, alpha: 0.84)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.98 : 0.96
        )
    }

    private var markerColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.86, alpha: 0.76)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 1 : 0.98
        )
    }

    private var labelOpacity: Double {
        usesLightPastDimStyle ? 1 : (isPastDimmed ? 0.38 : 1)
    }

    private var isPastDimmed: Bool {
        isPastPlan && dimPastPlans
    }

    private var usesLightPastDimStyle: Bool {
        colorScheme != .dark && isPastDimmed
    }

    private var markerHeight: CGFloat {
        max(2, CGFloat(displayTitleFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        0
    }

    private var textVerticalOffset: CGFloat {
        labelStyle == .underline ? -max(0.5, CGFloat(displayTitleFontSize) * 0.1) : 0
    }

    private var displayTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(titleFontSize)
    }

    private var isPastPlan: Bool {
        plan.endTime <= Date()
    }
}

private enum CalendarPlanColorRendering {
    static func surface(from color: Color, colorScheme: ColorScheme, intensity: CGFloat) -> Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        let source = UIColor(color).resolvedColor(with: traits)
        let base = LiminalThemeCatalog.resolvedDefinition(for: colorScheme).palette.surface

        return Color(uiColor: source.mixed(with: base, sourceAmount: intensity))
    }

    static func lightPastSurface(from color: Color, sourceAmount: CGFloat, alpha: CGFloat) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let source = UIColor(color).resolvedColor(with: traits)
        let darkened = source.mixed(with: .black, sourceAmount: sourceAmount)
        return Color(uiColor: darkened.withAlphaComponent(min(max(alpha, 0), 1)))
    }
}

private extension UIColor {
    func mixed(with base: UIColor, sourceAmount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha) else {
            return withAlphaComponent(1)
        }

        let clampedAmount = min(max(sourceAmount, 0), 1)
        let baseAmount = 1 - clampedAmount

        return UIColor(
            red: red * clampedAmount + baseRed * baseAmount,
            green: green * clampedAmount + baseGreen * baseAmount,
            blue: blue * clampedAmount + baseBlue * baseAmount,
            alpha: 1
        )
    }
}

private struct CalendarContinuationShape: Shape {
    let roundsLeading: Bool
    let roundsTrailing: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, 4)
        let leadingRadius = roundsLeading ? radius : 0
        let trailingRadius = roundsTrailing ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.minY))
        if trailingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + trailingRadius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailingRadius))
        if trailingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - trailingRadius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + leadingRadius, y: rect.maxY))
        if leadingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - leadingRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leadingRadius))
        if leadingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Calendar") {
    CalendarView()
        .liminalogPreviewEnvironment()
}

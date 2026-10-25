import SwiftUI
import SwiftData

/// 月表示の文脈を保ったまま、日間と共通の編集タイムラインを開く。
struct CalendarExpandedDayTimeline: View {
    @Environment(ChapterStore.self) private var store
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.createdAt)]) private var categories: [Category]
    @Query(sort: [SortDescriptor(\PlanPreset.sortOrder), SortDescriptor(\PlanPreset.createdAt)]) private var planPresets: [PlanPreset]
    @AppStorage("calendar.filter.usesCustomCategories") private var usesCustomFilter = false
    @AppStorage("calendar.filter.categoryIDs") private var storedCategoryIDs = ""
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = CalendarPlanTitleMetrics.defaultSize
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false

    let initialDate: Date
    @Binding var scrolledOffset: Int?
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool

    @State private var coordinator = TimelinePlanPresetInteractionCoordinator()
    @State private var showingPlanPresets = false
    @State private var showingPresetSettings = false
    @State private var showingCategoryEditor = false
    @State private var showingCategoryFilter = false
    @State private var pendingCreatedCategoryID: UUID?
    @State private var editingPlan: PlanBlock?
    private let pageOffsets = Array(-240...240)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                CalendarTimelineCategoryPalette(
                    categories: selectableCategories,
                    selectedCategoryID: $selectedCategoryID,
                    showsPresetEntry: true,
                    usesCustomFilter: usesCustomFilter,
                    onOpenPresets: { showingPlanPresets = true },
                    onOpenFilter: { showingCategoryFilter = true },
                    onCreateCategory: { showingCategoryEditor = true }
                )
                timelinePager
            }
            TimelinePlanPresetLibrary(
                presets: planPresets,
                categories: selectableCategories,
                onFixedTimeTap: coordinator.addFixedTimePreset,
                onDurationDragChanged: coordinator.updateDurationPreset,
                onDurationDrop: coordinator.finishDurationPreset,
                onDraggingChanged: coordinator.setDragging,
                launcherPlacement: .externalControl,
                isPresented: $showingPlanPresets,
                dayPresets: TimelineDayPresetConfiguration(date: currentDate),
                onManage: { showingPresetSettings = true }
            )
            .zIndex(100)
        }
        .sheet(item: $editingPlan) { plan in
            if plan.modelContext != nil && !plan.isDeleted { PlanCreateSheet(plan: plan) }
        }
        .sheet(isPresented: $showingPresetSettings) { CalendarSettingsSheet() }
        .sheet(isPresented: $showingCategoryEditor) {
            CategoryEditSheet(category: nil) { category in
                if usesCustomFilter {
                    storedCategoryIDs = visibleCategoryIDs.union([category.id])
                        .map(\.uuidString).sorted().joined(separator: ",")
                }
                selectedCategoryID = category.id
                pendingCreatedCategoryID = category.id
            }
        }
        .sheet(isPresented: $showingCategoryFilter) {
            NavigationStack {
                CalendarCategoryFilterList(
                    categories: categories,
                    isResetEnabled: usesCustomFilter,
                    isCategorySelected: { !usesCustomFilter || visibleCategoryIDs.contains($0.id) },
                    onToggleCategory: { category in
                        var ids = usesCustomFilter ? visibleCategoryIDs : Set(categories.map(\.id))
                        if ids.contains(category.id) { ids.remove(category.id) }
                        else { ids.insert(category.id) }
                        storedCategoryIDs = ids.map(\.uuidString).sorted().joined(separator: ",")
                        usesCustomFilter = true
                    },
                    onReset: { usesCustomFilter = false }
                )
                .navigationTitle("表示カテゴリ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { showingCategoryFilter = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { refreshRecurringPlans() }
        .onChange(of: scrolledOffset) { _, _ in refreshRecurringPlans() }
        .onChange(of: categories.map(\.id)) { _, ids in
            if let pendingCreatedCategoryID, ids.contains(pendingCreatedCategoryID) {
                selectedCategoryID = pendingCreatedCategoryID
                self.pendingCreatedCategoryID = nil
            }
        }
    }

    private var timelinePager: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(pageOffsets, id: \.self) { offset in
                        let isActive = offset == (scrolledOffset ?? 0)
                        CalendarExpandedDayTimelinePage(
                            date: pageDate(offset),
                            categories: selectableCategories,
                            planPresets: planPresets,
                            visibleCategoryIDs: usesCustomFilter ? visibleCategoryIDs : nil,
                            planTitleFontSize: CalendarPlanTitleMetrics.clamped(planTitleFontSize),
                            planTitleBold: planTitleBold,
                            isActive: isActive,
                            coordinator: coordinator,
                            visibleHour: $visibleHour,
                            selectedCategoryID: $selectedCategoryID,
                            isScheduleInteractionActive: $isScheduleInteractionActive,
                            onEditPlan: { editingPlan = $0 }
                        )
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(!isActive)
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledOffset, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .scrollDisabled(isScheduleInteractionActive)
            .frame(maxHeight: .infinity)
            .onAppear { scrollProxy.scrollTo(scrolledOffset ?? 0, anchor: .center) }
        }
    }

    private var visibleCategoryIDs: Set<UUID> {
        Set(storedCategoryIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private var selectableCategories: [Category] {
        usesCustomFilter ? categories.filter { visibleCategoryIDs.contains($0.id) } : categories
    }

    private var currentDate: Date { pageDate(scrolledOffset ?? 0) }

    private func pageDate(_ offset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: offset, to: initialDate) ?? initialDate
    }

    private func refreshRecurringPlans() {
        store.refreshRecurringPlans(from: currentDate,
            to: Calendar.japanese.date(byAdding: .day, value: 2, to: currentDate))
    }
}

private struct CalendarExpandedDayTimelinePage: View {
    @Query private var plans: [PlanBlock]
    let date: Date
    let categories: [Category]
    let planPresets: [PlanPreset]
    let visibleCategoryIDs: Set<UUID>?
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let isActive: Bool
    let coordinator: TimelinePlanPresetInteractionCoordinator
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onEditPlan: (PlanBlock) -> Void

    init(date: Date, categories: [Category], planPresets: [PlanPreset], visibleCategoryIDs: Set<UUID>?,
         planTitleFontSize: Double, planTitleBold: Bool, isActive: Bool,
         coordinator: TimelinePlanPresetInteractionCoordinator, visibleHour: Binding<Int>,
         selectedCategoryID: Binding<UUID?>, isScheduleInteractionActive: Binding<Bool>,
         onEditPlan: @escaping (PlanBlock) -> Void) {
        self.date = date
        self.categories = categories
        self.planPresets = planPresets
        self.visibleCategoryIDs = visibleCategoryIDs
        self.planTitleFontSize = planTitleFontSize
        self.planTitleBold = planTitleBold
        self.isActive = isActive
        self.coordinator = coordinator
        _visibleHour = visibleHour
        _selectedCategoryID = selectedCategoryID
        _isScheduleInteractionActive = isScheduleInteractionActive
        self.onEditPlan = onEditPlan
        let boundary = DayBoundary(date: date, calendar: .japanese)
        let start = boundary.dayStart
        let end = boundary.dayEnd
        // Only lazily visible days query their overlapping plans. Summary/score
        // views are unmounted while planning, rather than kept hidden underneath.
        _plans = Query(filter: #Predicate<PlanBlock> { $0.startTime < end && $0.endTime > start },
                       sort: [SortDescriptor(\.startTime)])
    }

    var body: some View {
        #if DEBUG || LIMINALOG_UI_TESTING
        let _ = CalendarExpandedDayDiagnostics.evaluated(date: date)
        #endif
        CalendarDayTimelineContainer(
            date: date, categories: categories, planPresets: planPresets,
            visibleCategoryIDs: visibleCategoryIDs, plans: plans,
            planTitleFontSize: planTitleFontSize, planTitleBold: planTitleBold,
            isInteractionEnabled: isActive, isPageSwipeActive: !isActive,
            presetInteractionCoordinator: coordinator,
            visibleHour: $visibleHour, selectedCategoryID: $selectedCategoryID,
            isScheduleInteractionActive: $isScheduleInteractionActive,
            onEditPlan: onEditPlan, onScheduleChanged: {}
        )
    }
}

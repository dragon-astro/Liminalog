import SwiftUI
import UIKit

private struct EditablePlanTimelineRenderItem: Identifiable {
    let plan: PlanBlock
    let interval: PlanTimelineInterval
    let slot: PlanTimelineLayoutSlot

    var id: UUID {
        plan.id
    }
}

private struct EditableTimelinePlanSignature: Hashable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let createdAt: Date
    let isAllDay: Bool
    let isMemo: Bool
    let categoryID: UUID?
}

private struct EditableTimelineRenderCacheKey: Hashable {
    let dayStart: Date
    let dayEnd: Date
    let visibleCategoryIDs: Set<UUID>?
    let plans: [EditableTimelinePlanSignature]
}

private struct EditableTimelineAxisCacheKey: Equatable {
    let renderCacheKey: EditableTimelineRenderCacheKey
    let hourHeight: CGFloat
}

private struct EditableTimelineRenderCache {
    let key: EditableTimelineRenderCacheKey
    let editablePlans: [PlanBlock]
    let editablePlansByID: [UUID: PlanBlock]
    let displayIntervals: [PlanTimelineInterval]
    let axisProfile: TimelineAxisProfile
    let renderItems: [EditablePlanTimelineRenderItem]
    let collisionIntervals: [PlanTimelineInterval]
    let visiblePlanIDs: Set<UUID>
}

private struct TimelinePresetPlacementDraft {
    let preset: PlanPreset
    let snapshot: PlanTemplateSnapshot
    let visualStartY: CGFloat

    var interval: PlanTimelineInterval {
        PlanTimelineInterval(
            id: preset.id,
            startMinute: snapshot.startMinute,
            endMinute: snapshot.endMinute
        )
    }
}

/// Gesture and viewport bookkeeping that does not affect rendered output.
///
/// Keeping these values outside SwiftUI observation prevents raw pointer and
/// scroll events from invalidating the entire 24-hour timeline. Rendered
/// state still changes at every real snap/zoom/selection step.
private final class EditableTimelineInteractionScratch {
    // A cache miss may be read many times before onChange commits the new axis.
    // Keep the committed @State cache intact for scroll-anchor restoration.
    var pendingRenderCache: EditableTimelineRenderCache?
    var latestScrollMinY: CGFloat = 0
    var pendingVisibleHour: Int?
    var timelineScrollIsActive = false
    var moveDragSession: TimelineAxisDragSession?
    var resizeDragSession: TimelineAxisDragSession?
    var axisCacheKey: EditableTimelineAxisCacheKey?
    var axisMap: TimelineAxisMap?
    var didWarnDuringScheduleGesture = false
    var lastMoveFeedbackMinute: Int?
    var lastResizeFeedbackMinute: Int?
    var lastPresetFeedbackMinute: Int?

    func cachedAxisMap(
        for key: EditableTimelineAxisCacheKey,
        make: () -> TimelineAxisMap
    ) -> TimelineAxisMap {
        if axisCacheKey == key, let axisMap {
            return axisMap
        }
        let newMap = make()
        axisCacheKey = key
        axisMap = newMap
        return newMap
    }

    func resetScheduleGesture() {
        moveDragSession = nil
        resizeDragSession = nil
        didWarnDuringScheduleGesture = false
        lastMoveFeedbackMinute = nil
        lastResizeFeedbackMinute = nil
        lastPresetFeedbackMinute = nil
    }
}

enum EditablePlanTimelineColorStyle: Equatable {
    case standalone
    case calendarGrid
}

struct EditablePlanTimelineView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var planPresetStore
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let plans: [PlanBlock]
    let categories: [Category]
    let planPresets: [PlanPreset]
    let visibleCategoryIDs: Set<UUID>?
    let isEditingEnabled: Bool
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let isInteractionEnabled: Bool
    let isPageSwipeActive: Bool
    let presetInteractionCoordinator: TimelinePlanPresetInteractionCoordinator?
    let presetExternalCoordinateSpaceName: String?
    /// 指定時は右下の起動ボタンを出さず、外（カテゴリ列のしおり）から開く。
    let presetDrawerPresentation: Binding<Bool>?
    let presetDayConfiguration: TimelineDayPresetConfiguration?
    let onPresetManage: (() -> Void)?
    let showsChrome: Bool
    let colorStyle: EditablePlanTimelineColorStyle
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onEditPlan: (PlanBlock) -> Void
    let onScheduleChanged: () -> Void
    private let renderCacheKey: EditableTimelineRenderCacheKey

    @State private var selectedPlanID: UUID?
    @State private var gesturePlanID: UUID?
    @State private var memoCreationDraft: TimelineMemoCreationDraft?
    @State private var dragIsMemo: Bool?
    @State private var pendingKindChange: PlanTimelineKindChange?
    @AppStorage(TimelineSnapPrecision.userDefaultsKey)
    private var storedSnapPrecisionMinutes = TimelineSnapPrecision.quarterHour.minutes
    @State private var draftIntervals: [PlanTimelineInterval]?
    @State private var gestureBaseline: [PlanTimelineInterval]?
    @State private var resizeInteractionAnchor: PlanTimelineInterval?
    @State private var activeResizeEdge: EditablePlanResizeEdge?
    @State private var creationDraft: PlanCreationDraft?
    @State private var creationGestureIsActive = false
    @State private var operationError: String?
    @State private var presetApplyRequest: PlanTemplateApplyRequest?
    @State private var planPendingDeletion: PlanBlock?
    @State private var renderCache: EditableTimelineRenderCache?
    @State private var interactionScratch = EditableTimelineInteractionScratch()
    @AppStorage(DayTimelineZoomPolicy.userDefaultsKey)
    private var storedHourScale = Double(DayTimelineZoomPolicy.defaultScale)
    @State private var transientHourScale: CGFloat?
    @State private var zoomGestureBaseScale: CGFloat?
    @State private var zoomAnchorMinute: CGFloat?
    @State private var zoomGestureIsActive = false
    @State private var scheduleGestureWasCancelledByZoom = false
    @State private var touchActionsWereCancelledByZoom = false
    @GestureState private var scheduleDragIsActive = false
    @State private var timelineScrollPosition = ScrollPosition()
    @State private var initialVisibleHour: Int?
    @State private var presetDragIsActive = false
    @State private var presetPlacementDraft: TimelinePresetPlacementDraft?
    @State private var presetWindowFrame: CGRect?
    @State private var presetTimelineContentFrameSource = TimelineWindowFrameSource()
    private let calendar = Calendar.japanese
    private let hourColumnWidth = TimelineHourAxisMetrics.columnWidth
    private let timelineTopInset: CGFloat = 30
    private let sideInset: CGFloat = 4
    private let bottomScrollPadding: CGFloat = 24
    private let creationSnapMinutes = 15
    private let creationLongPressDuration = 0.28
    private let creationLongPressMaximumDistance: CGFloat = 28
    private let creationHorizontalCancelDistance: CGFloat = 22
    private let creationVerticalIntentRatio: CGFloat = 0.8

    private var minimumDurationMinutes: Int {
        snapPrecision.minutes
    }

    private var snapPrecision: TimelineSnapPrecision {
        TimelineSnapPrecision.normalized(minutes: storedSnapPrecisionMinutes)
    }

    init(
        date: Date,
        plans: [PlanBlock],
        categories: [Category],
        planPresets: [PlanPreset],
        visibleCategoryIDs: Set<UUID>?,
        isEditingEnabled: Bool,
        planTitleFontSize: Double,
        planTitleBold: Bool,
        isInteractionEnabled: Bool,
        isPageSwipeActive: Bool,
        presetInteractionCoordinator: TimelinePlanPresetInteractionCoordinator? = nil,
        presetExternalCoordinateSpaceName: String? = nil,
        presetDrawerPresentation: Binding<Bool>? = nil,
        presetDayConfiguration: TimelineDayPresetConfiguration? = nil,
        onPresetManage: (() -> Void)? = nil,
        showsChrome: Bool,
        colorStyle: EditablePlanTimelineColorStyle,
        visibleHour: Binding<Int>,
        selectedCategoryID: Binding<UUID?>,
        isScheduleInteractionActive: Binding<Bool>,
        onEditPlan: @escaping (PlanBlock) -> Void,
        onScheduleChanged: @escaping () -> Void
    ) {
        self.date = date
        self.plans = plans
        self.categories = categories
        self.planPresets = planPresets
        self.visibleCategoryIDs = visibleCategoryIDs
        self.isEditingEnabled = isEditingEnabled
        self.planTitleFontSize = planTitleFontSize
        self.planTitleBold = planTitleBold
        self.isInteractionEnabled = isInteractionEnabled
        self.isPageSwipeActive = isPageSwipeActive
        self.presetInteractionCoordinator = presetInteractionCoordinator
        self.presetExternalCoordinateSpaceName = presetExternalCoordinateSpaceName
        self.presetDrawerPresentation = presetDrawerPresentation
        self.presetDayConfiguration = presetDayConfiguration
        self.onPresetManage = onPresetManage
        self.showsChrome = showsChrome
        self.colorStyle = colorStyle
        self._visibleHour = visibleHour
        self._initialVisibleHour = State(initialValue: visibleHour.wrappedValue)
        self._selectedCategoryID = selectedCategoryID
        self._isScheduleInteractionActive = isScheduleInteractionActive
        self.onEditPlan = onEditPlan
        self.onScheduleChanged = onScheduleChanged

        let calendar = Calendar.japanese
        let dayStart = DayBoundary.dayStart(for: date, calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        self.renderCacheKey = EditableTimelineRenderCacheKey(
            dayStart: dayStart,
            dayEnd: dayEnd,
            visibleCategoryIDs: visibleCategoryIDs,
            plans: plans.map {
                EditableTimelinePlanSignature(
                    id: $0.id,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    createdAt: $0.createdAt,
                    isAllDay: $0.isAllDay,
                    isMemo: $0.isMemo,
                    categoryID: $0.category?.id
                )
            }
        )
    }

    private var dayStart: Date {
        DayBoundary.dayStart(for: date, calendar: calendar)
    }

    private var hourScale: CGFloat {
        transientHourScale ?? DayTimelineZoomPolicy.normalizedScale(storedHourScale)
    }

    private var hourHeight: CGFloat {
        DayTimelineZoomPolicy.hourHeight(for: hourScale)
    }

    private var currentRenderCache: EditableTimelineRenderCache {
        if let renderCache, renderCache.key == renderCacheKey {
            return renderCache
        }
        if let pending = interactionScratch.pendingRenderCache, pending.key == renderCacheKey {
            return pending
        }
        let cache = makeRenderCache(for: renderCacheKey)
        interactionScratch.pendingRenderCache = cache
        return cache
    }

    private func makeRenderCache(for key: EditableTimelineRenderCacheKey) -> EditableTimelineRenderCache {
        let timelinePlans = plans
            .filter { !$0.isAllDay && $0.startTime < dayEnd && $0.endTime > dayStart }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.startTime < rhs.startTime
            }
        let editablePlans = timelinePlans.filter(isPlanVisible(_:))
        let displayIntervals = intervals(for: editablePlans)
        let axisProfile = TimelineAxisProfile(
            intervals: displayIntervals.map {
                TimelineAxisInterval(
                    startMinute: $0.startMinute,
                    endMinute: $0.endMinute
                )
            },
            minimumIntervalHeight: EditablePlanBlockMetrics.minimumReadableHeight
        )
        let slots = PlanTimelineLayoutSlot.makeSlots(for: displayIntervals)
        let editablePlansByID = Dictionary(uniqueKeysWithValues: editablePlans.map { ($0.id, $0) })
        let renderItems: [EditablePlanTimelineRenderItem] = displayIntervals.compactMap { interval in
            guard let plan = editablePlansByID[interval.id],
                  let slot = slots[interval.id]
            else { return nil }
            return EditablePlanTimelineRenderItem(plan: plan, interval: interval, slot: slot)
        }
        let collisionIntervals = timelinePlans.map {
            PlanTimelineInterval(
                id: $0.id,
                startMinute: minute(for: max($0.startTime, dayStart)),
                endMinute: minute(for: min($0.endTime, dayEnd)),
                isLocked: store.isPlanScheduleLocked($0) || !isPlanVisible($0), isMemo: $0.isMemo
            )
        }
        return EditableTimelineRenderCache(
            key: key,
            editablePlans: editablePlans,
            editablePlansByID: editablePlansByID,
            displayIntervals: displayIntervals,
            axisProfile: axisProfile,
            renderItems: renderItems,
            collisionIntervals: collisionIntervals,
            visiblePlanIDs: Set(editablePlans.map(\.id))
        )
    }

    private func refreshRenderCache() {
        let cache = renderCache?.key == renderCacheKey
            ? makeRenderCache(for: renderCacheKey) : currentRenderCache
        renderCache = cache
        interactionScratch.pendingRenderCache = nil
        resetSelectionIfHidden(visiblePlanIDs: cache.visiblePlanIDs)
    }

    private func refreshRenderCache(
        from oldKey: EditableTimelineRenderCacheKey,
        viewportHeight: CGFloat
    ) {
        let oldCache = renderCache?.key == oldKey ? renderCache : nil
        let oldAxis = oldCache.map { makeAxisMap(cache: $0, hourHeight: hourHeight) }
        let scrollY = max(0, -interactionScratch.latestScrollMinY)
        let centerMinute = oldAxis?.minute(
            atY: scrollY + viewportHeight / 2 - timelineTopInset
        )

        let newCache = currentRenderCache
        renderCache = newCache
        interactionScratch.pendingRenderCache = nil
        resetSelectionIfHidden(visiblePlanIDs: newCache.visiblePlanIDs)

        // Home loads plans after constructing this view. Initial layout must win
        // over center preservation until its requested offset has actually appeared.
        if initialVisibleHour != nil {
            scrollToVisibleHour()
            return
        }
        guard let centerMinute else { return }
        let newAxis = makeAxisMap(cache: newCache, hourHeight: hourHeight)
        let contentHeight = timelineTopInset + newAxis.contentHeight + bottomScrollPadding
        let maximumScrollY = max(0, contentHeight - viewportHeight)
        let targetY = min(
            maximumScrollY,
            max(0, timelineTopInset + newAxis.y(forMinute: centerMinute) - viewportHeight / 2)
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineScrollPosition.scrollTo(y: targetY)
        }
        interactionScratch.latestScrollMinY = -targetY
    }

    private func makeAxisMap(
        cache: EditableTimelineRenderCache,
        hourHeight: CGFloat
    ) -> TimelineAxisMap {
        TimelineAxisMap(
            hourHeight: hourHeight,
            profile: cache.axisProfile
        )
    }

    private var timelineAxisMap: TimelineAxisMap {
        let cache = currentRenderCache
        let key = EditableTimelineAxisCacheKey(
            renderCacheKey: cache.key,
            hourHeight: hourHeight
        )
        return interactionScratch.cachedAxisMap(for: key) {
            makeAxisMap(cache: cache, hourHeight: hourHeight)
        }
    }

    private var dayEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    }

    private var selectedCategory: Category? {
        categories.first { $0.id == selectedCategoryID } ?? categories.first
    }

    private func displayedIntervals(using cache: EditableTimelineRenderCache) -> [PlanTimelineInterval] {
        guard let draftIntervals else {
            return cache.displayIntervals
        }
        return draftIntervals.filter { cache.visiblePlanIDs.contains($0.id) }
    }

    private func renderItems(using cache: EditableTimelineRenderCache) -> [EditablePlanTimelineRenderItem] {
        guard draftIntervals != nil else {
            return cache.renderItems
        }
        let intervals = displayedIntervals(using: cache)
        let slots = PlanTimelineLayoutSlot.makeSlots(for: intervals, overlayMainID: promotingPlanID)
        return intervals.compactMap { interval in
            guard let plan = cache.editablePlansByID[interval.id],
                  let slot = slots[interval.id]
            else { return nil }
            return EditablePlanTimelineRenderItem(plan: plan, interval: interval, slot: slot)
        }
    }

    var body: some View {
        timeline
        .sheet(item: $pendingKindChange) { change in
            PlanMemoPromotionSheet(request: PlanMemoPromotionRequest(changes: change.approval),
                title: change.plan.title, start: change.start, end: change.end,
                colorHex: change.plan.category?.colorHex, icon: change.plan.category?.icon) { mode in
                pendingKindChange = nil
                commitKindChange(change.plan, start: change.start, end: change.end, isMemo: false, approval: change.approval, mode: mode)
            }
        }
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
        }
        .onChange(of: categories.map(\.id)) { _, newIDs in
            if let selectedCategoryID, newIDs.contains(selectedCategoryID) {
                return
            }
            selectedCategoryID = categories.first?.id
        }
        .onAppear {
            refreshRenderCache()
        }
        .alert(
            "予定を削除しますか？",
            isPresented: deleteConfirmationPresented,
            presenting: planPendingDeletion
        ) { plan in
            Button("削除", role: .destructive) {
                deletePlan(plan)
            }
            Button("キャンセル", role: .cancel) {
                planPendingDeletion = nil
            }
        } message: { plan in
            Text("「\(plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title)」は元に戻せません。")
        }
        .alert("予定を調整できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
        .background(PlanTemplateApplyConfirmationPresenter(request: $presetApplyRequest, store: store).frame(width: 0, height: 0))
    }

    private var timeline: some View {
        GeometryReader { proxy in
            let cache = currentRenderCache
            let renderItemsSnapshot = renderItems(using: cache)
            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            timelineCanvasLayer(width: proxy.size.width, renderItems: renderItemsSnapshot)

                            if isInteractionEnabled, let creationDraft {
                                creationDraftView(draft: creationDraft, width: proxy.size.width)
                                creationTimeGuide(draft: creationDraft, width: proxy.size.width)
                            }

                            ForEach(renderItemsSnapshot) { item in
                                planBlock(
                                    plan: item.plan,
                                    interval: item.interval,
                                    slot: item.slot,
                                    width: proxy.size.width, globalMinX: proxy.frame(in: .global).minX
                                )
                            }

                            if let draft = memoCreationDraft {
                                creationTimeGuide(draft: PlanCreationDraft(startMinute: draft.startMinute, endMinute: draft.endMinute),
                                    width: proxy.size.width)
                                TimelineMemoCreationCard(title: selectedCategory?.name ?? "予定メモ",
                                    start: date(forMinute: draft.startMinute), end: date(forMinute: draft.endMinute),
                                    color: selectedCategory?.displayColor ?? LiminalTheme.accent)
                                    .frame(width: availableBlockWidth(proxy.size.width) * 0.48,
                                        height: max(1, timelineAxisMap.height(startMinute: draft.startMinute, endMinute: draft.endMinute)))
                                    .offset(x: hourColumnWidth + sideInset + availableBlockWidth(proxy.size.width) * 0.52,
                                        y: yOffset(for: draft.startMinute))
                                    .zIndex(30)
                            }
                            if isInteractionEnabled {
                                moveTimeGuide(width: proxy.size.width)

                                resizeTimeGuide(width: proxy.size.width)

                                resizeInteractionLayer(width: proxy.size.width, renderItems: renderItemsSnapshot)

                                if currentMinuteForDisplayedDay != nil {
                                    currentTimeLine(width: proxy.size.width)
                                }

                            }
                        }
                        .frame(height: timelineHeight)
                        .background {
                            TimelineWindowFrameReader(
                                frameSource: presetTimelineContentFrameSource
                            )
                        }
                        .contentShape(Rectangle())

                        Color.clear
                            .frame(height: bottomScrollPadding)
                    }
                }
                .scrollPosition($timelineScrollPosition)
                .defaultScrollAnchor(initialScrollAnchor(viewportHeight: proxy.size.height), for: .initialOffset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(alignment: .top) {
                    if let kind = dragIsMemo ?? presetPlacementDraft?.snapshot.isMemo { TimelineKindDragHint(isMemo: kind).allowsHitTesting(false) }
                }
                .scrollDisabled(shouldDisableTimelineScroll || isPageSwipeActive)
                .scrollIndicators(.visible)
                .background {
                    if showsChrome {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(timelineBackground)
                    } else {
                        Rectangle()
                            .fill(timelineBackground)
                    }
                }
                .overlay {
                    if showsChrome {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(timelineOuterStroke, lineWidth: 1)
                    }
                }
                .onAppear {
                    normalizeStoredHourScale()
                    scrollToVisibleHour()
                }
                .onChange(of: visibleHour) { _, newHour in
                    guard !isInteractionEnabled else { return }
                    if initialVisibleHour != nil { initialVisibleHour = newHour }
                    scrollToVisibleHour()
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    -max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, minY in
                    interactionScratch.latestScrollMinY = minY
                    updateVisibleHour(fromScrollMinY: minY, viewportHeight: proxy.size.height)
                }
                .onScrollPhaseChange { _, newPhase in
                    handleTimelineScrollPhaseChange(newPhase)
                }
                .onChange(of: date) { _, _ in
                    cancelZoomGesture()
                    resetInteractionState()
                    initialVisibleHour = visibleHour
                    scrollToVisibleHour()
                }
                .onChange(of: renderCacheKey) { oldKey, _ in
                    refreshRenderCache(
                        from: oldKey,
                        viewportHeight: proxy.size.height
                    )
                }
                .onChange(of: scheduleDragIsActive) { wasActive, isActive in
                    guard wasActive, !isActive else { return }
                    discardZoomCancelledScheduleGestureIfNeeded()
                }
                .gesture(
                    TimelineTouchSequenceObserver(onSequenceBegan: {
                        beginTimelineTouchSequence()
                    })
                )
                .simultaneousGesture(dayTimelineZoomGesture(viewportHeight: proxy.size.height))
                .accessibilityIdentifier("day-timeline")
                .accessibilityValue(zoomAccessibilityValue)

                if isInteractionEnabled, let presetPlacementDraft {
                    ZStack(alignment: .topLeading) {
                        presetPlacementDraftView(
                            draft: presetPlacementDraft,
                            width: proxy.size.width
                        )
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                    .zIndex(90)
                }

                if isInteractionEnabled,
                   presetInteractionCoordinator == nil {
                    TimelinePlanPresetLibrary(
                        presets: planPresets,
                        categories: categories,
                        onFixedTimeTap: addFixedTimePreset,
                        onDurationDragChanged: { preset, location in
                            updateDurationPresetPreview(
                                preset,
                                at: localPresetLocation(location),
                                viewportSize: proxy.size
                            )
                        },
                        onDurationDrop: { preset, location in
                            finishDurationPresetDrop(
                                preset,
                                at: localPresetLocation(location),
                                viewportSize: proxy.size
                            )
                        },
                        onDraggingChanged: { active in
                            presetDragIsActive = active
                            isScheduleInteractionActive = active
                            if !active, presetPlacementDraft != nil {
                                presetPlacementDraft = nil
                                interactionScratch.lastPresetFeedbackMinute = nil
                            }
                        },
                        launcherPlacement: presetDrawerPresentation == nil ? .bottomTrailing : .externalControl,
                        isPresented: presetDrawerPresentation,
                        dayPresets: presetDayConfiguration,
                        onManage: onPresetManage
                    )
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .bottomTrailing
                    )
                }
            }
            .background {
                TimelineWindowFrameReader { frame in
                    if presetWindowFrame != frame {
                        presetWindowFrame = frame
                    }
                }
            }
            .coordinateSpace(name: presetCoordinateSpaceName)
            .onAppear {
                updatePresetInteractionTarget(
                    frame: presetExternalFrame(in: proxy),
                    viewportSize: proxy.size
                )
            }
            .onChange(of: isInteractionEnabled) { _, _ in
                updatePresetInteractionTarget(
                    frame: presetExternalFrame(in: proxy),
                    viewportSize: proxy.size
                )
            }
            .onChange(of: proxy.size) { _, _ in
                updatePresetInteractionTarget(
                    frame: presetExternalFrame(in: proxy),
                    viewportSize: proxy.size
                )
            }
            .onChange(of: presetWindowFrame) { _, frame in
                updatePresetInteractionTarget(
                    frame: frame,
                    viewportSize: proxy.size
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            presetInteractionCoordinator?.deactivate(targetID: presetInteractionTargetID)
            cancelZoomGesture()
            if hasActiveScheduleGesture || scheduleGestureWasCancelledByZoom {
                scheduleGestureWasCancelledByZoom = false
                creationDraft = nil
                resetScheduleGestureState()
            }
            touchActionsWereCancelledByZoom = false
        }
    }

    private func scrollToVisibleHour() {
        let targetHour = min(23, max(0, initialVisibleHour ?? visibleHour))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineScrollPosition.scrollTo(y: yOffset(for: targetHour * 60))
        }
    }

    private func initialScrollAnchor(viewportHeight: CGFloat) -> UnitPoint? {
        guard let hour = initialVisibleHour else { return nil }
        let maximumY = max(0, timelineHeight + bottomScrollPadding - viewportHeight)
        return UnitPoint(x: 0, y: maximumY > 0 ? min(1, yOffset(for: min(23, max(0, hour)) * 60) / maximumY) : 0)
    }

    private func updateVisibleHour(fromScrollMinY minY: CGFloat, viewportHeight: CGFloat) {
        // Geometry can report zero before layout applies the requested position.
        // Confirm the actual offset, not merely that scrollTo has been called.
        if let hour = initialVisibleHour {
            let targetY = min(max(0, timelineHeight + bottomScrollPadding - viewportHeight),
                              yOffset(for: min(23, max(0, hour)) * 60))
            guard abs(max(0, -minY) - targetY) <= 1 else { return }
            initialVisibleHour = nil
        }
        guard isInteractionEnabled,
              !isPageSwipeActive,
              !shouldDisableTimelineScroll
        else { return }

        updateVisibleHour(scrollY: max(0, -minY), axisMap: timelineAxisMap)
    }

    private func updateVisibleHour(scrollY: CGFloat, axisMap: TimelineAxisMap) {
        let minute = axisMap.minute(atY: max(0, scrollY - timelineTopInset))
        let hour = min(23, max(0, Int((minute / 60).rounded())))
        if interactionScratch.timelineScrollIsActive {
            interactionScratch.pendingVisibleHour = hour
            return
        }
        commitVisibleHour(hour)
    }

    private func handleTimelineScrollPhaseChange(_ phase: ScrollPhase) {
        if phase == .tracking || phase == .interacting { initialVisibleHour = nil }
        interactionScratch.timelineScrollIsActive = phase != .idle
        guard phase == .idle,
              let pendingVisibleHour = interactionScratch.pendingVisibleHour
        else { return }
        interactionScratch.pendingVisibleHour = nil
        commitVisibleHour(pendingVisibleHour)
    }

    private func commitVisibleHour(_ hour: Int) {
        if visibleHour != hour {
            visibleHour = hour
        }
    }

    private func dayTimelineZoomGesture(viewportHeight: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard beginZoomGestureIfNeeded(viewportHeight: viewportHeight),
                      let zoomGestureBaseScale
                else { return }

                let scale = DayTimelineZoomPolicy.magnifiedScale(
                    baseScale: zoomGestureBaseScale,
                    magnification: value.magnification
                )
                applyZoomScale(scale, viewportHeight: viewportHeight)
            }
            .onEnded { _ in
                finishZoomGesture(viewportHeight: viewportHeight)
            }
    }

    private func beginZoomGestureIfNeeded(viewportHeight: CGFloat) -> Bool {
        if zoomGestureIsActive {
            return true
        }
        guard isInteractionEnabled,
              !isPageSwipeActive,
              viewportHeight > 0
        else { return false }

        // A selected plan or resize handle can receive the first finger before
        // the magnification recognizer sees the second one. Once a real
        // two-finger magnification starts, discard that uncommitted one-finger
        // draft and let zoom own the interaction. Keep a latch until the old
        // recognizer ends so its remaining finger cannot resume and save.
        if hasActiveScheduleGesture {
            scheduleGestureWasCancelledByZoom = true
            creationDraft = nil
            resetScheduleGestureState()
        } else if isScheduleInteractionActive && !scheduleGestureWasCancelledByZoom {
            // Calendar pages share the parent lock. Never clear or steal an
            // interaction that belongs to a sibling timeline instance.
            return false
        }
        touchActionsWereCancelledByZoom = true

        let baseScale = DayTimelineZoomPolicy.normalizedScale(storedHourScale)
        zoomGestureBaseScale = baseScale
        let baseAxis = makeAxisMap(
            cache: currentRenderCache,
            hourHeight: DayTimelineZoomPolicy.hourHeight(for: baseScale)
        )
        let scrollY = max(0, -interactionScratch.latestScrollMinY)
        zoomAnchorMinute = baseAxis.minute(
            atY: scrollY + viewportHeight / 2 - timelineTopInset
        )
        zoomGestureIsActive = true
        isScheduleInteractionActive = true
        return true
    }

    @discardableResult
    private func applyZoomScale(_ scale: CGFloat, viewportHeight: CGFloat) -> CGFloat? {
        guard let zoomAnchorMinute else { return nil }

        let newHourHeight = DayTimelineZoomPolicy.hourHeight(for: scale)
        let newAxis = makeAxisMap(cache: currentRenderCache, hourHeight: newHourHeight)
        let newContentHeight = timelineTopInset + newAxis.contentHeight + bottomScrollPadding
        let maximumScrollY = max(0, newContentHeight - viewportHeight)
        let targetY = min(
            maximumScrollY,
            max(
                0,
                timelineTopInset + newAxis.y(forMinute: zoomAnchorMinute) - viewportHeight / 2
            )
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transientHourScale = scale
            timelineScrollPosition.scrollTo(y: targetY)
        }
        interactionScratch.latestScrollMinY = -targetY
        return targetY
    }

    private func finishZoomGesture(viewportHeight: CGFloat) {
        guard zoomGestureIsActive else { return }

        let snappedScale = DayTimelineZoomPolicy.snappedScale(
            transientHourScale ?? zoomGestureBaseScale ?? DayTimelineZoomPolicy.defaultScale
        )
        let targetY = applyZoomScale(snappedScale, viewportHeight: viewportHeight)
        let snappedHourHeight = DayTimelineZoomPolicy.hourHeight(for: snappedScale)
        let snappedAxis = makeAxisMap(
            cache: currentRenderCache,
            hourHeight: snappedHourHeight
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            storedHourScale = Double(snappedScale)
            transientHourScale = nil
            zoomGestureBaseScale = nil
            zoomAnchorMinute = nil
            zoomGestureIsActive = false
        }
        isScheduleInteractionActive = hasActiveScheduleGesture || scheduleGestureWasCancelledByZoom
        if let targetY {
            updateVisibleHour(scrollY: targetY, axisMap: snappedAxis)
        }
        LiminalHaptics.selection()
    }

    private func cancelZoomGesture() {
        guard zoomGestureIsActive || transientHourScale != nil else { return }

        transientHourScale = nil
        zoomGestureBaseScale = nil
        zoomAnchorMinute = nil
        zoomGestureIsActive = false
        isScheduleInteractionActive = hasActiveScheduleGesture || scheduleGestureWasCancelledByZoom
    }

    private func normalizeStoredHourScale() {
        let normalized = DayTimelineZoomPolicy.normalizedScale(storedHourScale)
        if storedHourScale != Double(normalized) {
            storedHourScale = Double(normalized)
        }
    }

    private var zoomAccessibilityValue: String {
        let scale = hourScale
        if scale.rounded() == scale {
            return "\(Int(scale))倍"
        }
        return "\(String(format: "%.2g", Double(scale)))倍"
    }

    private func timelineCanvas(width: CGFloat) -> some View {
        DayTimelineGrid(
            axisMap: timelineAxisMap,
            topInset: timelineTopInset,
            contentHeight: timelineHeight,
            colorStyle: colorStyle
        )
        .frame(width: width, height: timelineHeight)
    }

    @ViewBuilder
    private func timelineCanvasLayer(width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) -> some View {
        let canvas = timelineCanvas(width: width)
        if isInteractionEnabled {
            canvas
                .overlay(alignment: .topLeading) {
                    TimelineCreationLongPressOverlay(
                        minimumDuration: creationLongPressDuration,
                        maximumStationaryDistance: creationLongPressMaximumDistance,
                        onChanged: { startLocation, location in
                            handleCreationLongPressChanged(
                                startLocation: startLocation,
                                location: location,
                                width: width,
                                renderItems: renderItems
                            )
                        },
                        onEnded: { startLocation, location, completed in
                            finishCreationLongPress(
                                startLocation: startLocation,
                                location: location,
                                completed: completed,
                                width: width,
                                renderItems: renderItems
                            )
                        },
                        onTap: { point in
                            clearSelectionIfNeeded(at: point, width: width, renderItems: renderItems)
                        }
                    )
                    .frame(width: width, height: timelineHeight)
                }
        } else {
            canvas
        }
    }

    @ViewBuilder
    private func currentTimeLine(width: CGFloat) -> some View {
        if let currentMinuteForDisplayedDay {
            let y = yOffset(for: currentMinuteForDisplayedDay)
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: hourColumnWidth - 4)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: max(0, width - hourColumnWidth), height: 1.5)
                    .offset(x: hourColumnWidth - 4)
            }
            .offset(y: y)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func planBlock(plan: PlanBlock, interval: PlanTimelineInterval, slot: PlanTimelineLayoutSlot, width: CGFloat, globalMinX: CGFloat) -> some View {
        let isSelected = selectedPlanID == plan.id
        let color = plan.category?.displayColor ?? LiminalTheme.accent
        let block = EditablePlanBlock(
            title: plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title,
            interval: interval,
            color: color,
            isSelected: isSelected,
            isLocked: store.isPlanScheduleLocked(plan),
            planTitleFontSize: planTitleFontSize,
            planTitleBold: planTitleBold,
            activeResizeEdge: isSelected ? activeResizeEdge : nil,
            onSelect: {
                handlePlanTap(plan)
            },
            onLongPress: { state, point in
                handlePlanLongPress(plan, state: state, point: point)
            },
            moveGesture: moveGesture(for: plan, width: width, globalMinX: globalMinX)
        )
        .withBlockHeight(height(for: interval))
        .frame(
            width: blockWidth(for: width, slot: slot),
            height: height(for: interval) + EditablePlanBlockMetrics.verticalOverflow * 2,
            alignment: .topLeading
        )
        .offset(
            x: blockXOffset(for: width, slot: slot),
            y: yOffset(for: interval.startMinute)
                - EditablePlanBlockMetrics.verticalOverflow
        )
        .opacity(isBehindPromotion(plan.id, interval: interval) ? 0.4 : 1)
        .zIndex(gesturePlanID == plan.id && dragIsMemo != nil ? 20 : interval.isMemo ? (isSelected ? 10 : 5) : (isSelected ? 3 : 1))
        .accessibilityIdentifier("day-plan-\(plan.id)")

        if isSelected && !store.isPlanScheduleLocked(plan) {
            let step = snapPrecision.minutes
            block
                .accessibilityAction(named: Text("\(step)分早める")) {
                    applyAccessibilityMove(plan: plan, minuteDelta: -step)
                }
                .accessibilityAction(named: Text("\(step)分遅らせる")) {
                    applyAccessibilityMove(plan: plan, minuteDelta: step)
                }
                .accessibilityAction(named: Text("開始を\(step)分早める")) {
                    applyAccessibilityResize(plan: plan, edge: .start, minuteDelta: -step)
                }
                .accessibilityAction(named: Text("開始を\(step)分遅らせる")) {
                    applyAccessibilityResize(plan: plan, edge: .start, minuteDelta: step)
                }
                .accessibilityAction(named: Text("終了を\(step)分早める")) {
                    applyAccessibilityResize(plan: plan, edge: .end, minuteDelta: -step)
                }
                .accessibilityAction(named: Text("終了を\(step)分遅らせる")) {
                    applyAccessibilityResize(plan: plan, edge: .end, minuteDelta: step)
                }
        } else {
            block
        }
    }

    private func handlePlanTap(_ plan: PlanBlock) {
        guard gesturePlanID == nil, memoCreationDraft == nil,
              !zoomGestureIsActive,
              !scheduleGestureWasCancelledByZoom,
              !touchActionsWereCancelledByZoom
        else { return }
        guard planPendingDeletion?.id != plan.id else { return }
        if selectedPlanID == plan.id {
            onEditPlan(plan)
        } else {
            LiminalHaptics.selection()
            selectedPlanID = plan.id
        }
    }

    @ViewBuilder
    private func creationDraftView(draft: PlanCreationDraft, width: CGFloat) -> some View {
        let color = selectedCategory?.displayColor ?? LiminalTheme.accent
        if draft.isMemo {
            TimelineMemoCreationCard(title: selectedCategory?.name ?? "予定メモ",
                start: date(forMinute: draft.startMinute), end: date(forMinute: draft.endMinute), color: color)
                .frame(width: availableBlockWidth(width) * 0.48, height: max(1, height(for: draft.interval)))
                .offset(x: hourColumnWidth + sideInset + availableBlockWidth(width) * 0.52,
                    y: yOffset(for: draft.startMinute))
                .zIndex(30)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(timeText(draft.startMinute))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(selectedCategory?.name ?? "予定")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: availableBlockWidth(width), height: max(1, height(for: draft.interval)), alignment: .topLeading)
            .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .clipped()
            .offset(x: hourColumnWidth + sideInset, y: yOffset(for: draft.startMinute))
            .allowsHitTesting(false)
        }
    }

    private func presetPlacementDraftView(
        draft: TimelinePresetPlacementDraft,
        width: CGFloat
    ) -> some View {
        let color = categories.first { $0.id == draft.snapshot.categoryID }?.displayColor
            ?? LiminalTheme.accent
        let blockHeight = height(for: draft.interval)

        return VStack(alignment: .leading, spacing: 3) {
            Text(timeText(draft.snapshot.startMinute))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .lineLimit(1)
            if blockHeight >= 28 {
                Text(draft.snapshot.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(draft.snapshot.isMemo ? color : .white)
        .padding(.horizontal, 8)
        .padding(.vertical, blockHeight < 24 ? 2 : 5)
        .frame(
            width: availableBlockWidth(width) * (draft.snapshot.isMemo ? 0.48 : 1),
            height: blockHeight,
            alignment: .topLeading
        )
        .background(draft.snapshot.isMemo ? Color(uiColor: .secondarySystemBackground) : color.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(draft.snapshot.isMemo ? color : .white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 2, dash: draft.snapshot.isMemo ? [4, 3] : []))
        }
        .shadow(color: color.opacity(0.22), radius: 5, y: 2)
        .offset(
            x: hourColumnWidth + sideInset + (draft.snapshot.isMemo ? availableBlockWidth(width) * 0.52 : 0),
            y: draft.visualStartY
        )
        .allowsHitTesting(false)
        .zIndex(90)
    }

    private func creationTimeGuide(draft: PlanCreationDraft, width: CGFloat) -> some View {
        let color = selectedCategory?.displayColor ?? LiminalTheme.accent
        return ZStack(alignment: .topLeading) {
            creationBoundaryLine(
                minute: draft.startMinute,
                label: timeText(draft.startMinute),
                color: color,
                width: width
            )

            creationBoundaryLine(
                minute: draft.endMinute,
                label: timeText(draft.endMinute),
                color: color,
                width: width
            )
        }
        .frame(width: width, height: timelineHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(88)
    }

    private func creationBoundaryLine(minute: Int, label: String, color: Color, width: CGFloat) -> some View {
        let y = yOffset(for: minute)
        let labelY = max(0, min(timelineHeight - 20, y - 10))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(0.72))
                .frame(width: max(0, width - hourColumnWidth - sideInset), height: 1.2)
                .offset(x: hourColumnWidth + sideInset, y: y)

            Text(label)
                .font(.system(size: 9.6, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.9))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .offset(x: hourColumnWidth + sideInset + 6, y: labelY)
        }
    }

    private func handleCreationLongPressChanged(
        startLocation: CGPoint,
        location: CGPoint,
        width: CGFloat,
        renderItems: [EditablePlanTimelineRenderItem]
    ) {
        guard gesturePlanID == nil, memoCreationDraft == nil else { return }

        guard !timelineTouchEditingIsBlocked else {
            cancelCreationGesture()
            return
        }
        guard isCreationDragDirection(startLocation: startLocation, location: location) else {
            cancelCreationGesture()
            return
        }
        if updateCreationDraft(startLocation: startLocation, location: location, width: width, renderItems: renderItems) {
            activateCreationGestureIfNeeded()
        }
    }

    private func finishCreationLongPress(
        startLocation: CGPoint,
        location: CGPoint,
        completed: Bool,
        width: CGFloat,
        renderItems: [EditablePlanTimelineRenderItem]
    ) {
        guard gesturePlanID == nil, memoCreationDraft == nil else { return }

        guard !discardZoomCancelledScheduleGestureIfNeeded() else { return }
        defer {
            creationDraft = nil
            resetScheduleGestureState()
        }
        guard !timelineTouchEditingIsBlocked,
              completed,
              isCreationDragDirection(startLocation: startLocation, location: location),
              updateCreationDraft(startLocation: startLocation, location: location, width: width, renderItems: renderItems, isFinal: true)
        else { return }
        commitCreationDraft()
    }

    @discardableResult
    private func updateCreationDraft(
        startLocation: CGPoint,
        location: CGPoint,
        width: CGFloat,
        renderItems: [EditablePlanTimelineRenderItem],
        isFinal: Bool = false
    ) -> Bool {
        guard gesturePlanID == nil, memoCreationDraft == nil else { return false }

        guard !timelineTouchEditingIsBlocked else {
            creationDraft = nil
            return false
        }
        guard startLocation.x > hourColumnWidth else {
            creationDraft = nil
            return false
        }
        guard !isExistingPlanHit(at: startLocation, width: width, renderItems: renderItems) else {
            creationDraft = nil
            return false
        }
        let start = snappedMinute(fromY: startLocation.y)
        let current = snappedMinute(fromY: location.y)
        // Locked days still allow free memo placement, including across main plans.
        let isMemo = !isEditingEnabled
        guard let range = clampedCreationRange(
            anchorMinute: start,
            currentMinute: current,
            intervals: isMemo ? [] : collisionIntervals,
            isFinal: isFinal
        ) else {
            creationDraft = nil
            return false
        }
        creationDraft = PlanCreationDraft(startMinute: range.start, endMinute: range.end, isMemo: isMemo)
        selectedPlanID = nil
        return true
    }

    private func isCreationDragDirection(startLocation: CGPoint, location: CGPoint) -> Bool {
        let horizontal = abs(location.x - startLocation.x)
        let vertical = abs(location.y - startLocation.y)
        return horizontal <= creationHorizontalCancelDistance || vertical >= horizontal * creationVerticalIntentRatio
    }

    private func activateCreationGestureIfNeeded() {
        guard !timelineTouchEditingIsBlocked, !creationGestureIsActive else { return }
        creationGestureIsActive = true
        markScheduleInteractionActive()
        LiminalHaptics.selection()
    }

    private func cancelCreationGesture() {
        creationDraft = nil
        creationGestureIsActive = false
        isScheduleInteractionActive = zoomGestureIsActive || scheduleGestureWasCancelledByZoom
    }

    private func clampedCreationRange(
        anchorMinute: Int,
        currentMinute: Int,
        intervals: [PlanTimelineInterval],
        isFinal: Bool
    ) -> (start: Int, end: Int)? {
        guard let range = PlanTimelineCreationPolicy.range(
            anchorMinute: anchorMinute,
            currentMinute: currentMinute,
            minimumDuration: minimumDurationMinutes,
            intervals: intervals,
            enforcesMinimumDuration: isFinal
        ) else { return nil }
        return (range.start, range.end)
    }

    private func commitCreationDraft() {
        guard let creationDraft else { return }
        defer {
            self.creationDraft = nil
        }
        guard !timelineTouchEditingIsBlocked,
              isEditingEnabled || creationDraft.isMemo,
              selectedCategory != nil
        else { return }
        let start = date(forMinute: creationDraft.startMinute)
        let end = date(forMinute: creationDraft.endMinute)
        guard creationDraft.isMemo || !store.hasTimedPlanOverlap(startTime: start, endTime: end) else {
            operationError = "既存の予定と重なっています。空いている時間をなぞってください。"
            LiminalHaptics.warning()
            return
        }
        guard let plan = store.createPlanBlock(
            category: selectedCategory,
            title: selectedCategory?.name ?? "予定",
            startTime: start,
            endTime: end,
            isAllDay: false,
            isMemo: creationDraft.isMemo,
            isPublic: !creationDraft.isMemo
        ) else {
            operationError = "予定を作成できませんでした。今日以前の日付や重なった時間は直接追加できません。"
            LiminalHaptics.warning()
            return
        }
        selectedPlanID = plan.id
        LiminalHaptics.commit()
        onScheduleChanged()
    }

    private func addFixedTimePreset(_ preset: PlanPreset) {
        guard let interval = preset.snapshot.interval(on: date, calendar: calendar) else {
            operationError = "プリセットの時刻を読み取れませんでした。"
            return
        }
        if let error = createPlan(from: preset, interval: interval) {
            operationError = error
            LiminalHaptics.warning()
        }
    }

    private func updateDurationPresetPreview(
        _ preset: PlanPreset,
        at location: CGPoint?,
        viewportSize: CGSize
    ) {
        guard let location,
              location.x >= 0,
              location.x <= viewportSize.width,
              location.y >= 0,
              location.y <= viewportSize.height
        else {
            return
        }

        guard let viewportFrame = presetWindowFrame,
              let contentFrame = presetTimelineContentFrameSource.currentFrame
        else {
            return
        }
        let estimatedBlockHeight = max(
            EditablePlanBlockMetrics.minimumReadableHeight,
            CGFloat(preset.snapshot.durationMinutes) / 60 * hourHeight
        )
        let proposedVisualStartY = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: location.y,
            cardHeight: estimatedBlockHeight,
            viewportHeight: viewportSize.height
        )
        let contentY = TimelinePlanPresetPlacementGeometry.axisY(
            windowFingerY: viewportFrame.minY + proposedVisualStartY,
            contentFrameMinY: contentFrame.minY,
            timelineTopInset: timelineTopInset
        )
        let rawMinute = Int(timelineAxisMap.minute(atY: contentY).rounded())
        let step = snapPrecision.minutes
        let snappedMinute = Int((Double(rawMinute) / Double(step)).rounded()) * step
        let maximumStartMinute = max(
            0,
            TimelineAxisMap.minutesPerDay - preset.snapshot.durationMinutes
        )
        guard let snapshot = TimelinePlanPresetPlacementGeometry.snapshot(preset.snapshot, placementMode: preset.placementMode,
            startMinute: min(maximumStartMinute, max(0, snappedMinute)),
            horizontalFraction: (location.x - hourColumnWidth - sideInset) / availableBlockWidth(viewportSize.width),
            currentIsMemo: presetPlacementDraft?.snapshot.isMemo ?? preset.isMemo) else {
            return
        }

        let previewInterval = PlanTimelineInterval(
            id: preset.id,
            startMinute: snapshot.startMinute,
            endMinute: snapshot.endMinute
        )
        let visualStartY = preset.placementMode == .fixedTime
            ? contentFrame.minY - viewportFrame.minY + yOffset(for: snapshot.startMinute)
            : TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: location.y,
            cardHeight: height(for: previewInterval),
            viewportHeight: viewportSize.height
        )

        if interactionScratch.lastPresetFeedbackMinute != snapshot.startMinute
            || presetPlacementDraft?.snapshot.isMemo != snapshot.isMemo {
            interactionScratch.lastPresetFeedbackMinute = snapshot.startMinute
            LiminalHaptics.selection()
        }
        if presetPlacementDraft?.snapshot != snapshot
            || presetPlacementDraft?.preset.id != preset.id
            || abs((presetPlacementDraft?.visualStartY ?? -.infinity) - visualStartY) > 0.25 {
            presetPlacementDraft = TimelinePresetPlacementDraft(
                preset: preset,
                snapshot: snapshot,
                visualStartY: visualStartY
            )
        }
    }

    private func finishDurationPresetDrop(
        _ preset: PlanPreset,
        at location: CGPoint?,
        viewportSize: CGSize
    ) -> String? {
        updateDurationPresetPreview(preset, at: location, viewportSize: viewportSize)
        defer {
            presetPlacementDraft = nil
            interactionScratch.lastPresetFeedbackMinute = nil
        }
        guard let draft = presetPlacementDraft,
              draft.preset.id == preset.id,
              let interval = draft.snapshot.interval(on: date, calendar: calendar)
        else {
            return "タイムライン上へ移動してから指を離してください。"
        }
        return createPlan(from: preset, snapshot: draft.snapshot, interval: interval)
    }

    private func createPlan(
        from preset: PlanPreset,
        snapshot: PlanTemplateSnapshot? = nil,
        interval: DateInterval
    ) -> String? {
        let source = snapshot ?? preset.snapshot
        guard (isEditingEnabled || source.isMemo),
              store.canCreatePlan(startTime: interval.start, isAllDay: source.isAllDay, isMemo: source.isMemo)
        else {
            return "この日には予定を追加できません。"
        }
        let category = categories.first { $0.id == source.categoryID }
        if !source.isAllDay && !source.isMemo && store.hasTimedPlanOverlap(startTime: interval.start, endTime: interval.end) {
            presetApplyRequest = PlanTemplateApplyRequest(
                applications: [.init(snapshot: source, resolvedCategory: category)], targetDate: date,
                onApplied: {
                    _ = planPresetStore.markUsed(preset)
                    onScheduleChanged()
                })
            return nil
        }
        guard let plan = store.createPlanBlock(
            category: category,
            title: source.title,
            startTime: interval.start,
            endTime: interval.end,
            isAllDay: source.isAllDay,
            isMemo: source.isMemo,
            isImportant: source.isImportant,
            note: source.note,
            isPublic: source.isPublic,
            beforeSave: { $0.reminderMinutesBefore = source.reminderMinutesBefore; return true }
        ) else {
            return "予定を追加できませんでした。"
        }
        selectedPlanID = plan.id
        _ = planPresetStore.markUsed(preset)
        LiminalHaptics.commit()
        onScheduleChanged()
        return nil
    }

    private var promotingPlanID: UUID? {
        guard dragIsMemo == false, let gesturePlanID,
              plans.first(where: { $0.id == gesturePlanID })?.isMemo == true else { return nil }
        return gesturePlanID
    }

    private func isBehindPromotion(_ id: UUID, interval: PlanTimelineInterval) -> Bool {
        guard !interval.isMemo, let targetID = promotingPlanID, id != targetID,
              let target = draftIntervals?.first(where: { $0.id == targetID }) else { return false }
        return interval.startMinute < target.endMinute && interval.endMinute > target.startMinute
    }

    private func handlePlanLongPress(_ plan: PlanBlock, state: UIGestureRecognizer.State, point: CGPoint) {
        if state == .began {
            guard !timelineTouchEditingIsBlocked, gesturePlanID == nil, memoCreationDraft == nil,
                  !creationGestureIsActive, pendingKindChange == nil else { return }
            if selectedPlanID == plan.id && !store.isPlanScheduleLocked(plan) {
                requestDeletePlan(plan)
                return
            }
            guard let frame = presetTimelineContentFrameSource.currentFrame else { return }
            let anchor = snappedMinute(fromY: point.y - frame.minY)
            memoCreationDraft = TimelineMemoCreationDraft(sourceID: plan.id, anchorMinute: anchor,
                minimumDuration: minimumDurationMinutes)
            markScheduleInteractionActive()
            LiminalHaptics.selection()
        } else if memoCreationDraft?.sourceID == plan.id {
            if state == .changed, let frame = presetTimelineContentFrameSource.currentFrame {
                memoCreationDraft?.extend(to: snappedMinute(fromY: point.y - frame.minY))
            } else if state == .ended {
                let draft = memoCreationDraft
                memoCreationDraft = nil
                resetScheduleGestureState()
                guard !timelineTouchEditingIsBlocked, let draft else { return }
                let category = selectedCategory ?? plan.category
                guard let memo = store.createPlanBlock(category: category, title: category?.name ?? "予定メモ",
                    startTime: date(forMinute: draft.committedRange.start), endTime: date(forMinute: draft.committedRange.end),
                    isMemo: true, isPublic: false) else { operationError = "予定メモを追加できませんでした。"; return }
                selectedPlanID = memo.id
                LiminalHaptics.commit(); onScheduleChanged()
            } else if state == .cancelled || state == .failed {
                memoCreationDraft = nil
                resetScheduleGestureState()
            }
        }
    }

    private func commitKindChange(_ plan: PlanBlock, start: Date, end: Date, isMemo: Bool,
                                  approval: [PlanMemoPromotionChange]? = nil, mode: PlanMemoPromotionMode = .keepRemainders) {
        if !isMemo && approval == nil {
            guard let changes = store.memoPromotionPreview(start: start, end: end, excluding: plan.id) else {
                operationError = "この日時にはメイン予定を置けません。"; return
            }
            if !changes.isEmpty {
                pendingKindChange = PlanTimelineKindChange(plan: plan, start: start, end: end, approval: changes)
                return
            }
        }
        guard store.savePlanPlacement(plan, start: start, end: end, isMemo: isMemo, approvedPromotion: approval, promotionMode: mode) else {
            operationError = "予定を切り替えられませんでした。"; return
        }
        LiminalHaptics.commit(); onScheduleChanged(); refreshRenderCache()
    }

    private func requestDeletePlan(_ plan: PlanBlock) {
        guard !zoomGestureIsActive,
              !scheduleGestureWasCancelledByZoom,
              !touchActionsWereCancelledByZoom,
              !store.isPlanScheduleLocked(plan),
              gestureBaseline == nil,
              activeResizeEdge == nil
        else { return }
        selectedPlanID = plan.id
        planPendingDeletion = plan
        LiminalHaptics.selection()
    }

    private func deletePlan(_ plan: PlanBlock) {
        guard !timelineTouchEditingIsBlocked else { return }
        guard store.deletePlanBlock(plan) else {
            operationError = "予定を削除できませんでした。時間をおいてもう一度試してください。"
            LiminalHaptics.failure()
            return
        }
        planPendingDeletion = nil
        selectedPlanID = nil
        resetScheduleGestureState()
        LiminalHaptics.commit()
        onScheduleChanged()
    }

    private func isExistingPlanHit(at point: CGPoint, width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) -> Bool {
        renderItems.contains { item in
            let x = blockXOffset(for: width, slot: item.slot)
            let y = yOffset(for: item.interval.startMinute)
            let blockWidth = blockWidth(for: width, slot: item.slot)
            let blockHeight = height(for: item.interval)
            let slop = EditablePlanBlockMetrics.creationHitSlop
            return point.x >= x - slop &&
                point.x <= x + blockWidth + slop &&
                point.y >= y - slop &&
                point.y <= y + blockHeight + slop
                || isSelectedResizeHandleHit(interval: item.interval, slot: item.slot, point: point, width: width)
        }
    }

    private func isSelectedResizeHandleHit(
        interval: PlanTimelineInterval,
        slot: PlanTimelineLayoutSlot,
        point: CGPoint,
        width: CGFloat
    ) -> Bool {
        guard interval.id == selectedPlanID else { return false }

        let blockWidth = blockWidth(for: width, slot: slot)
        let blockX = blockXOffset(for: width, slot: slot)
        let timelineMinX = hourColumnWidth + sideInset
        let timelineMaxX = width - sideInset
        let hitRegion = TimelineResizeHitPolicy.horizontalRegion(
            blockMinX: blockX,
            blockWidth: blockWidth,
            timelineMinX: timelineMinX,
            timelineMaxX: timelineMaxX,
            preferredGripWidth: EditablePlanBlockMetrics.resizeGripBackgroundWidth
        )
        let topY = yOffset(for: interval.startMinute) - EditablePlanBlockMetrics.resizeHitHandleHeight
        let bottomY = yOffset(for: interval.startMinute) + height(for: interval)
        return isPoint(
            point,
            insideX: hitRegion.minX,
            y: topY,
            width: hitRegion.width,
            height: EditablePlanBlockMetrics.resizeHitHandleHeight
        ) || isPoint(
            point,
            insideX: hitRegion.minX,
            y: bottomY,
            width: hitRegion.width,
            height: EditablePlanBlockMetrics.resizeHitHandleHeight
        )
    }

    private func isPoint(_ point: CGPoint, insideX x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Bool {
        point.x >= x &&
            point.x <= x + width &&
            point.y >= y &&
            point.y <= y + height
    }

    private func clearSelectionIfNeeded(at point: CGPoint, width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) {
        guard !zoomGestureIsActive,
              !scheduleGestureWasCancelledByZoom,
              !touchActionsWereCancelledByZoom
        else { return }
        guard gesturePlanID == nil, memoCreationDraft == nil, selectedPlanID != nil,
              !isExistingPlanHit(at: point, width: width, renderItems: renderItems)
        else { return }
        selectedPlanID = nil
        planPendingDeletion = nil
        LiminalHaptics.selection()
    }

    private func clearSelectionGesture(width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                clearSelectionIfNeeded(at: value.location, width: width, renderItems: renderItems)
            }
    }

    private func moveGesture(for plan: PlanBlock, width: CGFloat, globalMinX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($scheduleDragIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                guard memoCreationDraft == nil, gesturePlanID == nil || gesturePlanID == plan.id,
                      !timelineTouchEditingIsBlocked,
                      !store.isPlanScheduleLocked(plan)
                else { return }
                gesturePlanID = plan.id
                markScheduleInteractionActive()
                if selectedPlanID != plan.id {
                    selectedPlanID = plan.id
                }
                let baseline = gestureBaseline ?? collisionIntervals
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                }
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if interactionScratch.lastMoveFeedbackMinute == nil {
                    interactionScratch.lastMoveFeedbackMinute = original.startMinute
                    LiminalHaptics.selection()
                }
                var session = interactionScratch.moveDragSession ?? TimelineAxisDragSession(
                    startGlobalY: value.startLocation.y,
                    originalMinute: original.startMinute,
                    axisMap: timelineAxisMap
                )
                let previousDelta = session.minuteDelta
                let delta = session.update(
                    currentGlobalY: value.location.y,
                    precision: snapPrecision
                )
                interactionScratch.moveDragSession = session
                let nextMemo = PlanTimelineKindPolicy.memo(
                    atFraction: (value.location.x - globalMinX - hourColumnWidth - sideInset) / max(1, width - hourColumnWidth - sideInset * 2),
                    horizontalMovement: value.translation.width, current: dragIsMemo ?? plan.isMemo)
                let kindChanged = nextMemo != (dragIsMemo ?? plan.isMemo)
                dragIsMemo = nextMemo
                if kindChanged { LiminalHaptics.selection() }
                guard draftIntervals == nil || delta != previousDelta || kindChanged else { return }
                let alignedDelta = TimelineSnapPolicy.alignedDelta(
                    originalMinute: original.startMinute,
                    relativeDelta: delta,
                    precision: snapPrecision
                )
                let proposedStart = original.startMinute + alignedDelta
                let proposedEnd = original.endMinute + alignedDelta
                let direction: PlanTimelinePushDirection = alignedDelta >= 0 ? .later : .earlier
                if let interval = updateDraft(from: baseline, editingID: plan.id, start: proposedStart, end: proposedEnd, direction: direction, adjustment: .move, targetIsMemo: dragIsMemo) {
                    let appliedDelta = interval.startMinute - original.startMinute
                    if appliedDelta != alignedDelta {
                        session.saturate(currentGlobalY: value.location.y, appliedMinuteDelta: appliedDelta)
                        interactionScratch.moveDragSession = session
                    }
                    notifyMoveStepIfNeeded(interval.startMinute)
                }
            }
            .onEnded { _ in
                guard gesturePlanID == plan.id else { return }
                guard !discardZoomCancelledScheduleGestureIfNeeded() else { return }
                guard !timelineTouchEditingIsBlocked else {
                    resetScheduleGestureState()
                    return
                }
                finishScheduleGesture()
            }
    }

    private func startHandleGesture(for plan: PlanBlock) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($scheduleDragIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                guard memoCreationDraft == nil, gesturePlanID == nil || gesturePlanID == plan.id,
                      !timelineTouchEditingIsBlocked,
                      selectedPlanID == plan.id,
                      !store.isPlanScheduleLocked(plan)
                else { return }
                gesturePlanID = plan.id
                markScheduleInteractionActive()
                let baseline = gestureBaseline ?? collisionIntervals
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                    resizeInteractionAnchor = original
                    interactionScratch.lastResizeFeedbackMinute = original.startMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .start
                var session = interactionScratch.resizeDragSession ?? TimelineAxisDragSession(
                    startGlobalY: value.startLocation.y,
                    originalMinute: original.startMinute,
                    axisMap: timelineAxisMap
                )
                let previousDelta = session.minuteDelta
                let delta = session.update(
                    currentGlobalY: value.location.y,
                    precision: snapPrecision
                )
                interactionScratch.resizeDragSession = session
                guard draftIntervals == nil || delta != previousDelta else { return }
                let alignedDelta = TimelineSnapPolicy.alignedDelta(
                    originalMinute: original.startMinute,
                    relativeDelta: delta,
                    precision: snapPrecision
                )
                let resize = resizedInterval(from: original, edge: .start, delta: alignedDelta)
                if let interval = updateDraft(from: baseline, editingID: plan.id, start: resize.start, end: resize.end, direction: resize.direction, adjustment: .resizeStart) {
                    notifyResizeStepIfNeeded(interval.startMinute)
                }
            }
            .onEnded { _ in
                guard gesturePlanID == plan.id else { return }
                guard !discardZoomCancelledScheduleGestureIfNeeded() else { return }
                guard !timelineTouchEditingIsBlocked else {
                    resetScheduleGestureState()
                    return
                }
                finishScheduleGesture()
            }
    }

    private func endHandleGesture(for plan: PlanBlock) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($scheduleDragIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                guard memoCreationDraft == nil, gesturePlanID == nil || gesturePlanID == plan.id,
                      !timelineTouchEditingIsBlocked,
                      selectedPlanID == plan.id,
                      !store.isPlanScheduleLocked(plan)
                else { return }
                gesturePlanID = plan.id
                markScheduleInteractionActive()
                let baseline = gestureBaseline ?? collisionIntervals
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                    resizeInteractionAnchor = original
                    interactionScratch.lastResizeFeedbackMinute = original.endMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .end
                var session = interactionScratch.resizeDragSession ?? TimelineAxisDragSession(
                    startGlobalY: value.startLocation.y,
                    originalMinute: original.endMinute,
                    axisMap: timelineAxisMap
                )
                let previousDelta = session.minuteDelta
                let delta = session.update(
                    currentGlobalY: value.location.y,
                    precision: snapPrecision
                )
                interactionScratch.resizeDragSession = session
                guard draftIntervals == nil || delta != previousDelta else { return }
                let alignedDelta = TimelineSnapPolicy.alignedDelta(
                    originalMinute: original.endMinute,
                    relativeDelta: delta,
                    precision: snapPrecision
                )
                let resize = resizedInterval(from: original, edge: .end, delta: alignedDelta)
                if let interval = updateDraft(from: baseline, editingID: plan.id, start: resize.start, end: resize.end, direction: resize.direction, adjustment: .resizeEnd) {
                    notifyResizeStepIfNeeded(interval.endMinute)
                }
            }
            .onEnded { _ in
                guard gesturePlanID == plan.id else { return }
                guard !discardZoomCancelledScheduleGestureIfNeeded() else { return }
                guard !timelineTouchEditingIsBlocked else {
                    resetScheduleGestureState()
                    return
                }
                finishScheduleGesture()
            }
    }

    @ViewBuilder
    private func resizeInteractionLayer(width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) -> some View {
        if let selectedPlanID,
           let item = renderItems.first(where: { $0.plan.id == selectedPlanID }),
           !store.isPlanScheduleLocked(item.plan) {
            let plan = item.plan
            let currentInterval = interval(for: plan) ?? item.interval
            let slot = item.slot
            let anchor = resizeInteractionAnchor ?? currentInterval
            let blockWidth = blockWidth(for: width, slot: slot)
            let blockX = blockXOffset(for: width, slot: slot)
            let timelineMinX = hourColumnWidth + sideInset
            let timelineMaxX = width - sideInset
            let hitRegion = TimelineResizeHitPolicy.horizontalRegion(
                blockMinX: blockX,
                blockWidth: blockWidth,
                timelineMinX: timelineMinX,
                timelineMaxX: timelineMaxX,
                preferredGripWidth: EditablePlanBlockMetrics.resizeGripBackgroundWidth
            )
            let topY = yOffset(for: anchor.startMinute) - EditablePlanBlockMetrics.resizeHitHandleHeight
            let bottomY = yOffset(for: anchor.startMinute) + height(for: anchor)

            ZStack(alignment: .topLeading) {
                resizeHitHandle()
                    .frame(width: hitRegion.width)
                    .offset(x: hitRegion.minX, y: topY)
                    .highPriorityGesture(startHandleGesture(for: plan), including: .all)

                resizeHitHandle()
                    .frame(width: hitRegion.width)
                    .offset(x: hitRegion.minX, y: bottomY)
                    .highPriorityGesture(endHandleGesture(for: plan), including: .all)
            }
            .frame(width: width, height: timelineHeight, alignment: .topLeading)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private func resizeTimeGuide(width: CGFloat) -> some View {
        if let selectedPlanID,
           let activeResizeEdge,
           let plan = editablePlans.first(where: { $0.id == selectedPlanID }),
           !store.isPlanScheduleLocked(plan),
           let interval = interval(for: plan) {
            let minute = activeResizeEdge == .start ? interval.startMinute : interval.endMinute
            let y = yOffset(for: minute)
            let color = plan.category?.displayColor ?? LiminalTheme.accent
            let labelY = max(0, min(timelineHeight - 20, y - 11))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(0.92))
                    .frame(width: max(0, width - hourColumnWidth - sideInset), height: 1.5)
                    .offset(x: hourColumnWidth + sideInset, y: y)

                Text(timeText(minute))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.94))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
                    .offset(x: hourColumnWidth + sideInset + 6, y: labelY)
            }
            .frame(width: width, height: timelineHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(90)
        }
    }

    @ViewBuilder
    private func moveTimeGuide(width: CGFloat) -> some View {
        if activeResizeEdge == nil,
           gestureBaseline != nil,
           let selectedPlanID,
           let plan = editablePlans.first(where: { $0.id == selectedPlanID }),
           !store.isPlanScheduleLocked(plan),
           let interval = interval(for: plan) {
            let minute = interval.startMinute
            let y = yOffset(for: minute)
            let color = plan.category?.displayColor ?? LiminalTheme.accent
            let labelY = max(0, min(timelineHeight - 20, y - 11))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(0.82))
                    .frame(width: max(0, width - hourColumnWidth - sideInset), height: 1.3)
                    .offset(x: hourColumnWidth + sideInset, y: y)

                Text(timeText(minute) + "  " + ((dragIsMemo ?? plan.isMemo) ? "予定メモ →" : "← メイン予定"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.92))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 4, y: 1)
                    .offset(x: hourColumnWidth + sideInset + 6, y: labelY)
            }
            .frame(width: width, height: timelineHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(85)
        }
    }

    private func resizeHitHandle() -> some View {
        Color.white
            .opacity(0.001)
            .frame(height: EditablePlanBlockMetrics.resizeHitHandleHeight)
            .contentShape(Rectangle())
    }

    private func updateDraft(
        from baseline: [PlanTimelineInterval],
        editingID: UUID,
        start: Int,
        end: Int,
        direction: PlanTimelinePushDirection,
        adjustment: PlanTimelineAdjustment,
        targetIsMemo: Bool? = nil
    ) -> PlanTimelineInterval? {
        guard !timelineTouchEditingIsBlocked else { return nil }
        let effectiveMinimumDuration = adjustment == .move
            ? max(1, end - start)
            : minimumDurationMinutes
        guard let resolved = PlanTimelineKindPolicy.resolve(items: baseline, editingID: editingID,
            start: start, end: end, direction: direction, adjustment: adjustment,
            minimumDuration: effectiveMinimumDuration, targetIsMemo: targetIsMemo) else {
            warnOnceDuringScheduleGesture()
            return nil
        }
        if draftIntervals != resolved {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                draftIntervals = resolved
            }
        }
        return resolved.first { $0.id == editingID }
    }

    private func markScheduleInteractionActive() {
        guard !isScheduleInteractionActive else { return }
        isScheduleInteractionActive = true
    }

    private func notifyResizeStepIfNeeded(_ minute: Int) {
        guard interactionScratch.lastResizeFeedbackMinute != minute else { return }
        interactionScratch.lastResizeFeedbackMinute = minute
        LiminalHaptics.selection()
    }

    private func notifyMoveStepIfNeeded(_ minute: Int) {
        guard interactionScratch.lastMoveFeedbackMinute != minute else { return }
        interactionScratch.lastMoveFeedbackMinute = minute
        LiminalHaptics.selection()
    }

    private func resizedInterval(
        from original: PlanTimelineInterval,
        edge: EditablePlanResizeEdge,
        delta: Int
    ) -> (start: Int, end: Int, direction: PlanTimelinePushDirection, feedbackMinute: Int) {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: original.startMinute,
            originalEndMinute: original.endMinute,
            edge: edge.timelineEdge,
            delta: delta,
            minimumDuration: minimumDurationMinutes
        )
        return (result.startMinute, result.endMinute, result.pushDirection, result.feedbackMinute)
    }

    private func applyAccessibilityMove(plan: PlanBlock, minuteDelta: Int) {
        guard selectedPlanID == plan.id, !store.isPlanScheduleLocked(plan) else { return }
        let baseline = collisionIntervals
        guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
        let alignedDelta = TimelineSnapPolicy.alignedDelta(
            originalMinute: original.startMinute,
            relativeDelta: minuteDelta,
            precision: snapPrecision
        )
        saveResolvedSchedule(
            from: baseline,
            editingID: plan.id,
            start: original.startMinute + alignedDelta,
            end: original.endMinute + alignedDelta,
            direction: alignedDelta >= 0 ? .later : .earlier,
            failureMessage: "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
        )
    }

    private func applyAccessibilityResize(plan: PlanBlock, edge: EditablePlanResizeEdge, minuteDelta: Int) {
        guard selectedPlanID == plan.id, !store.isPlanScheduleLocked(plan) else { return }
        let baseline = collisionIntervals
        guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
        let originalMinute = edge == .start ? original.startMinute : original.endMinute
        let alignedDelta = TimelineSnapPolicy.alignedDelta(
            originalMinute: originalMinute,
            relativeDelta: minuteDelta,
            precision: snapPrecision
        )
        let resize = resizedInterval(from: original, edge: edge, delta: alignedDelta)
        saveResolvedSchedule(
            from: baseline,
            editingID: plan.id,
            start: resize.start,
            end: resize.end,
            direction: resize.direction,
            failureMessage: "予定の長さを変更できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
        )
    }

    private func saveResolvedSchedule(
        from baseline: [PlanTimelineInterval],
        editingID: UUID,
        start: Int,
        end: Int,
        direction: PlanTimelinePushDirection,
        failureMessage: String
    ) {
        guard let resolved = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: editingID,
            proposedStartMinute: start,
            proposedEndMinute: end,
            pushDirection: direction
        ) else {
            operationError = failureMessage
            LiminalHaptics.warning()
            return
        }
        let cache = currentRenderCache
        let currentByID = Dictionary(uniqueKeysWithValues: cache.displayIntervals.map { ($0.id, $0) })
        let changes = resolved.compactMap { interval -> PlanStore.ScheduleChange? in
            guard let current = currentByID[interval.id],
                  current.startMinute != interval.startMinute || current.endMinute != interval.endMinute,
                  let plan = cache.editablePlansByID[interval.id]
            else {
                return nil
            }
            return .init(
                plan: plan,
                startTime: date(forMinute: interval.startMinute),
                endTime: date(forMinute: interval.endMinute)
            )
        }
        guard !changes.isEmpty else { return }
        guard store.savePlanScheduleChanges(changes) else {
            operationError = failureMessage
            LiminalHaptics.warning()
            return
        }
        LiminalHaptics.commit()
        onScheduleChanged()
        refreshRenderCache()
    }

    private func finishScheduleGesture() {
        defer {
            resetScheduleGestureState()
        }
        guard !timelineTouchEditingIsBlocked else { return }
        guard let draftIntervals else { return }
        let cache = currentRenderCache
        if let gesturePlanID, let target = draftIntervals.first(where: { $0.id == gesturePlanID }),
           let plan = cache.editablePlansByID[gesturePlanID], target.isMemo != plan.isMemo {
            commitKindChange(plan, start: date(forMinute: target.startMinute), end: date(forMinute: target.endMinute), isMemo: target.isMemo)
            return
        }
        let currentByID = Dictionary(uniqueKeysWithValues: cache.displayIntervals.map { ($0.id, $0) })
        let changes = draftIntervals.compactMap { interval -> PlanStore.ScheduleChange? in
            guard let current = currentByID[interval.id],
                  current.startMinute != interval.startMinute || current.endMinute != interval.endMinute,
                  let plan = cache.editablePlansByID[interval.id]
            else {
                return nil
            }
            return .init(
                plan: plan,
                startTime: date(forMinute: interval.startMinute),
                endTime: date(forMinute: interval.endMinute)
            )
        }
        guard !changes.isEmpty else { return }
        guard store.savePlanScheduleChanges(changes) else {
            operationError = "予定を保存できませんでした。今日以前の予定や収まりきらない玉突き移動は変更できません。"
            LiminalHaptics.warning()
            return
        }
        LiminalHaptics.commit()
        onScheduleChanged()
        refreshRenderCache()
    }

    private func resetInteractionState() {
        selectedPlanID = nil
        planPendingDeletion = nil
        creationDraft = nil
        operationError = nil
        scheduleGestureWasCancelledByZoom = false
        touchActionsWereCancelledByZoom = false
        resetScheduleGestureState()
    }

    private func resetSelectionIfHidden(visiblePlanIDs: Set<UUID>) {
        guard let selectedPlanID, !visiblePlanIDs.contains(selectedPlanID) else { return }
        self.selectedPlanID = nil
        planPendingDeletion = nil
        creationDraft = nil
        resetScheduleGestureState()
    }

    private func resetScheduleGestureState() {
        creationGestureIsActive = false
        gestureBaseline = nil
        gesturePlanID = nil
        memoCreationDraft = nil
        dragIsMemo = nil
        draftIntervals = nil
        resizeInteractionAnchor = nil
        activeResizeEdge = nil
        interactionScratch.resetScheduleGesture()
        isScheduleInteractionActive = zoomGestureIsActive || scheduleGestureWasCancelledByZoom
    }

    @discardableResult
    private func discardZoomCancelledScheduleGestureIfNeeded() -> Bool {
        guard scheduleGestureWasCancelledByZoom || touchActionsWereCancelledByZoom else { return false }
        scheduleGestureWasCancelledByZoom = false
        creationDraft = nil
        resetScheduleGestureState()
        return true
    }

    private func beginTimelineTouchSequence() {
        guard !zoomGestureIsActive else { return }
        discardZoomCancelledScheduleGestureIfNeeded()
        touchActionsWereCancelledByZoom = false
    }

    private func warnOnceDuringScheduleGesture() {
        guard !interactionScratch.didWarnDuringScheduleGesture else { return }
        interactionScratch.didWarnDuringScheduleGesture = true
        LiminalHaptics.warning()
    }

    private func intervals(for plans: [PlanBlock]) -> [PlanTimelineInterval] {
        plans.map {
            PlanTimelineInterval(
                id: $0.id,
                startMinute: minute(for: max($0.startTime, dayStart)),
                endMinute: minute(for: min($0.endTime, dayEnd)),
                isLocked: store.isPlanScheduleLocked($0), isMemo: $0.isMemo
            )
        }
    }

    private var editablePlans: [PlanBlock] {
        currentRenderCache.editablePlans
    }

    private var collisionIntervals: [PlanTimelineInterval] {
        currentRenderCache.collisionIntervals
    }

    private func isPlanVisible(_ plan: PlanBlock) -> Bool {
        guard let visibleCategoryIDs else { return true }
        guard let categoryID = plan.category?.id else { return false }
        return visibleCategoryIDs.contains(categoryID)
    }

    private func interval(for plan: PlanBlock) -> PlanTimelineInterval? {
        return displayedIntervals(using: currentRenderCache).first { $0.id == plan.id }
    }

    private var timelineHeight: CGFloat {
        timelineTopInset + timelineAxisMap.contentHeight
    }

    private var presetCoordinateSpaceName: String {
        "day-plan-preset-\(date.timeIntervalSinceReferenceDate)"
    }

    private var presetInteractionTargetID: String {
        "day-target-\(date.timeIntervalSinceReferenceDate)"
    }

    private func localPresetLocation(_ location: CGPoint?) -> CGPoint? {
        guard let location, let frame = presetWindowFrame else { return nil }
        return CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
    }

    private func presetExternalFrame(in proxy: GeometryProxy) -> CGRect? {
        guard presetInteractionCoordinator != nil else { return nil }
        return presetWindowFrame
    }

    private func updatePresetInteractionTarget(frame: CGRect?, viewportSize: CGSize) {
        guard let coordinator = presetInteractionCoordinator else { return }
        guard isInteractionEnabled, let frame else {
            coordinator.deactivate(targetID: presetInteractionTargetID)
            return
        }

        coordinator.activate(
            targetID: presetInteractionTargetID,
            targetFrame: frame,
            onFixedTimeTap: addFixedTimePreset,
            onDurationDragChanged: { preset, location in
                updateDurationPresetPreview(
                    preset,
                    at: location,
                    viewportSize: viewportSize
                )
            },
            onDurationDrop: { preset, location in
                finishDurationPresetDrop(
                    preset,
                    at: location,
                    viewportSize: viewportSize
                )
            },
            onDraggingChanged: { active in
                presetDragIsActive = active
                isScheduleInteractionActive = active
                if !active, presetPlacementDraft != nil {
                    presetPlacementDraft = nil
                    interactionScratch.lastPresetFeedbackMinute = nil
                }
            }
        )
    }

    private var hasActiveScheduleGesture: Bool {
        memoCreationDraft != nil ||
            gesturePlanID != nil ||
            scheduleDragIsActive ||
            creationGestureIsActive ||
            creationDraft != nil ||
            gestureBaseline != nil ||
            draftIntervals != nil ||
            resizeInteractionAnchor != nil ||
            activeResizeEdge != nil
    }

    private var shouldDisableTimelineScroll: Bool {
        zoomGestureIsActive
            || scheduleGestureWasCancelledByZoom
            || hasActiveScheduleGesture
            || presetDragIsActive
    }

    private var timelineTouchEditingIsBlocked: Bool {
        zoomGestureIsActive ||
            scheduleGestureWasCancelledByZoom ||
            touchActionsWereCancelledByZoom
    }

    private var timelineBackground: Color {
        DayTimelineGridPalette(colorScheme: colorScheme, style: colorStyle).background
    }

    private var timelineOuterStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.12)
    }



    private var currentMinuteForDisplayedDay: Int? {
        guard calendar.isDateInToday(date) else { return nil }
        return minute(for: Date())
    }

    private func blockWidth(for totalWidth: CGFloat, slot: PlanTimelineLayoutSlot) -> CGFloat {
        let gap = CGFloat(max(slot.columnCount - 1, 0)) * 2
        let width = availableBlockWidth(totalWidth) * (slot.isMemo ? 0.48 : 1)
        return max(20, (width - gap) / CGFloat(slot.columnCount))
    }

    private func blockXOffset(for totalWidth: CGFloat, slot: PlanTimelineLayoutSlot) -> CGFloat {
        let columnWidth = blockWidth(for: totalWidth, slot: slot)
        return hourColumnWidth + sideInset + (slot.isMemo ? availableBlockWidth(totalWidth) * 0.52 : 0) + CGFloat(slot.column) * (columnWidth + 2)
    }

    private func availableBlockWidth(_ totalWidth: CGFloat) -> CGFloat {
        max(42, totalWidth - hourColumnWidth - sideInset * 2)
    }

    private func yOffset(for minute: Int) -> CGFloat {
        timelineTopInset + timelineAxisMap.y(forMinute: minute)
    }

    private func height(for interval: PlanTimelineInterval) -> CGFloat {
        timelineAxisMap.height(
            startMinute: interval.startMinute,
            endMinute: interval.endMinute
        )
    }

    private func snappedMinute(fromY y: CGFloat) -> Int {
        let raw = Int(timelineAxisMap.minute(atY: y - timelineTopInset).rounded())
        return min(
            PlanTimelineRescheduler.dayEndMinute,
            max(0, (raw / creationSnapMinutes) * creationSnapMinutes)
        )
    }

    private func minute(for date: Date) -> Int {
        let seconds = max(0, min(dayEnd.timeIntervalSince(dayStart), date.timeIntervalSince(dayStart)))
        return Int((seconds / 60).rounded())
    }

    private func date(forMinute minute: Int) -> Date {
        dayStart.addingTimeInterval(TimeInterval(minute * 60))
    }

    private func timeText(_ minute: Int) -> String {
        date(forMinute: minute).shortTime
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

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding {
            planPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                planPendingDeletion = nil
            }
        }
    }

}

struct TimelineTouchSequenceObserver: UIGestureRecognizerRepresentable {
    let onSequenceBegan: () -> Void

    func makeUIGestureRecognizer(context: Context) -> TimelineTouchSequenceRecognizer {
        let recognizer = TimelineTouchSequenceRecognizer(target: nil, action: nil)
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.onSequenceBegan = onSequenceBegan
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: TimelineTouchSequenceRecognizer, context: Context) {
        recognizer.onSequenceBegan = onSequenceBegan
    }
}

final class TimelineTouchSequenceRecognizer: UIGestureRecognizer {
    var onSequenceBegan: (() -> Void)?
    private var activeTouches: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let beginsNewSequence = activeTouches.isEmpty
        activeTouches.formUnion(touches)
        if beginsNewSequence {
            onSequenceBegan?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func reset() {
        super.reset()
        activeTouches.removeAll()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func finish(_ touches: Set<UITouch>) {
        activeTouches.subtract(touches)
        if activeTouches.isEmpty {
            state = .failed
        }
    }
}

struct TimelineCreationLongPressOverlay: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let maximumStationaryDistance: CGFloat
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint, CGPoint, Bool) -> Void
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = TimelineCreationTouchTrackingView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onTouchBegan = { [weak coordinator = context.coordinator] point in
            coordinator?.touchDownLocation = point
        }
        view.onTouchFinished = { [weak coordinator = context.coordinator] in
            coordinator?.touchDownLocation = nil
        }

        let longPressRecognizer = TimelinePresetLongPressRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = minimumDuration
        longPressRecognizer.allowableMovement = maximumStationaryDistance
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.delaysTouchesBegan = false
        longPressRecognizer.delaysTouchesEnded = false
        longPressRecognizer.numberOfTouchesRequired = 1
        longPressRecognizer.delegate = context.coordinator

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delaysTouchesBegan = false
        tapRecognizer.delaysTouchesEnded = false
        tapRecognizer.delegate = context.coordinator
        tapRecognizer.require(toFail: longPressRecognizer)

        context.coordinator.longPressRecognizer = longPressRecognizer
        view.addGestureRecognizer(longPressRecognizer)
        view.addGestureRecognizer(tapRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.longPressRecognizer?.minimumPressDuration = minimumDuration
        context.coordinator.longPressRecognizer?.allowableMovement = maximumStationaryDistance
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TimelineCreationLongPressOverlay
        weak var longPressRecognizer: UILongPressGestureRecognizer?
        var touchDownLocation: CGPoint?
        private var startLocation: CGPoint?

        init(parent: TimelineCreationLongPressOverlay) {
            self.parent = parent
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                let start = touchDownLocation ?? location
                startLocation = start
                parent.onChanged(start, location)
            case .changed:
                guard let startLocation else { return }
                parent.onChanged(startLocation, location)
            case .ended:
                let start = startLocation ?? location
                startLocation = nil
                touchDownLocation = nil
                parent.onEnded(start, location, true)
            case .cancelled, .failed:
                let start = startLocation ?? location
                startLocation = nil
                touchDownLocation = nil
                parent.onEnded(start, location, false)
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap(recognizer.location(in: recognizer.view))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer !== longPressRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === longPressRecognizer else { return false }
            return TimelinePlanPresetLongPressDragSurface.Coordinator.hasPriority(
                over: otherGestureRecognizer, drag: gestureRecognizer)
        }
    }
}

private final class TimelineCreationTouchTrackingView: UIView {
    var onTouchBegan: ((CGPoint) -> Void)?
    var onTouchFinished: (() -> Void)?
    private weak var primaryTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if primaryTouch == nil, let touch = touches.first {
            primaryTouch = touch
            onTouchBegan?(touch.location(in: self))
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        finishPrimaryTouchIfNeeded(in: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        finishPrimaryTouchIfNeeded(in: touches)
    }

    private func finishPrimaryTouchIfNeeded(in touches: Set<UITouch>) {
        guard let primaryTouch, touches.contains(primaryTouch) else { return }
        self.primaryTouch = nil
        onTouchFinished?()
    }
}

private struct PlanCreationDraft {
    let startMinute: Int
    let endMinute: Int
    var isMemo = false

    var interval: PlanTimelineInterval {
        PlanTimelineInterval(id: UUID(), startMinute: startMinute, endMinute: endMinute, isMemo: isMemo)
    }
}


enum EditablePlanBlockMetrics {
    static let minimumReadableHeight: CGFloat = 18
    static let verticalOverflow: CGFloat = 34
    static let resizeHandleHeight: CGFloat = 40
    static let resizeHitHandleHeight: CGFloat = 38
    static let resizeHandleEdgeOutset: CGFloat = 6
    static let resizeHandleEdgeOverlap: CGFloat = 0
    static let creationHitSlop: CGFloat = 6
    static let resizeGripBackgroundWidth: CGFloat = 70
    static let resizeGripBackgroundHeight: CGFloat = 19
    static let resizeGripWidth: CGFloat = 54
    static let resizeGripHeight: CGFloat = 5.5
}

enum EditablePlanResizeEdge: Equatable {
    case start
    case end

    var timelineEdge: PlanTimelineResizeEdge {
        switch self {
        case .start:
            return .start
        case .end:
            return .end
        }
    }
}

struct EditablePlanBlock<MoveGesture: Gesture>: View {
    let title: String
    let interval: PlanTimelineInterval
    let color: Color
    let isSelected: Bool
    let isLocked: Bool
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let activeResizeEdge: EditablePlanResizeEdge?
    var blockHeight: CGFloat = 26
    let onSelect: () -> Void
    let onLongPress: (UIGestureRecognizer.State, CGPoint) -> Void
    let moveGesture: MoveGesture

    var body: some View {
        let overflow = EditablePlanBlockMetrics.verticalOverflow

        return ZStack(alignment: .topTrailing) {
            selectableBlockCard(height: blockHeight)
                .offset(y: overflow)

            if isSelected && !isLocked {
                resizeHandle(edge: .start)
                    .offset(y: -EditablePlanBlockMetrics.resizeHandleEdgeOutset)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                resizeHandle(edge: .end)
                    .offset(y: blockHeight + overflow - EditablePlanBlockMetrics.resizeHandleEdgeOverlap)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(timeText(interval.startMinute))から\(timeText(interval.endMinute))")
        .accessibilityValue(interval.isMemo ? "予定メモ" : "メイン予定")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect()
        }
        .accessibilityAction(named: Text("詳細を編集")) {
            onSelect()
        }
    }

    @ViewBuilder
    private func blockLabel(height: CGFloat) -> some View {
        if interval.isMemo {
            if height < 28 {
                Text(title).lineLimit(1).font(.system(size: 10, weight: .semibold))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText(interval.startMinute)).monospacedDigit()
                        .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Text(title).font(.system(size: regularTitleFontSize, weight: titleFontWeight))
                        .lineLimit(height < 48 ? 1 : 2)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 4) {
                Text(timeText(interval.startMinute))
                    .font(.system(size: 10.2, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .frame(width: 32, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .layoutPriority(3)

                Text(title)
                    .font(.system(size: regularTitleFontSize, weight: titleFontWeight))
                    .lineLimit(height < 34 ? 1 : 2)
                    .truncationMode(.tail)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .layoutPriority(1)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.2, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .layoutPriority(2)
                }
            }
        }
    }

    private func blockCard(height: CGFloat) -> some View {
        // Keep the gesture's host alive when a drag switches the label's layout between layers.
        ZStack(alignment: .topLeading) {
            blockLabel(height: height)
        }
        .foregroundStyle(interval.isMemo ? color : .white)
        .padding(.horizontal, 8)
        .padding(.vertical, height < 24 ? 2 : 5)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(interval.isMemo ? Color(uiColor: .secondarySystemBackground) : color.opacity(isLocked ? 0.50 : 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(interval.isMemo ? color : isSelected ? .white.opacity(activeResizeEdge == nil ? 0.92 : 0.98) : color.opacity(0.42), style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: interval.isMemo ? [4, 3] : []))
        )
        .shadow(color: color.opacity(0.07), radius: 3, y: 3)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func selectableBlockCard(height: CGFloat) -> some View {
        movableBlockCard(height: height)
            .gesture(TimelinePlanLongPressGesture(onEvent: onLongPress))
            .onTapGesture {
                onSelect()
            }
    }

    @ViewBuilder
    private func movableBlockCard(height: CGFloat) -> some View {
        if isSelected && !isLocked && activeResizeEdge == nil {
            blockCard(height: height)
                .highPriorityGesture(moveGesture)

        } else {
            blockCard(height: height)

        }
    }

    private func resizeHandle(edge: EditablePlanResizeEdge) -> some View {
        let alignment: Alignment = {
            switch edge {
            case .start:
                .bottom
            case .end:
                .top
            }
        }()

        return ZStack(alignment: alignment) {
            Color.white.opacity(0.001)

            handleVisual(edge: edge)
                .padding(edge == .start ? .bottom : .top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: EditablePlanBlockMetrics.resizeHandleHeight)
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private func handleVisual(edge: EditablePlanResizeEdge) -> some View {
        let isActive = activeResizeEdge == edge
        return Capsule()
            .fill(.black.opacity(isActive ? 0.58 : 0.42))
            .frame(maxWidth: EditablePlanBlockMetrics.resizeGripBackgroundWidth + (isActive ? 14 : 0))
            .frame(height: EditablePlanBlockMetrics.resizeGripBackgroundHeight + (isActive ? 3 : 0))
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isActive ? 0.42 : 0.22), lineWidth: 1)
            }
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.96))
                    .frame(maxWidth: EditablePlanBlockMetrics.resizeGripWidth + (isActive ? 12 : 0))
                    .frame(height: EditablePlanBlockMetrics.resizeGripHeight + (isActive ? 1 : 0))
                    .padding(.horizontal, isActive ? 9 : 8)
            }
            .shadow(color: .black.opacity(isActive ? 0.34 : 0.22), radius: isActive ? 5 : 3, y: 1)
    }

    private var titleFontWeight: Font.Weight {
        planTitleBold ? .bold : .semibold
    }

    private var regularTitleFontSize: CGFloat {
        let normalized = min(max(planTitleFontSize, 5), 9)
        return CGFloat(10.8 + (normalized - 6) * 0.62)
    }

    private func timeText(_ minute: Int) -> String {
        let hour = minute / 60
        let minutes = minute % 60
        return String(format: "%02d:%02d", hour, minutes)
    }

    func withBlockHeight(_ value: CGFloat) -> Self {
        var copy = self
        copy.blockHeight = value
        return copy
    }
}

import SwiftUI

private struct WeekTimelineRenderSnapshot {
    let days: [Date]
    let timedSegments: [WeekTimedPlanSegment]
    let allDayPlansByDay: [Date: [PlanBlock]]
    let allDayLaneHeight: CGFloat

    var visibleTimedPlanIDs: Set<UUID> {
        Set(timedSegments.map(\.plan.id))
    }
}

private struct WeekTimelinePlanSignature: Hashable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let createdAt: Date
    let isAllDay: Bool
    let isMemo: Bool
    let categoryID: UUID?
}

private struct WeekTimelineRenderCacheKey: Hashable {
    let weekStart: Date
    let visibleCategoryIDs: Set<UUID>?
    let plans: [WeekTimelinePlanSignature]
}

private struct WeekTimelineRenderCache {
    let key: WeekTimelineRenderCacheKey
    let sortedPlans: [PlanBlock]
    let displayPlans: [PlanBlock]
    let plansByID: [UUID: PlanBlock]
    let timedSegmentsByPlanID: [UUID: [WeekTimedPlanSegment]]
    let axisProfile: TimelineAxisProfile
    let snapshot: WeekTimelineRenderSnapshot
}

private struct WeekTimelineAxisCacheKey: Hashable {
    let renderCacheKey: WeekTimelineRenderCacheKey
    let hourHeight: CGFloat
}

private struct WeekPresetPlacementDraft {
    let preset: PlanPreset
    let snapshot: PlanTemplateSnapshot
    let dayIndex: Int
    let visualStartY: CGFloat
}

private struct WeekTimelineDayScheduleBaseline {
    let originalIntervalsByID: [UUID: PlanTimelineInterval]
    let intervals: [PlanTimelineInterval]
}

private struct WeekMoveRequest: Equatable {
    let dayIndex: Int
    let proposedStartMinute: Int
    let proposedEndMinute: Int
    let direction: PlanTimelinePushDirection
}

/// Gesture bookkeeping that does not directly affect rendered output.
/// Keeping it outside SwiftUI observation prevents non-render bookkeeping from
/// invalidating the full week while preserving all haptic and clamping behavior.
private final class WeekTimelineInteractionScratch {
    var renderCache: WeekTimelineRenderCache?
    var latestScrollMinY: CGFloat = 0
    var pendingVisibleHour: Int?
    var timelineScrollIsActive = false
    var resizeDragStartGlobalY: CGFloat?
    var didWarnDuringScheduleGesture = false
    var lastMoveFeedbackStep: WeekMoveFeedbackStep?
    var lastMoveRequest: WeekMoveRequest?
    var moveBaseline: WeekTimedPlanSegment?
    var lastResizeFeedbackMinute: Int?
    var lastResizeRequest: WeekResizeRequest?
    var lastPresetFeedbackDayIndex: Int?
    var lastPresetFeedbackMinute: Int?
    private var axisCacheKey: WeekTimelineAxisCacheKey?
    private var axisCache: TimelineAxisMap?
    var dayScheduleBaselines: [Int: WeekTimelineDayScheduleBaseline] = [:]

    func cachedAxisMap(
        for key: WeekTimelineAxisCacheKey,
        make: () -> TimelineAxisMap
    ) -> TimelineAxisMap {
        if axisCacheKey == key, let axisCache {
            return axisCache
        }
        let map = make()
        axisCacheKey = key
        axisCache = map
        return map
    }

    func resetScheduleGesture() {
        resizeDragStartGlobalY = nil
        didWarnDuringScheduleGesture = false
        lastMoveFeedbackStep = nil
        lastMoveRequest = nil
        moveBaseline = nil
        lastResizeFeedbackMinute = nil
        lastResizeRequest = nil
        lastPresetFeedbackDayIndex = nil
        lastPresetFeedbackMinute = nil
        dayScheduleBaselines = [:]
    }
}

struct CalendarWeekTimelineView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var planPresetStore
    @Environment(\.colorScheme) private var colorScheme

    let anchorDate: Date
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
    private let presetDrawerPresentation: Binding<Bool>?
    private let onPresetDrawerDismiss: () -> Void
    private let presetDayConfiguration: TimelineDayPresetConfiguration?
    private let onPresetManage: (() -> Void)?
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onOpenPlan: (PlanBlock) -> Void
    let onOpenDay: (Date) -> Void
    let onScheduleChanged: () -> Void
    private let renderCacheKey: WeekTimelineRenderCacheKey

    @State private var selectedPlanID: UUID?
    @State private var gesturePlanID: UUID?
    @State private var dragTargetDayIndex: Int?
    @AppStorage(TimelineSnapPrecision.userDefaultsKey)
    private var storedSnapPrecisionMinutes = TimelineSnapPrecision.quarterHour.minutes
    @State private var creationDraft: WeekPlanCreationDraft?
    @State private var creationGestureIsActive = false
    @State private var movingDrafts: [UUID: WeekPlanMoveDraft] = [:]
    @State private var movingSegmentIdentityDayByPlanID: [UUID: Int] = [:]
    @State private var resizeBaseline: WeekResizeBaseline?
    @State private var activeResizeEdge: WeekResizeEdge?
    @State private var operationError: String?
    @State private var presetApplyRequest: PlanTemplateApplyRequest?
    @State private var planPendingDeletion: PlanBlock?
    @State private var interactionScratch = WeekTimelineInteractionScratch()
    @AppStorage(TimelineZoomPolicy.weekUserDefaultsKey)
    private var storedHourScale = Double(TimelineZoomPolicy.defaultScale)
    @State private var transientHourScale: CGFloat?
    @State private var zoomGestureBaseScale: CGFloat?
    @State private var zoomAnchorMinute: CGFloat?
    @State private var zoomGestureIsActive = false
    @State private var timelineScrollPosition = ScrollPosition()
    @State private var initialVisibleHour: Int?
    @State private var presetDragIsActive = false
    @State private var presetPlacementDraft: WeekPresetPlacementDraft?
    @State private var presetWindowFrame: CGRect?
    @State private var presetTimelineContentFrameSource = TimelineWindowFrameSource()

    private let calendar = Calendar.japanese
    private let hourColumnWidth = TimelineHourAxisMetrics.columnWidth
    private let hourLabelHeight: CGFloat = 14
    private let timelineTopInset: CGFloat = 15
    private let daySpacing: CGFloat = 1
    private let blockInset: CGFloat = 1.5
    private let bottomScrollPadding: CGFloat = 24
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

    private var hourScale: CGFloat {
        transientHourScale ?? TimelineZoomPolicy.normalizedScale(storedHourScale)
    }

    private var hourHeight: CGFloat {
        TimelineZoomPolicy.hourHeight(
            for: hourScale,
            base: TimelineZoomPolicy.weekBaseHourHeight
        )
    }

    private func makeAxisMap(
        cache: WeekTimelineRenderCache,
        hourHeight: CGFloat
    ) -> TimelineAxisMap {
        TimelineAxisMap(
            hourHeight: hourHeight,
            profile: cache.axisProfile
        )
    }

    private var timelineAxisMap: TimelineAxisMap {
        let cache = currentRenderCache
        let key = WeekTimelineAxisCacheKey(
            renderCacheKey: cache.key,
            hourHeight: hourHeight
        )
        return interactionScratch.cachedAxisMap(for: key) {
            makeAxisMap(cache: cache, hourHeight: hourHeight)
        }
    }

    init(
        anchorDate: Date,
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
        presetDrawerPresentation: Binding<Bool>? = nil,
        onPresetDrawerDismiss: @escaping () -> Void = {},
        presetDayConfiguration: TimelineDayPresetConfiguration? = nil,
        onPresetManage: (() -> Void)? = nil,
        visibleHour: Binding<Int>,
        selectedCategoryID: Binding<UUID?>,
        isScheduleInteractionActive: Binding<Bool>,
        onOpenPlan: @escaping (PlanBlock) -> Void,
        onOpenDay: @escaping (Date) -> Void,
        onScheduleChanged: @escaping () -> Void
    ) {
        let normalizedAnchorDate = Calendar.japanese.startOfDay(for: anchorDate)
        self.anchorDate = normalizedAnchorDate
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
        self.presetDrawerPresentation = presetDrawerPresentation
        self.onPresetDrawerDismiss = onPresetDrawerDismiss
        self.presetDayConfiguration = presetDayConfiguration
        self.onPresetManage = onPresetManage
        self._visibleHour = visibleHour
        self._initialVisibleHour = State(initialValue: visibleHour.wrappedValue)
        self._selectedCategoryID = selectedCategoryID
        self._isScheduleInteractionActive = isScheduleInteractionActive
        self.onOpenPlan = onOpenPlan
        self.onOpenDay = onOpenDay
        self.onScheduleChanged = onScheduleChanged
        self.renderCacheKey = WeekTimelineRenderCacheKey(
            weekStart: Self.weekInterval(containing: normalizedAnchorDate).start,
            visibleCategoryIDs: visibleCategoryIDs,
            plans: plans.map {
                WeekTimelinePlanSignature(
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

    var body: some View {
        GeometryReader { proxy in
            let cache = currentRenderCache
            let snapshot = renderSnapshot(using: cache)
            let totalWidth = proxy.size.width
            let dayWidth = max(1, (totalWidth - hourColumnWidth - daySpacing * 6) / 7)
            let timelineViewportHeight = max(1, proxy.size.height - 46 - snapshot.allDayLaneHeight)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    weekHeader(dayWidth: dayWidth, totalWidth: totalWidth, snapshot: snapshot)

                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                timelineGridLayer(dayWidth: dayWidth, totalWidth: totalWidth, snapshot: snapshot)

                                if isInteractionEnabled, let creationDraft {
                                    creationDraftView(draft: creationDraft, dayWidth: dayWidth)
                                    creationTimeGuide(draft: creationDraft, dayWidth: dayWidth, totalWidth: totalWidth)
                                }

                                ForEach(snapshot.timedSegments) { segment in
                                    timedPlanBlock(segment: segment, dayWidth: dayWidth, globalMinX: proxy.frame(in: .global).minX)
                                }

                                if isInteractionEnabled {
                                    moveTimeGuide(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    resizeTimeGuide(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    resizeInteractionLayer(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    currentTimeLine(dayWidth: dayWidth, totalWidth: totalWidth)

                                }
                            }
                            .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
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
                    .defaultScrollAnchor(initialScrollAnchor(viewportHeight: timelineViewportHeight), for: .initialOffset)
                    .frame(width: totalWidth, height: timelineViewportHeight)
                    .scrollDisabled(shouldDisableTimelineScroll || isPageSwipeActive)
                    .scrollIndicators(.visible)
                    .background(timelineBackground)
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
                        updateVisibleHour(fromScrollMinY: minY, viewportHeight: timelineViewportHeight)
                    }
                    .onScrollPhaseChange { _, newPhase in
                        handleTimelineScrollPhaseChange(newPhase)
                    }
                    .onChange(of: anchorDate) { _, _ in
                        cancelZoomGesture()
                        resetInteractionState()
                        initialVisibleHour = visibleHour
                        scrollToVisibleHour()
                    }
                    .onChange(of: snapshot.visibleTimedPlanIDs) { _, visiblePlanIDs in
                        resetSelectionIfHidden(visiblePlanIDs: visiblePlanIDs)
                    }
                    .simultaneousGesture(
                        weekTimelineZoomGesture(viewportHeight: timelineViewportHeight)
                    )
                    .accessibilityIdentifier("week-timeline")
                    .accessibilityValue(zoomAccessibilityValue)
                }
                .frame(width: totalWidth, height: proxy.size.height, alignment: .top)
                .background(timelineBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(timelineStroke, lineWidth: 1)
                )

                if isInteractionEnabled, let presetPlacementDraft {
                    ZStack(alignment: .topLeading) {
                        presetPlacementDraftView(
                            draft: presetPlacementDraft,
                            dayWidth: dayWidth
                        )
                    }
                    .frame(
                        width: totalWidth,
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
                    .allowsHitTesting(false)
                    .zIndex(90)
                }

                if isInteractionEnabled {
                    TimelinePlanPresetLibrary(
                        presets: planPresets,
                        categories: categories,
                        onFixedTimeTap: { preset in
                            if let presetInteractionCoordinator {
                                presetInteractionCoordinator.addFixedTimePreset(preset)
                            } else {
                                addFixedTimePreset(preset)
                            }
                        },
                        onDurationDragChanged: { preset, location in
                            if let presetInteractionCoordinator {
                                presetInteractionCoordinator.updateDurationPreset(preset, at: location)
                            } else {
                                updateDurationPresetPreview(
                                    preset,
                                    at: localPresetLocation(location),
                                    dayWidth: dayWidth,
                                    totalWidth: totalWidth,
                                    allDayLaneHeight: snapshot.allDayLaneHeight,
                                    viewportSize: proxy.size
                                )
                            }
                        },
                        onDurationDrop: { preset, location in
                            if let presetInteractionCoordinator {
                                return presetInteractionCoordinator.finishDurationPreset(preset, at: location)
                            }
                            return finishDurationPresetDrop(
                                preset,
                                at: localPresetLocation(location),
                                dayWidth: dayWidth,
                                totalWidth: totalWidth,
                                allDayLaneHeight: snapshot.allDayLaneHeight,
                                viewportSize: proxy.size
                            )
                        },
                        onDraggingChanged: { active in
                            if let presetInteractionCoordinator {
                                presetInteractionCoordinator.setDragging(active)
                            } else {
                                presetDragIsActive = active
                                isScheduleInteractionActive = active
                                if !active, presetPlacementDraft != nil {
                                    presetPlacementDraft = nil
                                    interactionScratch.lastPresetFeedbackDayIndex = nil
                                    interactionScratch.lastPresetFeedbackMinute = nil
                                }
                            }
                        },
                        launcherPlacement: .externalControl,
                        isPresented: presetDrawerPresentation,
                        dayPresets: presetDayConfiguration,
                        onManage: onPresetManage,
                        onDismiss: onPresetDrawerDismiss
                    )
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topLeading
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
                    viewportSize: proxy.size,
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: snapshot.allDayLaneHeight
                )
            }
            .onChange(of: isInteractionEnabled) { _, _ in
                updatePresetInteractionTarget(
                    frame: presetExternalFrame(in: proxy),
                    viewportSize: proxy.size,
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: snapshot.allDayLaneHeight
                )
            }
            .onChange(of: proxy.size) { _, _ in
                updatePresetInteractionTarget(
                    frame: presetExternalFrame(in: proxy),
                    viewportSize: proxy.size,
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: snapshot.allDayLaneHeight
                )
            }
            .onChange(of: presetWindowFrame) { _, frame in
                updatePresetInteractionTarget(
                    frame: frame,
                    viewportSize: proxy.size,
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: snapshot.allDayLaneHeight
                )
            }
        }
        .padding(.horizontal, CalendarTimelineCardMetrics.horizontalPadding)
        .padding(.top, CalendarTimelineCardMetrics.topPadding)
        .padding(.bottom, CalendarTimelineCardMetrics.bottomPadding)
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
            Text("「\(displayTitle(for: plan))」は元に戻せません。")
        }
        .alert("予定を調整できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
        .onChange(of: renderCacheKey) { _, _ in
            refreshRenderCache()
        }
        .background(PlanTemplateApplyConfirmationPresenter(request: $presetApplyRequest, store: store).frame(width: 0, height: 0))
        .onDisappear {
            presetInteractionCoordinator?.deactivate(targetID: presetInteractionTargetID)
            cancelZoomGesture()
        }
    }

    private var presetCoordinateSpaceName: String {
        "week-plan-preset-\(weekStart.timeIntervalSinceReferenceDate)"
    }

    private var presetInteractionTargetID: String {
        "week-target-\(weekStart.timeIntervalSinceReferenceDate)"
    }

    private func localPresetLocation(_ location: CGPoint?) -> CGPoint? {
        guard let location, let frame = presetWindowFrame else { return nil }
        return CGPoint(x: location.x - frame.minX, y: location.y - frame.minY)
    }

    private func presetExternalFrame(in proxy: GeometryProxy) -> CGRect? {
        guard presetInteractionCoordinator != nil else { return nil }
        return presetWindowFrame
    }

    private func updatePresetInteractionTarget(
        frame: CGRect?,
        viewportSize: CGSize,
        dayWidth: CGFloat,
        totalWidth: CGFloat,
        allDayLaneHeight: CGFloat
    ) {
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
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: allDayLaneHeight,
                    viewportSize: viewportSize
                )
            },
            onDurationDrop: { preset, location in
                finishDurationPresetDrop(
                    preset,
                    at: location,
                    dayWidth: dayWidth,
                    totalWidth: totalWidth,
                    allDayLaneHeight: allDayLaneHeight,
                    viewportSize: viewportSize
                )
            },
            onDraggingChanged: { active in
                presetDragIsActive = active
                isScheduleInteractionActive = active
                if !active, presetPlacementDraft != nil {
                    presetPlacementDraft = nil
                    interactionScratch.lastPresetFeedbackDayIndex = nil
                    interactionScratch.lastPresetFeedbackMinute = nil
                }
            }
        )
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
        interactionScratch.latestScrollMinY = minY
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

        let scrollOffset = max(0, -minY - timelineTopInset)
        let minute = timelineAxisMap.minute(atY: scrollOffset)
        let hour = min(23, max(0, Int((minute / 60).rounded())))
        if interactionScratch.timelineScrollIsActive {
            interactionScratch.pendingVisibleHour = hour
        } else {
            commitVisibleHour(hour)
        }
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

    private func weekTimelineZoomGesture(viewportHeight: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard beginZoomGestureIfNeeded(viewportHeight: viewportHeight),
                      let zoomGestureBaseScale
                else { return }

                let scale = TimelineZoomPolicy.magnifiedScale(
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
              !shouldDisableTimelineScroll,
              !isScheduleInteractionActive,
              viewportHeight > 0
        else { return false }

        let baseScale = TimelineZoomPolicy.normalizedScale(storedHourScale)
        zoomGestureBaseScale = baseScale
        let baseAxis = makeAxisMap(
            cache: currentRenderCache,
            hourHeight: TimelineZoomPolicy.hourHeight(
                for: baseScale,
                base: TimelineZoomPolicy.weekBaseHourHeight
            )
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

        let newHourHeight = TimelineZoomPolicy.hourHeight(
            for: scale,
            base: TimelineZoomPolicy.weekBaseHourHeight
        )
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

        let snappedScale = TimelineZoomPolicy.snappedScale(
            transientHourScale ?? zoomGestureBaseScale ?? TimelineZoomPolicy.defaultScale
        )
        let targetY = applyZoomScale(snappedScale, viewportHeight: viewportHeight)
        let snappedHourHeight = TimelineZoomPolicy.hourHeight(
            for: snappedScale,
            base: TimelineZoomPolicy.weekBaseHourHeight
        )
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
        isScheduleInteractionActive = false
        if let targetY {
            let minute = snappedAxis.minute(atY: max(0, targetY - timelineTopInset))
            visibleHour = min(23, max(0, Int((minute / 60).rounded())))
        }
        LiminalHaptics.selection()
    }

    private func cancelZoomGesture() {
        guard zoomGestureIsActive || transientHourScale != nil else { return }
        transientHourScale = nil
        zoomGestureBaseScale = nil
        zoomAnchorMinute = nil
        zoomGestureIsActive = false
        isScheduleInteractionActive = false
    }

    private func normalizeStoredHourScale() {
        let normalized = TimelineZoomPolicy.normalizedScale(storedHourScale)
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

    private func weekHeader(dayWidth: CGFloat, totalWidth: CGFloat, snapshot: WeekTimelineRenderSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: daySpacing) {
                Rectangle()
                    .fill(hourColumnBackground)
                    .frame(width: hourColumnWidth, height: 46)

                ForEach(snapshot.days, id: \.self) { day in
                    Button {
                        onOpenDay(day)
                    } label: {
                        VStack(spacing: 2) {
                            Text(dayNumberText(day))
                                .font(.system(size: 14, weight: isToday(day) ? .bold : .semibold, design: .monospaced))
                                .foregroundStyle(dayNumberColor(day))
                                .frame(width: 27, height: 27)
                                .background {
                                    if isToday(day) {
                                        Circle()
                                            .fill(LiminalTheme.accent.opacity(0.82))
                                    }
                                }

                            Text(weekdayText(day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(weekdayColor(day))
                        }
                        .frame(width: dayWidth, height: 46)
                        .background(dayHeaderBackground(day))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.japaneseMonthDayShortWeekday)
                    .accessibilityIdentifier("week-day-\(DailyCardSnapshot.dayIdentifier(for: day, calendar: calendar))")
                }
            }
            .frame(height: 46)
            .background(gridLine)

            allDayLane(dayWidth: dayWidth, totalWidth: totalWidth, snapshot: snapshot)
        }
    }

    private func allDayLane(dayWidth: CGFloat, totalWidth: CGFloat, snapshot: WeekTimelineRenderSnapshot) -> some View {
        HStack(alignment: .top, spacing: daySpacing) {
            Rectangle()
                .fill(hourColumnBackground)
                .frame(width: hourColumnWidth, height: snapshot.allDayLaneHeight)

            ForEach(snapshot.days, id: \.self) { day in
                VStack(alignment: .leading, spacing: allDayItemSpacing) {
                    let plans = snapshot.allDayPlansByDay[day] ?? []
                    ForEach(plans.prefix(allDayVisibleRowLimit)) { plan in
                        Button {
                            onOpenPlan(plan)
                        } label: {
                            Text(plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title)
                                .font(.system(size: 7.8, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .allowsTightening(true)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: allDayItemHeight)
                                .background(planColor(plan).opacity(0.68), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if plans.count > allDayVisibleRowLimit {
                        Text("+\(plans.count - allDayVisibleRowLimit)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, allDayLaneVerticalPadding)
                .frame(width: dayWidth, height: snapshot.allDayLaneHeight, alignment: .top)
                .background(dayColumnBackground(day))
            }
        }
        .frame(width: totalWidth, height: snapshot.allDayLaneHeight)
        .background(gridLine)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(gridLine)
                .frame(height: 1)
        }
    }

    private func timelineGrid(dayWidth: CGFloat, totalWidth: CGFloat, days: [Date]) -> some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, _ in
            context.fill(
                Path(CGRect(x: 0, y: 0, width: totalWidth, height: timelineHeight)),
                with: .color(timelineBackground)
            )
            context.fill(
                Path(CGRect(x: 0, y: 0, width: hourColumnWidth, height: timelineHeight)),
                with: .color(hourColumnBackground)
            )

            for (index, day) in days.enumerated() {
                context.fill(
                    Path(
                        CGRect(
                            x: dayX(index, dayWidth: dayWidth),
                            y: 0,
                            width: dayWidth,
                            height: timelineHeight
                        )
                    ),
                    with: .color(dayColumnBackground(day))
                )
            }

            for index in 0...7 {
                let x = hourColumnWidth + CGFloat(index) * (dayWidth + daySpacing) - daySpacing
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 1, height: timelineHeight)),
                    with: .color(gridLine)
                )
            }

            let gridWidth = max(0, totalWidth - hourColumnWidth)
            for hour in 0...24 {
                let tickY = hourTickCenterY(hour)
                context.fill(
                    Path(CGRect(x: hourColumnWidth, y: tickY - 0.5, width: gridWidth, height: 1)),
                    with: .color(primaryLine)
                )

                guard hour < 24 else { continue }

                let secondaryY = yOffset(for: hour * 60 + 30)
                context.fill(
                    Path(CGRect(x: hourColumnWidth, y: secondaryY - 0.5, width: gridWidth, height: 1)),
                    with: .color(secondaryLine)
                )

                context.draw(
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(timeText),
                    at: CGPoint(
                        x: hourColumnWidth - 9,
                        y: hourLabelCenterY(forTickY: tickY)
                    ),
                    anchor: .trailing
                )
            }
        }
        .frame(width: totalWidth, height: timelineHeight)
    }

    @ViewBuilder
    private func timelineGridLayer(dayWidth: CGFloat, totalWidth: CGFloat, snapshot: WeekTimelineRenderSnapshot) -> some View {
        let grid = timelineGrid(dayWidth: dayWidth, totalWidth: totalWidth, days: snapshot.days)
        if isInteractionEnabled {
            grid
                .overlay(alignment: .topLeading) {
                    TimelineCreationLongPressOverlay(
                        minimumDuration: creationLongPressDuration,
                        maximumStationaryDistance: creationLongPressMaximumDistance,
                        onChanged: { startLocation, location in
                            handleCreationLongPressChanged(
                                startLocation: startLocation,
                                location: location,
                                dayWidth: dayWidth,
                                timedSegments: snapshot.timedSegments
                            )
                        },
                        onEnded: { startLocation, location, completed in
                            finishCreationLongPress(
                                startLocation: startLocation,
                                location: location,
                                completed: completed,
                                dayWidth: dayWidth,
                                timedSegments: snapshot.timedSegments
                            )
                        },
                        onTap: { point in
                            clearSelectionIfNeeded(at: point, dayWidth: dayWidth, timedSegments: snapshot.timedSegments)
                        }
                    )
                    .frame(width: totalWidth, height: timelineHeight)
                }
        } else {
            grid
        }
    }

    @ViewBuilder
    private func timedPlanBlock(segment: WeekTimedPlanSegment, dayWidth: CGFloat, globalMinX: CGFloat) -> some View {
        let color = planColor(segment.plan)
        let blockHeight = height(startMinute: segment.startMinute, endMinute: segment.endMinute)
        let isSelected = selectedPlanID == segment.plan.id
        let isLocked = store.isPlanScheduleLocked(segment.plan)
        let overflow = WeekTimedPlanBlockMetrics.verticalOverflow
        let title = displayTitle(for: segment.plan)
        let cardWidth = segmentFrame(segment, dayWidth: dayWidth).width

        let block = ZStack(alignment: .top) {
            weekPlanCard(
                segment: segment,
                dayWidth: dayWidth,
                blockHeight: blockHeight,
                color: color,
                isSelected: isSelected,
                isLocked: isLocked,
                activeResizeEdge: isSelected ? activeResizeEdge : nil,
                globalMinX: globalMinX
            )
                .gesture(TimelinePlanLongPressGesture { state, _ in
                    handlePlanLongPress(segment, state: state)
                })
                .offset(y: overflow)

            if isSelected && !isLocked {
                weekHandle(edge: .start)
                    .frame(width: cardWidth, alignment: .center)
                    .offset(y: -WeekTimedPlanBlockMetrics.resizeHandleEdgeOutset)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityLabel("開始時刻を調整")

                weekHandle(edge: .end)
                    .frame(width: cardWidth, alignment: .center)
                    .offset(y: blockHeight + overflow - WeekTimedPlanBlockMetrics.resizeHandleEdgeOverlap)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityLabel("終了時刻を調整")
            }
        }
        .frame(
            width: cardWidth,
            height: blockHeight + overflow * 2,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleSegmentTap(segment)
        }
        .offset(
            x: segmentFrame(segment, dayWidth: dayWidth).minX,
            y: yOffset(for: segment.startMinute) - overflow
        )
        .zIndex(isSelected ? 3 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(timeRangeText(segment))")
        .accessibilityValue("メイン予定")
        .accessibilityIdentifier("week-plan-\(segment.id)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleSegmentTap(segment)
        }
        .accessibilityAction(named: Text("詳細を編集")) {
            guard gesturePlanID == nil else { return }
            onOpenPlan(segment.plan)
        }

        if isSelected && !isLocked {
            let step = snapPrecision.minutes
            block
                .accessibilityAction(named: Text("\(step)分早める")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: -step, dayDelta: 0)
                }
                .accessibilityAction(named: Text("\(step)分遅らせる")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: step, dayDelta: 0)
                }
                .accessibilityAction(named: Text("前日に移動")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: 0, dayDelta: -1)
                }
                .accessibilityAction(named: Text("翌日に移動")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: 0, dayDelta: 1)
                }
                .accessibilityAction(named: Text("開始を\(step)分早める")) {
                    applyAccessibilityResize(segment: segment, edge: .start, minuteDelta: -step)
                }
                .accessibilityAction(named: Text("開始を\(step)分遅らせる")) {
                    applyAccessibilityResize(segment: segment, edge: .start, minuteDelta: step)
                }
                .accessibilityAction(named: Text("終了を\(step)分早める")) {
                    applyAccessibilityResize(segment: segment, edge: .end, minuteDelta: -step)
                }
                .accessibilityAction(named: Text("終了を\(step)分遅らせる")) {
                    applyAccessibilityResize(segment: segment, edge: .end, minuteDelta: step)
                }
        } else {
            block
        }
    }

    private func updateDragDay(_ value: DragGesture.Value, segment: WeekTimedPlanSegment, dayWidth: CGFloat, globalMinX: CGFloat) {
        let localX = value.location.x - globalMinX
        dragTargetDayIndex = dayIndex(forX: max(hourColumnWidth, min(localX, dayX(6, dayWidth: dayWidth) + dayWidth - 1)), dayWidth: dayWidth) ?? segment.dayIndex
    }

    private func handlePlanLongPress(_ segment: WeekTimedPlanSegment, state: UIGestureRecognizer.State) {
        guard state == .began, isInteractionEnabled, !zoomGestureIsActive,
              gesturePlanID == nil, !creationGestureIsActive else { return }
        if selectedPlanID == segment.plan.id {
            requestDeletePlan(segment.plan)
        } else {
            selectedPlanID = segment.plan.id
            LiminalHaptics.selection()
        }
    }

    private func handleSegmentTap(_ segment: WeekTimedPlanSegment) {
        guard gesturePlanID == nil, !zoomGestureIsActive else { return }
        guard planPendingDeletion?.id != segment.plan.id else { return }
        if selectedPlanID == segment.plan.id {
            onOpenPlan(segment.plan)
        } else {
            LiminalHaptics.selection()
            selectedPlanID = segment.plan.id
        }
    }

    @ViewBuilder
    private func weekPlanCard(
        segment: WeekTimedPlanSegment,
        dayWidth: CGFloat,
        blockHeight: CGFloat,
        color: Color,
        isSelected: Bool,
        isLocked: Bool,
        activeResizeEdge: WeekResizeEdge?,
        globalMinX: CGFloat
    ) -> some View {
        let title = displayTitle(for: segment.plan)
        let showsTitle = blockHeight >= 38
        let card = VStack(alignment: .leading, spacing: 1) {
            Text(timeText(segment.startMinute))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .layoutPriority(3)

            if showsTitle {
                Text(title)
                    .font(.system(size: regularWeekTitleFontSize, weight: weekTitleFontWeight))
                    .lineLimit(blockHeight < 68 ? 1 : 2)
                    .minimumScaleFactor(0.66)
                    .allowsTightening(true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2.5)
        .padding(.vertical, showsTitle ? 2.5 : 2)
        .frame(maxWidth: .infinity, minHeight: blockHeight, maxHeight: blockHeight, alignment: .topLeading)
        .background(color.opacity(isLocked ? 0.40 : 0.72), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.92) : color.opacity(0.62), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .clear, radius: 0)
        .contentShape(Rectangle())
        .accessibilityHidden(true)

        if isSelected && !isLocked && activeResizeEdge == nil {
            card.highPriorityGesture(moveGesture(for: segment, dayWidth: dayWidth, globalMinX: globalMinX))
        } else {
            card
        }
    }

    private func displayTitle(for plan: PlanBlock) -> String {
        plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title
    }

    private func weekHandle(edge: WeekResizeEdge) -> some View {
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

            weekHandleVisual(edge: edge, activeResizeEdge: activeResizeEdge)
                .padding(edge == .start ? .bottom : .top, edge == .start ? 0 : 2)
        }
        .frame(width: WeekTimedPlanBlockMetrics.visibleResizeHandleWidth, alignment: .center)
        .frame(height: WeekTimedPlanBlockMetrics.resizeHandleHeight)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func weekHandleVisual(edge: WeekResizeEdge, activeResizeEdge: WeekResizeEdge?) -> some View {
        let isActive = activeResizeEdge == edge
        return ZStack {
            Capsule()
                .fill(.white.opacity(isActive ? 0.30 : 0.20))
                .frame(height: WeekTimedPlanBlockMetrics.resizeGripBackgroundHeight + (isActive ? 3 : 0))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(isActive ? 0.62 : 0.44), lineWidth: 1)
                }

            Capsule()
                .fill(.white.opacity(0.96))
                .frame(height: WeekTimedPlanBlockMetrics.resizeGripHeight + (isActive ? 1 : 0))
                .padding(.horizontal, isActive ? 2 : 4)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(isActive ? 0.38 : 0.28), radius: isActive ? 5 : 3, y: 1)
    }

    private var weekTitleFontWeight: Font.Weight {
        planTitleBold ? .bold : .semibold
    }

    private var regularWeekTitleFontSize: CGFloat {
        let normalized = min(max(planTitleFontSize, 5), 9)
        return CGFloat(7.8 + (normalized - 6) * 0.34)
    }

    private func creationDraftView(draft: WeekPlanCreationDraft, dayWidth: CGFloat) -> some View {
        let color = selectedCategory?.displayColor ?? LiminalTheme.accent
        let blockHeight = max(1, height(startMinute: draft.startMinute, endMinute: draft.endMinute))
        let showsTitle = blockHeight >= 38
        return VStack(alignment: .leading, spacing: 1) {
            Text(timeText(draft.startMinute))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .layoutPriority(3)
            if showsTitle {
                Text(selectedCategory?.name ?? "予定")
                    .font(.system(size: 7.8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2.5)
        .padding(.vertical, 3)
        .frame(width: max(1, dayWidth - blockInset * 2), height: blockHeight, alignment: .topLeading)
        .background(color.opacity(0.66), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.92), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipped()
        .offset(x: dayX(draft.dayIndex, dayWidth: dayWidth) + blockInset, y: yOffset(for: draft.startMinute))
        .allowsHitTesting(false)
    }

    private func presetPlacementDraftView(
        draft: WeekPresetPlacementDraft,
        dayWidth: CGFloat
    ) -> some View {
        let color = categories.first { $0.id == draft.snapshot.categoryID }?.displayColor
            ?? LiminalTheme.accent
        let blockHeight = height(
            startMinute: draft.snapshot.startMinute,
            endMinute: draft.snapshot.endMinute
        )
        let showsTitle = blockHeight >= 24

        return VStack(alignment: .leading, spacing: 1) {
            Text(timeText(draft.snapshot.startMinute))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            if showsTitle {
                Text(draft.snapshot.title)
                    .font(.system(size: 7.8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2.5)
        .padding(.vertical, blockHeight < 20 ? 1.5 : 3)
        .frame(
            width: max(1, dayWidth - blockInset * 2),
            height: blockHeight,
            alignment: .topLeading
        )
        .background(color.opacity(0.86), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.white.opacity(0.94), lineWidth: 1.6)
        }
        .shadow(color: color.opacity(0.24), radius: 4, y: 2)
        .offset(
            x: dayX(draft.dayIndex, dayWidth: dayWidth) + blockInset,
            y: draft.visualStartY
        )
        .allowsHitTesting(false)
        .zIndex(90)
    }

    private func creationTimeGuide(draft: WeekPlanCreationDraft, dayWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let color = selectedCategory?.displayColor ?? LiminalTheme.accent
        return ZStack(alignment: .topLeading) {
            creationBoundaryLine(
                minute: draft.startMinute,
                dayIndex: draft.dayIndex,
                label: timeText(draft.startMinute),
                color: color,
                dayWidth: dayWidth,
                totalWidth: totalWidth
            )

            creationBoundaryLine(
                minute: draft.endMinute,
                dayIndex: draft.dayIndex,
                label: timeText(draft.endMinute),
                color: color,
                dayWidth: dayWidth,
                totalWidth: totalWidth
            )
        }
        .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(88)
    }

    private func creationBoundaryLine(
        minute: Int,
        dayIndex: Int,
        label: String,
        color: Color,
        dayWidth: CGFloat,
        totalWidth: CGFloat
    ) -> some View {
        let y = yOffset(for: minute)
        let x = dayX(dayIndex, dayWidth: dayWidth)
        let labelX = min(
            max(x + 2, hourColumnWidth + 1),
            max(hourColumnWidth + 1, totalWidth - 45)
        )
        let labelY = max(0, min(timelineHeight - 18, y - 9))

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(0.70))
                .frame(width: dayWidth, height: 1.1)
                .offset(x: x, y: y)

            Text(label)
                .font(.system(size: 8.2, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.9))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .offset(x: labelX, y: labelY)
        }
    }

    private func handleCreationLongPressChanged(
        startLocation: CGPoint,
        location: CGPoint,
        dayWidth: CGFloat,
        timedSegments: [WeekTimedPlanSegment]
    ) {
        guard gesturePlanID == nil else { return }

        guard !zoomGestureIsActive else { return }
        guard isCreationDragDirection(startLocation: startLocation, location: location) else {
            cancelCreationGesture()
            return
        }
        if updateCreationDraft(startLocation: startLocation, location: location, dayWidth: dayWidth, timedSegments: timedSegments) {
            activateCreationGestureIfNeeded()
        }
    }

    private func finishCreationLongPress(
        startLocation: CGPoint,
        location: CGPoint,
        completed: Bool,
        dayWidth: CGFloat,
        timedSegments: [WeekTimedPlanSegment]
    ) {
        guard gesturePlanID == nil else { return }

        guard !zoomGestureIsActive else { return }
        defer {
            creationDraft = nil
            resetScheduleGestureState()
        }
        guard completed,
              isCreationDragDirection(startLocation: startLocation, location: location),
              updateCreationDraft(startLocation: startLocation, location: location, dayWidth: dayWidth, timedSegments: timedSegments, isFinal: true)
        else { return }
        commitCreationDraft()
    }

    @discardableResult
    private func updateCreationDraft(
        startLocation: CGPoint,
        location: CGPoint,
        dayWidth: CGFloat,
        timedSegments: [WeekTimedPlanSegment],
        isFinal: Bool = false
    ) -> Bool {
        guard gesturePlanID == nil else { return false }

        guard let dayIndex = dayIndex(forX: startLocation.x, dayWidth: dayWidth),
              canCreatePlan(onDayIndex: dayIndex)
        else {
            creationDraft = nil
            return false
        }
        guard !isExistingSegmentHit(at: startLocation, dayWidth: dayWidth, timedSegments: timedSegments) else {
            creationDraft = nil
            return false
        }
        let start = snappedMinute(fromY: startLocation.y)
        let current = snappedMinute(fromY: location.y)
        guard let range = clampedCreationRange(
            anchorMinute: start,
            currentMinute: current,
            intervals: creationCollisionIntervals(onDayIndex: dayIndex),
            isFinal: isFinal
        ) else {
            creationDraft = nil
            return false
        }
        creationDraft = WeekPlanCreationDraft(dayIndex: dayIndex, startMinute: range.start, endMinute: range.end)
        selectedPlanID = nil
        return true
    }

    private func isCreationDragDirection(startLocation: CGPoint, location: CGPoint) -> Bool {
        let horizontal = abs(location.x - startLocation.x)
        let vertical = abs(location.y - startLocation.y)
        return horizontal <= creationHorizontalCancelDistance || vertical >= horizontal * creationVerticalIntentRatio
    }

    private func activateCreationGestureIfNeeded() {
        guard !creationGestureIsActive else { return }
        creationGestureIsActive = true
        markScheduleInteractionActive()
        LiminalHaptics.selection()
    }

    private func cancelCreationGesture() {
        creationDraft = nil
        creationGestureIsActive = false
        isScheduleInteractionActive = false
    }

    private func clampedCreationRange(
        anchorMinute: Int, currentMinute: Int, intervals: [PlanTimelineInterval], isFinal: Bool
    ) -> (start: Int, end: Int)? {
        guard let range = PlanTimelineCreationPolicy.range(anchorMinute: anchorMinute, currentMinute: currentMinute,
            minimumDuration: minimumDurationMinutes, intervals: intervals, enforcesMinimumDuration: isFinal)
        else { return nil }
        return (range.start, range.end)
    }

    private func creationCollisionIntervals(onDayIndex dayIndex: Int) -> [PlanTimelineInterval] {
        guard days.indices.contains(dayIndex) else { return [] }
        let dayStart = calendar.startOfDay(for: days[dayIndex])
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return sortedPlans
            .filter { !$0.isAllDay && !$0.isMemo }
            .compactMap { plan -> PlanTimelineInterval? in
                guard plan.startTime < dayEnd, plan.endTime > dayStart else { return nil }
                let clippedStart = max(plan.startTime, dayStart)
                let clippedEnd = min(plan.endTime, dayEnd)
                guard clippedEnd > clippedStart else { return nil }
                return PlanTimelineInterval(
                    id: plan.id,
                    startMinute: minute(from: clippedStart, dayStart: dayStart),
                    endMinute: minute(from: clippedEnd, dayStart: dayStart), isMemo: plan.isMemo
                )
            }
    }

    private func commitCreationDraft() {
        guard let creationDraft, let selectedCategory else { return }
        defer {
            self.creationDraft = nil
        }
        guard canCreatePlan(onDayIndex: creationDraft.dayIndex) else {
            operationError = "今日以前の予定はここから追加できません。"
            LiminalHaptics.warning()
            return
        }
        let day = days[creationDraft.dayIndex]
        let start = date(on: day, minute: creationDraft.startMinute)
        let end = date(on: day, minute: creationDraft.endMinute)
        guard !store.hasTimedPlanOverlap(startTime: start, endTime: end) else {
            operationError = "既存の予定と重なっています。空いている時間をなぞってください。"
            LiminalHaptics.warning()
            return
        }
        guard let plan = store.createPlanBlock(
            category: selectedCategory,
            title: selectedCategory.name,
            startTime: start,
            endTime: end,
            isAllDay: false
        ) else {
            operationError = "予定を作成できませんでした。未来の日付の空いている時間を選んでください。"
            LiminalHaptics.warning()
            return
        }
        selectedPlanID = plan.id
        LiminalHaptics.commit()
        onScheduleChanged()
    }

    private var memoPresetMessage: String {
        "予定メモは日表示のプリセットから追加できます。"
    }

    private func addFixedTimePreset(_ preset: PlanPreset) {
        guard !preset.isMemo else {
            operationError = memoPresetMessage
            return
        }
        // 週表示でタップ配置する日は、ページの基準日（現在週なら今日）に固定する。
        // 任意の曜日へ置く長さ指定プリセットは、カードをその列へドラッグする。
        let targetDay = days.first { calendar.isDate($0, inSameDayAs: anchorDate) } ?? days[0]
        guard let interval = preset.snapshot.interval(on: targetDay, calendar: calendar) else {
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
        dayWidth: CGFloat,
        totalWidth: CGFloat,
        allDayLaneHeight: CGFloat,
        viewportSize: CGSize
    ) {
        guard !preset.isMemo else {
            presetPlacementDraft = nil
            return
        }
        guard let location,
              location.x >= 0,
              location.x <= min(totalWidth, viewportSize.width),
              location.y >= 0,
              location.y <= viewportSize.height,
              let dayIndex = dayIndex(forX: location.x, dayWidth: dayWidth)
        else {
            return
        }

        guard let viewportFrame = presetWindowFrame,
              let contentFrame = presetTimelineContentFrameSource.currentFrame
        else {
            return
        }
        let estimatedBlockHeight = height(
            startMinute: 0,
            endMinute: preset.snapshot.durationMinutes
        )
        let proposedVisualStartY = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: location.y,
            cardHeight: estimatedBlockHeight,
            viewportHeight: viewportSize.height,
            minimumY: 46 + allDayLaneHeight
        )
        let contentY = TimelinePlanPresetPlacementGeometry.axisY(
            windowFingerY: viewportFrame.minY + proposedVisualStartY,
            contentFrameMinY: contentFrame.minY,
            timelineTopInset: timelineTopInset
        )
        let rawMinute = Int(timelineAxisMap.minute(atY: contentY).rounded())
        let step = snapPrecision.minutes
        let minute = min(24 * 60, max(0, (rawMinute / step) * step))
        let maximumStartMinute = max(
            0,
            TimelineAxisMap.minutesPerDay - preset.snapshot.durationMinutes
        )
        guard let snapshot = preset.placementMode == .fixedTime ? preset.snapshot
            : preset.snapshot.placed(at: min(maximumStartMinute, max(0, minute))) else {
            return
        }
        let blockHeight = height(
            startMinute: snapshot.startMinute,
            endMinute: snapshot.endMinute
        )
        let visualStartY = preset.placementMode == .fixedTime
            ? contentFrame.minY - viewportFrame.minY + yOffset(for: snapshot.startMinute)
            : TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: location.y,
            cardHeight: blockHeight,
            viewportHeight: viewportSize.height,
            minimumY: 46 + allDayLaneHeight
        )

        if interactionScratch.lastPresetFeedbackDayIndex != dayIndex
            || interactionScratch.lastPresetFeedbackMinute != snapshot.startMinute {
            interactionScratch.lastPresetFeedbackDayIndex = dayIndex
            interactionScratch.lastPresetFeedbackMinute = snapshot.startMinute
            LiminalHaptics.selection()
        }
        if presetPlacementDraft?.snapshot != snapshot
            || presetPlacementDraft?.dayIndex != dayIndex
            || presetPlacementDraft?.preset.id != preset.id
            || abs((presetPlacementDraft?.visualStartY ?? -.infinity) - visualStartY) > 0.25 {
            presetPlacementDraft = WeekPresetPlacementDraft(
                preset: preset,
                snapshot: snapshot,
                dayIndex: dayIndex,
                visualStartY: visualStartY
            )
        }
    }

    private func finishDurationPresetDrop(
        _ preset: PlanPreset,
        at location: CGPoint?,
        dayWidth: CGFloat,
        totalWidth: CGFloat,
        allDayLaneHeight: CGFloat,
        viewportSize: CGSize
    ) -> String? {
        guard !preset.isMemo else { return memoPresetMessage }
        updateDurationPresetPreview(
            preset,
            at: location,
            dayWidth: dayWidth,
            totalWidth: totalWidth,
            allDayLaneHeight: allDayLaneHeight,
            viewportSize: viewportSize
        )
        defer {
            presetPlacementDraft = nil
            interactionScratch.lastPresetFeedbackDayIndex = nil
            interactionScratch.lastPresetFeedbackMinute = nil
        }
        guard let draft = presetPlacementDraft,
              draft.preset.id == preset.id,
              days.indices.contains(draft.dayIndex),
              let interval = draft.snapshot.interval(
                on: days[draft.dayIndex],
                calendar: calendar
              )
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
        guard !source.isMemo else { return memoPresetMessage }
        guard store.canCreatePlan(startTime: interval.start, isAllDay: source.isAllDay, isMemo: source.isMemo) else {
            return "この日には予定を追加できません。"
        }
        let category = categories.first { $0.id == source.categoryID }
        if !source.isAllDay && !source.isMemo && store.hasTimedPlanOverlap(startTime: interval.start, endTime: interval.end) {
            presetApplyRequest = PlanTemplateApplyRequest(
                applications: [.init(snapshot: source, resolvedCategory: category)], targetDate: interval.start,
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

    private func requestDeletePlan(_ plan: PlanBlock) {
        guard !store.isPlanScheduleLocked(plan),
              movingDrafts.isEmpty,
              resizeBaseline == nil,
              activeResizeEdge == nil
        else { return }
        selectedPlanID = plan.id
        planPendingDeletion = plan
        LiminalHaptics.selection()
    }

    private func deletePlan(_ plan: PlanBlock) {
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

    private func isExistingSegmentHit(at point: CGPoint, dayWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) -> Bool {
        timedSegments.contains { segment in
            let frame = segmentFrame(segment, dayWidth: dayWidth)
            let x = frame.minX
            let y = frame.minY
            let width = frame.width
            let height = height(startMinute: segment.startMinute, endMinute: segment.endMinute)
            let slop = WeekTimedPlanBlockMetrics.creationHitSlop
            return point.x >= x - slop &&
                point.x <= x + width + slop &&
                point.y >= y - slop &&
                point.y <= y + height + slop
                || isSelectedResizeHandleHit(segment: segment, point: point, dayWidth: dayWidth)
        }
    }

    private func isSelectedResizeHandleHit(segment: WeekTimedPlanSegment, point: CGPoint, dayWidth: CGFloat) -> Bool {
        guard segment.plan.id == selectedPlanID else { return false }

        let totalWidth = hourColumnWidth + dayWidth * 7 + daySpacing * 6
        let timelineMinX = hourColumnWidth
        let timelineMaxX = totalWidth
        let handleWidth = weekResizeHandleWidth(dayWidth: dayWidth, timelineWidth: timelineMaxX - timelineMinX)
        let centeredX = segmentFrame(segment, dayWidth: dayWidth).midX - handleWidth / 2
        let handleX = min(max(centeredX, timelineMinX), max(timelineMinX, timelineMaxX - handleWidth))
        let topY = yOffset(for: segment.startMinute) - WeekTimedPlanBlockMetrics.resizeHitHandleHeight
        let bottomY = yOffset(for: segment.startMinute) + height(startMinute: segment.startMinute, endMinute: segment.endMinute)
        return isPoint(
            point,
            insideX: handleX,
            y: topY,
            width: handleWidth,
            height: WeekTimedPlanBlockMetrics.resizeHitHandleHeight
        ) || isPoint(
            point,
            insideX: handleX,
            y: bottomY,
            width: handleWidth,
            height: WeekTimedPlanBlockMetrics.resizeHitHandleHeight
        )
    }

    private func isPoint(_ point: CGPoint, insideX x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Bool {
        point.x >= x &&
            point.x <= x + width &&
            point.y >= y &&
            point.y <= y + height
    }

    private func clearSelectionIfNeeded(at point: CGPoint, dayWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) {
        guard gesturePlanID == nil, selectedPlanID != nil,
              !isExistingSegmentHit(at: point, dayWidth: dayWidth, timedSegments: timedSegments)
        else { return }
        selectedPlanID = nil
        planPendingDeletion = nil
        LiminalHaptics.selection()
    }

    private func clearSelectionGesture(dayWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                clearSelectionIfNeeded(at: value.location, dayWidth: dayWidth, timedSegments: timedSegments)
            }
    }

    private func moveGesture(for segment: WeekTimedPlanSegment, dayWidth: CGFloat, globalMinX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard gesturePlanID == nil || gesturePlanID == segment.plan.id,
                      !zoomGestureIsActive,
                      !store.isPlanScheduleLocked(segment.plan)
                else { return }
                gesturePlanID = segment.plan.id
                if interactionScratch.moveBaseline == nil {
                    interactionScratch.moveBaseline = segment
                }
                markScheduleInteractionActive()
                if selectedPlanID != segment.plan.id {
                    selectedPlanID = segment.plan.id
                }
                if movingSegmentIdentityDayByPlanID[segment.plan.id] == nil {
                    movingSegmentIdentityDayByPlanID[segment.plan.id] = segment.dayIndex
                }
                resizeBaseline = nil
                updateDragDay(value, segment: segment, dayWidth: dayWidth, globalMinX: globalMinX)
                if let drafts = moveDrafts(for: segment, translation: dragTranslation(value), dayWidth: dayWidth, targetDay: dragTargetDayIndex) {
                    updateMovingDrafts(drafts)
                    notifyMoveStepIfNeeded(from: drafts, planID: segment.plan.id, fallbackDayIndex: segment.dayIndex)
                } else {
                    warnOnceDuringScheduleGesture()
                }
            }
            .onEnded { value in
                guard gesturePlanID == segment.plan.id else { return }
                guard !zoomGestureIsActive,
                      !store.isPlanScheduleLocked(segment.plan),
                      let drafts = moveDrafts(for: segment, translation: dragTranslation(value), dayWidth: dayWidth, targetDay: dragTargetDayIndex)
                else {
                    if !movingDrafts.isEmpty {
                        finishScheduleDrafts(
                            movingDrafts,
                            failureMessage: "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
                        )
                        return
                    }
                    resetScheduleGestureState()
                    return
                }
                finishScheduleDrafts(drafts, failureMessage: "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。")
            }
    }

    private func startHandleGesture(for segment: WeekTimedPlanSegment) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let baseline = currentResizeBaseline(for: segment)
                guard gesturePlanID == nil || gesturePlanID == segment.plan.id,
                      !zoomGestureIsActive,
                      selectedPlanID == segment.plan.id,
                      !store.isPlanScheduleLocked(segment.plan)
                else { return }
                gesturePlanID = segment.plan.id
                markScheduleInteractionActive()
                if resizeBaseline == nil {
                    resizeBaseline = baseline
                    interactionScratch.resizeDragStartGlobalY = value.startLocation.y
                    interactionScratch.lastResizeFeedbackMinute = baseline.startMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .start
                guard let drafts = resizeDrafts(
                    for: segment.plan,
                    baseline: baseline,
                    edge: .start,
                    translationY: resizeDragTranslationY(value)
                ) else {
                    warnOnceDuringScheduleGesture()
                    return
                }
                updateMovingDrafts(drafts)
                notifyResizeStepIfNeeded(from: drafts, planID: segment.plan.id, edge: .start, baseline: baseline)
            }
            .onEnded { value in
                finishResize(segment: segment, edge: .start, translationY: resizeDragTranslationY(value))
            }
    }

    private func endHandleGesture(for segment: WeekTimedPlanSegment) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let baseline = currentResizeBaseline(for: segment)
                guard gesturePlanID == nil || gesturePlanID == segment.plan.id,
                      !zoomGestureIsActive,
                      selectedPlanID == segment.plan.id,
                      !store.isPlanScheduleLocked(segment.plan)
                else { return }
                gesturePlanID = segment.plan.id
                markScheduleInteractionActive()
                if resizeBaseline == nil {
                    resizeBaseline = baseline
                    interactionScratch.resizeDragStartGlobalY = value.startLocation.y
                    interactionScratch.lastResizeFeedbackMinute = baseline.endMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .end
                guard let drafts = resizeDrafts(
                    for: segment.plan,
                    baseline: baseline,
                    edge: .end,
                    translationY: resizeDragTranslationY(value)
                ) else {
                    warnOnceDuringScheduleGesture()
                    return
                }
                updateMovingDrafts(drafts)
                notifyResizeStepIfNeeded(from: drafts, planID: segment.plan.id, edge: .end, baseline: baseline)
            }
            .onEnded { value in
                finishResize(segment: segment, edge: .end, translationY: resizeDragTranslationY(value))
            }
    }

    private func finishResize(segment: WeekTimedPlanSegment, edge: WeekResizeEdge, translationY: CGFloat) {
        guard gesturePlanID == segment.plan.id else { return }
        let baseline = currentResizeBaseline(for: segment)
        guard let drafts = resizeDrafts(
            for: segment.plan,
            baseline: baseline,
            edge: edge,
            translationY: translationY
        ) else {
            if !movingDrafts.isEmpty {
                finishScheduleDrafts(
                    movingDrafts,
                    failureMessage: "予定の長さを変更できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
                )
                return
            }
            resetScheduleGestureState()
            return
        }
        finishScheduleDrafts(drafts, failureMessage: "予定の長さを変更できませんでした。今日以前や収まりきらない玉突き移動は変更できません。")
    }

    private func notifyResizeStepIfNeeded(
        from drafts: [UUID: WeekPlanMoveDraft],
        planID: UUID,
        edge: WeekResizeEdge,
        baseline: WeekResizeBaseline
    ) {
        guard days.indices.contains(baseline.dayIndex),
              let draft = drafts[planID]
        else { return }
        let dayStart = calendar.startOfDay(for: days[baseline.dayIndex])
        let minute = edge == .start
            ? minute(from: draft.startTime, dayStart: dayStart)
            : minute(from: draft.endTime, dayStart: dayStart)
        guard interactionScratch.lastResizeFeedbackMinute != minute else { return }
        interactionScratch.lastResizeFeedbackMinute = minute
        LiminalHaptics.selection()
    }

    private func notifyMoveStepIfNeeded(
        from drafts: [UUID: WeekPlanMoveDraft],
        planID: UUID,
        fallbackDayIndex: Int
    ) {
        guard let draft = drafts[planID] else { return }
        let dayIndex = days.firstIndex { calendar.isDate($0, inSameDayAs: draft.startTime) } ?? fallbackDayIndex
        guard days.indices.contains(dayIndex) else { return }
        let minute = minute(from: draft.startTime, dayStart: calendar.startOfDay(for: days[dayIndex]))
        let step = WeekMoveFeedbackStep(dayIndex: dayIndex, minute: minute)
        guard interactionScratch.lastMoveFeedbackStep != step else { return }
        interactionScratch.lastMoveFeedbackStep = step
        LiminalHaptics.selection()
    }

    private func currentResizeBaseline(for segment: WeekTimedPlanSegment) -> WeekResizeBaseline {
        if let resizeBaseline, resizeBaseline.planID == segment.plan.id {
            return resizeBaseline
        }
        return WeekResizeBaseline(segment: segment)
    }

    @ViewBuilder
    private func resizeInteractionLayer(dayWidth: CGFloat, totalWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) -> some View {
        if let selectedPlanID,
           let segment = timedSegments.first(where: { $0.plan.id == selectedPlanID }),
           !store.isPlanScheduleLocked(segment.plan) {
            let baseline = resizeBaseline ?? WeekResizeBaseline(segment: segment)
            let timelineMinX = hourColumnWidth
            let timelineMaxX = totalWidth
            let handleWidth = activeResizeEdge == nil
                ? weekResizeHandleWidth(dayWidth: dayWidth, timelineWidth: timelineMaxX - timelineMinX)
                : timelineMaxX - timelineMinX
            let centeredX = segmentFrame(segment, dayWidth: dayWidth).midX - handleWidth / 2
            let handleX = min(max(centeredX, timelineMinX), max(timelineMinX, timelineMaxX - handleWidth))
            let topY = yOffset(for: baseline.startMinute) - WeekTimedPlanBlockMetrics.resizeHitHandleHeight
            let bottomY = yOffset(for: baseline.startMinute) + height(startMinute: baseline.startMinute, endMinute: baseline.endMinute)

            ZStack(alignment: .topLeading) {
                resizeHitHandle()
                    .frame(width: handleWidth)
                    .offset(x: handleX, y: topY)
                    .highPriorityGesture(startHandleGesture(for: segment), including: .all)

                resizeHitHandle()
                    .frame(width: handleWidth)
                    .offset(x: handleX, y: bottomY)
                    .highPriorityGesture(endHandleGesture(for: segment), including: .all)
            }
            .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private func resizeTimeGuide(dayWidth: CGFloat, totalWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) -> some View {
        if let selectedPlanID,
           let activeResizeEdge,
           let segment = timedSegments.first(where: { $0.plan.id == selectedPlanID }),
           !store.isPlanScheduleLocked(segment.plan) {
            let minute = activeResizeEdge == .start ? segment.startMinute : segment.endMinute
            let y = yOffset(for: minute)
            let x = dayX(segment.dayIndex, dayWidth: dayWidth)
            let color = planColor(segment.plan)
            let labelX = min(
                max(x + 2, hourColumnWidth + 1),
                max(hourColumnWidth + 1, totalWidth - 45)
            )
            let labelY = max(0, min(timelineHeight - 20, y - 11))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(0.92))
                    .frame(width: dayWidth, height: 1.5)
                    .offset(x: x, y: y)

                Text(timeText(minute))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
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
                    .offset(x: labelX, y: labelY)
            }
            .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(90)
        }
    }

    @ViewBuilder
    private func moveTimeGuide(dayWidth: CGFloat, totalWidth: CGFloat, timedSegments: [WeekTimedPlanSegment]) -> some View {
        if activeResizeEdge == nil,
           !movingDrafts.isEmpty,
           let selectedPlanID,
           let segment = timedSegments.first(where: { $0.plan.id == selectedPlanID }),
           !store.isPlanScheduleLocked(segment.plan) {
            let minute = segment.startMinute
            let y = yOffset(for: minute)
            let x = dayX(segment.dayIndex, dayWidth: dayWidth)
            let color = planColor(segment.plan)
            let labelX = min(
                max(x + 2, hourColumnWidth + 1),
                max(hourColumnWidth + 1, totalWidth - 45)
            )
            let labelY = max(0, min(timelineHeight - 20, y - 11))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(color.opacity(0.82))
                    .frame(width: dayWidth, height: 1.3)
                    .offset(x: x, y: y)

                Text(timeText(minute))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
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
                    .offset(x: labelX, y: labelY)
            }
            .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(85)
        }
    }

    private func resizeHitHandle() -> some View {
        Color.white
            .opacity(0.001)
            .frame(height: WeekTimedPlanBlockMetrics.resizeHitHandleHeight)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func currentTimeLine(dayWidth: CGFloat, totalWidth: CGFloat) -> some View {
        if let currentDayIndex, let currentMinute {
            let y = yOffset(for: currentMinute)
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: dayX(currentDayIndex, dayWidth: dayWidth) - 4)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: dayWidth, height: 1.5)
                    .offset(x: dayX(currentDayIndex, dayWidth: dayWidth) - 8)
            }
            .offset(y: y)
            .allowsHitTesting(false)
        }
    }

    private var currentRenderCache: WeekTimelineRenderCache {
        if let renderCache = interactionScratch.renderCache,
           renderCache.key == renderCacheKey {
            return renderCache
        }
        let cache = makeRenderCache(for: renderCacheKey)
        interactionScratch.renderCache = cache
        return cache
    }

    private func refreshRenderCache() {
        let cache = makeRenderCache(for: renderCacheKey)
        interactionScratch.renderCache = cache
        resetSelectionIfHidden(visiblePlanIDs: cache.snapshot.visibleTimedPlanIDs)
    }

    private func makeRenderCache(for key: WeekTimelineRenderCacheKey) -> WeekTimelineRenderCache {
        let days = days
        // Hidden memos must not create hit targets, stretch the time axis, or enter
        // weekly selection/drag calculations. They remain available in day views.
        let sortedPlans = plans.filter { !$0.isMemo }.sorted {
            if $0.startTime == $1.startTime {
                return $0.createdAt < $1.createdAt
            }
            return $0.startTime < $1.startTime
        }
        let displayPlans: [PlanBlock]
        if let visibleCategoryIDs {
            displayPlans = sortedPlans.filter { plan in
                guard let categoryID = plan.category?.id else { return false }
                return visibleCategoryIDs.contains(categoryID)
            }
        } else {
            displayPlans = sortedPlans
        }
        let timedSegments = timedSegments(from: displayPlans, days: days, drafts: [:], identityDays: [:])
        let axisProfile = TimelineAxisProfile(
            intervals: timedSegments.map {
                TimelineAxisInterval(
                    startMinute: $0.startMinute,
                    endMinute: $0.endMinute
                )
            },
            minimumIntervalHeight: WeekTimedPlanBlockMetrics.minimumReadableHeight
        )
        let allDayPlansByDay = allDayPlansByDay(from: displayPlans, days: days)
        let snapshot = WeekTimelineRenderSnapshot(
            days: days,
            timedSegments: timedSegments,
            allDayPlansByDay: allDayPlansByDay,
            allDayLaneHeight: allDayLaneHeight(for: allDayPlansByDay)
        )
        return WeekTimelineRenderCache(
            key: key,
            sortedPlans: sortedPlans,
            displayPlans: displayPlans,
            plansByID: Dictionary(uniqueKeysWithValues: sortedPlans.map { ($0.id, $0) }),
            timedSegmentsByPlanID: Dictionary(grouping: timedSegments) { $0.plan.id },
            axisProfile: axisProfile,
            snapshot: snapshot
        )
    }

    private var sortedPlans: [PlanBlock] {
        currentRenderCache.sortedPlans
    }

    private func renderSnapshot(using cache: WeekTimelineRenderCache) -> WeekTimelineRenderSnapshot {
        guard !movingDrafts.isEmpty else { return cache.snapshot }

        let dynamicTimedSegments = cache.displayPlans
            .filter { !$0.isAllDay }
            .flatMap { plan -> [WeekTimedPlanSegment] in
                guard movingDrafts[plan.id] != nil else {
                    return cache.timedSegmentsByPlanID[plan.id] ?? []
                }
                return timedSegments(
                    from: [plan],
                    days: cache.snapshot.days,
                    drafts: movingDrafts,
                    identityDays: movingSegmentIdentityDayByPlanID
                )
            }

        return WeekTimelineRenderSnapshot(
            days: cache.snapshot.days,
            timedSegments: dynamicTimedSegments,
            allDayPlansByDay: cache.snapshot.allDayPlansByDay,
            allDayLaneHeight: cache.snapshot.allDayLaneHeight
        )
    }

    private func segmentFrame(_ segment: WeekTimedPlanSegment, dayWidth: CGFloat) -> CGRect {
        CGRect(x: dayX(segment.dayIndex, dayWidth: dayWidth) + blockInset,
               y: yOffset(for: segment.startMinute), width: max(1, dayWidth - blockInset * 2),
               height: height(startMinute: segment.startMinute, endMinute: segment.endMinute))
    }

    private func timedSegments(
        from displayPlans: [PlanBlock],
        days: [Date],
        drafts: [UUID: WeekPlanMoveDraft],
        identityDays: [UUID: Int]
    ) -> [WeekTimedPlanSegment] {
        displayPlans
            .filter { !$0.isAllDay }
            .flatMap { plan in
                let effectiveStart = drafts[plan.id]?.startTime ?? plan.startTime
                let effectiveEnd = drafts[plan.id]?.endTime ?? plan.endTime
                return days.enumerated().compactMap { dayIndex, day -> WeekTimedPlanSegment? in
                    let dayStart = calendar.startOfDay(for: day)
                    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                          effectiveStart < dayEnd,
                          effectiveEnd > dayStart
                    else { return nil }
                    let clippedStart = max(effectiveStart, dayStart)
                    let clippedEnd = min(effectiveEnd, dayEnd)
                    guard clippedEnd > clippedStart else { return nil }
                    let startMinute = minute(from: clippedStart, dayStart: dayStart)
                    let endMinute = max(startMinute + 1, minute(from: clippedEnd, dayStart: dayStart))
                    return WeekTimedPlanSegment(
                        plan: plan,
                        dayIndex: dayIndex,
                        identityDayIndex: identityDays[plan.id] ?? dayIndex,
                        startMinute: startMinute,
                        endMinute: min(24 * 60, endMinute)
                    )
                }
            }
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekStart: Date {
        Self.weekInterval(containing: anchorDate).start
    }

    private var weekEnd: Date {
        Self.weekInterval(containing: anchorDate).end
    }

    private func allDayLaneHeight(for allDayPlansByDay: [Date: [PlanBlock]]) -> CGFloat {
        let visibleCounts = allDayPlansByDay.values.map { min($0.count, allDayVisibleRowLimit) }
        let maxVisibleCount = visibleCounts.max() ?? 0
        guard maxVisibleCount > 0 else { return 1 }
        return allDayLaneVerticalPadding * 2
            + CGFloat(maxVisibleCount) * allDayItemHeight
            + CGFloat(max(maxVisibleCount - 1, 0)) * allDayItemSpacing
    }

    private var allDayVisibleRowLimit: Int {
        2
    }

    private var allDayItemHeight: CGFloat {
        13
    }

    private var allDayItemSpacing: CGFloat {
        1.5
    }

    private var allDayLaneVerticalPadding: CGFloat {
        2
    }

    private var timelineHeight: CGFloat {
        timelineTopInset + timelineAxisMap.contentHeight
    }

    private var shouldDisableTimelineScroll: Bool {
        gesturePlanID != nil || zoomGestureIsActive ||
            presetDragIsActive ||
            creationGestureIsActive ||
            creationDraft != nil ||
            !movingDrafts.isEmpty ||
            resizeBaseline != nil ||
            activeResizeEdge != nil
    }

    private var currentDayIndex: Int? {
        days.firstIndex { calendar.isDateInToday($0) }
    }

    private var currentMinute: Int? {
        guard currentDayIndex != nil else { return nil }
        return minute(from: Date(), dayStart: calendar.startOfDay(for: Date()))
    }

    private var selectedCategory: Category? {
        categories.first { $0.id == selectedCategoryID } ?? categories.first
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

    private func allDayPlansByDay(from displayPlans: [PlanBlock], days: [Date]) -> [Date: [PlanBlock]] {
        var result = Dictionary(uniqueKeysWithValues: days.map { ($0, [PlanBlock]()) })
        let dayIntervals = days.map { day -> (day: Date, interval: DateInterval)? in
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            return (day, DateInterval(start: dayStart, end: dayEnd))
        }

        for plan in displayPlans where plan.isAllDay {
            for dayInterval in dayIntervals {
                guard let dayInterval,
                      plan.startTime < dayInterval.interval.end,
                      plan.endTime > dayInterval.interval.start
                else { continue }
                result[dayInterval.day, default: []].append(plan)
            }
        }
        return result
    }

    private func planColor(_ plan: PlanBlock) -> Color {
        plan.category?.displayColor ?? LiminalTheme.accent
    }

    private func dayX(_ index: Int, dayWidth: CGFloat) -> CGFloat {
        hourColumnWidth + CGFloat(index) * (dayWidth + daySpacing)
    }

    private func dayIndex(forX x: CGFloat, dayWidth: CGFloat) -> Int? {
        let relativeX = x - hourColumnWidth
        guard relativeX >= 0 else { return nil }
        let index = Int(relativeX / (dayWidth + daySpacing))
        guard (0..<days.count).contains(index) else { return nil }
        return index
    }

    private func yOffset(for minute: Int) -> CGFloat {
        timelineTopInset + timelineAxisMap.y(forMinute: minute)
    }

    private func height(startMinute: Int, endMinute: Int) -> CGFloat {
        timelineAxisMap.height(
            startMinute: startMinute,
            endMinute: endMinute
        )
    }

    private func weekResizeHandleWidth(dayWidth: CGFloat, timelineWidth: CGFloat) -> CGFloat {
        min(
            timelineWidth,
            max(
                dayWidth - blockInset * 2 + WeekTimedPlanBlockMetrics.resizeHandleHorizontalSlop * 2,
                WeekTimedPlanBlockMetrics.minimumResizeHandleWidth
            )
        )
    }

    private func snappedMinute(fromY y: CGFloat) -> Int {
        let raw = Int(timelineAxisMap.minute(atY: y - timelineTopInset).rounded())
        let step = snapPrecision.minutes
        return min(24 * 60, max(0, (raw / step) * step))
    }

    private func snappedMinuteDelta(_ y: CGFloat, from originalMinute: Int) -> Int {
        let originalY = timelineAxisMap.y(forMinute: originalMinute)
        let targetMinute = timelineAxisMap.minute(atY: originalY + y)
        let raw = Int((targetMinute - CGFloat(originalMinute)).rounded())
        let step = snapPrecision.minutes
        return Int((Double(raw) / Double(step)).rounded()) * step
    }

    private func dragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        value.location.y - value.startLocation.y
    }

    private func resizeDragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        let startY = interactionScratch.resizeDragStartGlobalY ?? value.startLocation.y
        return value.location.y - startY
    }

    private func dragTranslation(_ value: DragGesture.Value) -> CGSize {
        value.translation
    }

    private func date(on day: Date, minute: Int) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minute * 60))
    }

    private func canCreatePlan(onDayIndex dayIndex: Int) -> Bool {
        guard days.indices.contains(dayIndex) else { return false }
        return store.canCreatePlan(startTime: days[dayIndex], isAllDay: false)
    }

    private func moveDrafts(for segment: WeekTimedPlanSegment, translation: CGSize, dayWidth: CGFloat, targetDay: Int? = nil) -> [UUID: WeekPlanMoveDraft]? {
        // SwiftUI refreshes the segment as its preview moves. Translation is cumulative,
        // so always apply it to the original segment, never the previous preview.
        let original = interactionScratch.moveBaseline ?? segment
        let originalDayIndex = original.dayIndex
        let duration = max(60.0, segment.plan.endTime.timeIntervalSince(segment.plan.startTime))
        let dayDelta = Int((translation.width / max(1, dayWidth + daySpacing)).rounded())
        let targetDayIndex = targetDay ?? max(0, min(days.count - 1, originalDayIndex + dayDelta))
        let originalMinute = original.startMinute
        let durationMinutes = max(1, Int((duration / 60).rounded()))
        let relativeDelta = snappedMinuteDelta(translation.height, from: originalMinute)
        let proposedMinute = TimelineSnapPolicy.alignedMinute(
            originalMinute: originalMinute,
            relativeDelta: relativeDelta,
            precision: snapPrecision
        )
        let clampedMinute = max(0, min(24 * 60 - durationMinutes, proposedMinute))
        let direction: PlanTimelinePushDirection = proposedMinute >= originalMinute ? .later : .earlier
        let request = WeekMoveRequest(
            dayIndex: targetDayIndex,
            proposedStartMinute: clampedMinute,
            proposedEndMinute: clampedMinute + durationMinutes,
            direction: direction
        )
        guard interactionScratch.lastMoveRequest != request else {
            return movingDrafts
        }
        interactionScratch.lastMoveRequest = request
        return resolvedDrafts(
            for: segment.plan,
            dayIndex: request.dayIndex,
            proposedStartMinute: request.proposedStartMinute,
            proposedEndMinute: request.proposedEndMinute,
            direction: request.direction,
            adjustment: .move
        )
    }

    private func applyAccessibilityMove(
        segment: WeekTimedPlanSegment,
        dayWidth: CGFloat,
        minuteDelta: Int,
        dayDelta: Int
    ) {
        guard selectedPlanID == segment.plan.id, !store.isPlanScheduleLocked(segment.plan) else { return }
        let translation = CGSize(
            width: CGFloat(dayDelta) * (dayWidth + daySpacing),
            height: timelineAxisMap.y(forMinute: segment.startMinute + minuteDelta)
                - timelineAxisMap.y(forMinute: segment.startMinute)
        )
        guard let drafts = moveDrafts(for: segment, translation: translation, dayWidth: dayWidth) else {
            operationError = "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
            LiminalHaptics.warning()
            return
        }
        finishScheduleDrafts(drafts, failureMessage: "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。")
    }

    private func applyAccessibilityResize(segment: WeekTimedPlanSegment, edge: WeekResizeEdge, minuteDelta: Int) {
        guard selectedPlanID == segment.plan.id, !store.isPlanScheduleLocked(segment.plan) else { return }
        let baseline = WeekResizeBaseline(segment: segment)
        let originalMinute = edge == .start ? baseline.startMinute : baseline.endMinute
        let translationY = timelineAxisMap.y(forMinute: originalMinute + minuteDelta)
            - timelineAxisMap.y(forMinute: originalMinute)
        guard let drafts = resizeDrafts(
            for: segment.plan,
            baseline: baseline,
            edge: edge,
            translationY: translationY
        ) else {
            operationError = "予定の長さを変更できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
            LiminalHaptics.warning()
            return
        }
        finishScheduleDrafts(drafts, failureMessage: "予定の長さを変更できませんでした。今日以前や収まりきらない玉突き移動は変更できません。")
    }

    private func resizeDrafts(
        for plan: PlanBlock,
        baseline: WeekResizeBaseline,
        edge: WeekResizeEdge,
        translationY: CGFloat
    ) -> [UUID: WeekPlanMoveDraft]? {
        guard days.indices.contains(baseline.dayIndex) else { return nil }
        let originalMinute = edge == .start ? baseline.startMinute : baseline.endMinute
        let relativeDelta = snappedMinuteDelta(translationY, from: originalMinute)
        let delta = TimelineSnapPolicy.alignedDelta(
            originalMinute: originalMinute,
            relativeDelta: relativeDelta,
            precision: snapPrecision
        )
        let resize = resizedBounds(
            from: baseline,
            edge: edge,
            delta: delta
        )
        let request = WeekResizeRequest(
            planID: plan.id,
            edge: edge,
            startMinute: resize.start,
            endMinute: resize.end
        )
        guard interactionScratch.lastResizeRequest != request else {
            return movingDrafts
        }
        interactionScratch.lastResizeRequest = request
        let drafts: [UUID: WeekPlanMoveDraft]?
        switch edge {
        case .start:
            drafts = resolvedDrafts(
                for: plan,
                dayIndex: baseline.dayIndex,
                proposedStartMinute: resize.start,
                proposedEndMinute: resize.end,
                direction: resize.direction,
                adjustment: .resizeStart
            )
        case .end:
            drafts = resolvedDrafts(
                for: plan,
                dayIndex: baseline.dayIndex,
                proposedStartMinute: resize.start,
                proposedEndMinute: resize.end,
                direction: resize.direction,
                adjustment: .resizeEnd
            )
        }
        return drafts
    }

    private func resizedBounds(
        from baseline: WeekResizeBaseline,
        edge: WeekResizeEdge,
        delta: Int
    ) -> (start: Int, end: Int, direction: PlanTimelinePushDirection) {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: baseline.startMinute,
            originalEndMinute: baseline.endMinute,
            edge: edge.timelineEdge,
            delta: delta,
            minimumDuration: minimumDurationMinutes
        )
        return (result.startMinute, result.endMinute, result.pushDirection)
    }

    private func resolvedDrafts(
        for editingPlan: PlanBlock,
        dayIndex: Int,
        proposedStartMinute: Int,
        proposedEndMinute: Int,
        direction: PlanTimelinePushDirection,
        adjustment: PlanTimelineAdjustment
    ) -> [UUID: WeekPlanMoveDraft]? {
        guard let baseline = dayScheduleBaseline(for: dayIndex) else { return nil }
        let day = days[dayIndex]

        // The persisted day layout is stable for the duration of one gesture.
        // Reuse it and replace only the actively edited interval instead of
        // rebuilding both arrays from every plan at each snap step.
        var intervals = baseline.intervals.filter { $0.id != editingPlan.id }
        intervals.append(
            PlanTimelineInterval(
                id: editingPlan.id,
                startMinute: proposedStartMinute,
                endMinute: proposedEndMinute,
                isLocked: store.isPlanScheduleLocked(editingPlan) || !isPlanVisible(editingPlan), isMemo: editingPlan.isMemo
            )
        )

        let effectiveMinimumDuration = adjustment == .move
            ? max(1, proposedEndMinute - proposedStartMinute)
            : minimumDurationMinutes
        guard let resolved = PlanTimelineRescheduler.resolveClamped(items: intervals, editingID: editingPlan.id,
            proposedStartMinute: proposedStartMinute, proposedEndMinute: proposedEndMinute, pushDirection: direction,
            adjustment: adjustment, minimumDuration: effectiveMinimumDuration) else {
            return nil
        }

        let changedIntervals = PlanTimelineRescheduler.changedIntervals(
            in: resolved,
            comparedTo: baseline.originalIntervalsByID
        )
        return Dictionary(
            uniqueKeysWithValues: changedIntervals.map { interval -> (UUID, WeekPlanMoveDraft) in
                return (
                    interval.id,
                    WeekPlanMoveDraft(
                        planID: interval.id,
                        startTime: date(on: day, minute: interval.startMinute),
                        endTime: date(on: day, minute: interval.endMinute)
                    )
                )
            }
        )
    }

    private func dayScheduleBaseline(for dayIndex: Int) -> WeekTimelineDayScheduleBaseline? {
        if let cached = interactionScratch.dayScheduleBaselines[dayIndex] {
            return cached
        }
        guard days.indices.contains(dayIndex) else { return nil }
        let dayStart = calendar.startOfDay(for: days[dayIndex])
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var originalsByID: [UUID: PlanTimelineInterval] = [:]
        var collisionIntervals: [PlanTimelineInterval] = []
        collisionIntervals.reserveCapacity(sortedPlans.count)

        for plan in sortedPlans where !plan.isAllDay {
            guard plan.startTime < dayEnd, plan.endTime > dayStart else { continue }
            let clippedStart = max(plan.startTime, dayStart)
            let clippedEnd = min(plan.endTime, dayEnd)
            guard clippedEnd > clippedStart else { continue }
            let original = PlanTimelineInterval(
                id: plan.id,
                startMinute: minute(from: clippedStart, dayStart: dayStart),
                endMinute: minute(from: clippedEnd, dayStart: dayStart), isMemo: plan.isMemo
            )
            originalsByID[plan.id] = original
            collisionIntervals.append(
                PlanTimelineInterval(
                    id: original.id,
                    startMinute: original.startMinute,
                    endMinute: original.endMinute,
                    isLocked: store.isPlanScheduleLocked(plan) || !isPlanVisible(plan), isMemo: plan.isMemo
                )
            )
        }

        let baseline = WeekTimelineDayScheduleBaseline(
            originalIntervalsByID: originalsByID,
            intervals: collisionIntervals
        )
        interactionScratch.dayScheduleBaselines[dayIndex] = baseline
        return baseline
    }

    private func finishScheduleDrafts(_ drafts: [UUID: WeekPlanMoveDraft], failureMessage: String) {
        defer {
            resetScheduleGestureState()
        }
        let changes = scheduleChanges(from: drafts)
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

    private func resetInteractionState() {
        selectedPlanID = nil
        planPendingDeletion = nil
        creationDraft = nil
        operationError = nil
        resetScheduleGestureState()
    }

    private func resetSelectionIfHidden(visiblePlanIDs: Set<UUID>) {
        guard let selectedPlanID, !visiblePlanIDs.contains(selectedPlanID) else { return }
        resetInteractionState()
    }

    private func resetScheduleGestureState() {
        creationGestureIsActive = false
        movingDrafts = [:]
        gesturePlanID = nil
        dragTargetDayIndex = nil
        movingSegmentIdentityDayByPlanID = [:]
        resizeBaseline = nil
        activeResizeEdge = nil
        interactionScratch.resetScheduleGesture()
        isScheduleInteractionActive = false
    }

    private func warnOnceDuringScheduleGesture() {
        guard !interactionScratch.didWarnDuringScheduleGesture else { return }
        interactionScratch.didWarnDuringScheduleGesture = true
        LiminalHaptics.warning()
    }

    private func markScheduleInteractionActive() {
        guard !isScheduleInteractionActive else { return }
        isScheduleInteractionActive = true
    }

    private func updateMovingDrafts(_ drafts: [UUID: WeekPlanMoveDraft]) {
        guard movingDrafts != drafts else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            movingDrafts = drafts
        }
    }

    private func scheduleChanges(from drafts: [UUID: WeekPlanMoveDraft]) -> [PlanStore.ScheduleChange] {
        let plansByID = currentRenderCache.plansByID
        return drafts.values.compactMap { draft in
            guard let plan = plansByID[draft.planID],
                  plan.startTime != draft.startTime || plan.endTime != draft.endTime
            else { return nil }
            return .init(plan: plan, startTime: draft.startTime, endTime: draft.endTime)
        }
    }

    private func isPlanVisible(_ plan: PlanBlock) -> Bool {
        guard let visibleCategoryIDs else { return true }
        guard let categoryID = plan.category?.id else { return false }
        return visibleCategoryIDs.contains(categoryID)
    }

    private func minute(from date: Date, dayStart: Date) -> Int {
        let seconds = max(0, min(24 * 60 * 60, date.timeIntervalSince(dayStart)))
        return Int((seconds / 60).rounded())
    }

    private func timeRangeText(_ segment: WeekTimedPlanSegment) -> String {
        "\(timeText(segment.startMinute))–\(timeText(segment.endMinute))"
    }

    private func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func hourLabel(_ hour: Int) -> String {
        TimelineHourAxisMetrics.label(for: hour)
    }

    private func hourTickCenterY(_ hour: Int) -> CGFloat {
        let rawY = yOffset(for: hour * 60)
        return min(max(0.5, rawY), max(0.5, timelineHeight - 0.5))
    }

    private func hourLabelCenterY(forTickY tickY: CGFloat) -> CGFloat {
        min(max(hourLabelHeight / 2, tickY), max(hourLabelHeight / 2, timelineHeight - hourLabelHeight / 2))
    }

    private func dayNumberText(_ day: Date) -> String {
        "\(calendar.component(.day, from: day))"
    }

    private func weekdayText(_ day: Date) -> String {
        let index = calendar.component(.weekday, from: day) - 1
        return Calendar.japaneseShortWeekdaySymbols[max(0, min(index, Calendar.japaneseShortWeekdaySymbols.count - 1))]
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    private func weekdayColor(_ day: Date) -> Color {
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return LiminalTheme.secondaryText
    }

    private func dayNumberColor(_ day: Date) -> Color {
        isToday(day) ? .white : weekdayColor(day)
    }

    private func dayHeaderBackground(_ day: Date) -> Color {
        isToday(day) ? LiminalTheme.accent.opacity(0.08) : timelineBackground
    }

    private func dayColumnBackground(_ day: Date) -> Color {
        isToday(day) ? todayColumnBackground : timelineBackground
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

    private var todayColumnBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : LiminalTheme.accent.opacity(0.055)
    }

    private var timelineStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    private var gridLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.13)
    }

    private var primaryLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.16)
    }

    private var secondaryLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    private var timeText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.52)
    }

    static func weekInterval(containing date: Date) -> DateInterval {
        Calendar.japanese.dateInterval(of: .weekOfYear, for: date) ?? {
            let dayStart = Calendar.japanese.startOfDay(for: date)
            let end = Calendar.japanese.date(byAdding: .day, value: 7, to: dayStart) ?? dayStart
            return DateInterval(start: dayStart, end: end)
        }()
    }
}

private struct WeekTimedPlanSegment: Identifiable {
    let plan: PlanBlock
    let dayIndex: Int
    let identityDayIndex: Int
    let startMinute: Int
    let endMinute: Int

    var id: String {
        // Keep identity stable while dragging; changing this mid-gesture cancels the drag.
        "\(plan.id.uuidString)-\(identityDayIndex)"
    }
}

private struct WeekPlanCreationDraft {
    let dayIndex: Int
    let startMinute: Int
    let endMinute: Int
}

private struct WeekPlanMoveDraft: Equatable {
    let planID: UUID
    let startTime: Date
    let endTime: Date
}

private struct WeekResizeBaseline {
    let planID: UUID
    let dayIndex: Int
    let startMinute: Int
    let endMinute: Int

    init(segment: WeekTimedPlanSegment) {
        planID = segment.plan.id
        dayIndex = segment.dayIndex
        startMinute = segment.startMinute
        endMinute = segment.endMinute
    }
}

private struct WeekResizeRequest: Equatable {
    let planID: UUID
    let edge: WeekResizeEdge
    let startMinute: Int
    let endMinute: Int
}

private enum WeekResizeEdge: Equatable {
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

private struct WeekMoveFeedbackStep: Equatable {
    let dayIndex: Int
    let minute: Int
}

private enum WeekTimedPlanBlockMetrics {
    static let minimumReadableHeight: CGFloat = 18
    static let verticalOverflow: CGFloat = 34
    static let resizeHandleHeight: CGFloat = 40
    static let resizeHitHandleHeight: CGFloat = 38
    static let resizeHandleEdgeOutset: CGFloat = 6
    static let resizeHandleEdgeOverlap: CGFloat = 0
    static let creationHitSlop: CGFloat = 4
    static let resizeGripBackgroundHeight: CGFloat = 20
    static let resizeGripHeight: CGFloat = 6.5
    static let resizeHandleHorizontalSlop: CGFloat = 12
    static let minimumResizeHandleWidth: CGFloat = 72
    static let visibleResizeHandleWidth: CGFloat = 34
}

#Preview("Week Timeline") {
    CalendarWeekTimelineView(
        anchorDate: Date(),
        categories: [],
        planPresets: [],
        visibleCategoryIDs: nil,
        plans: [],
        planTitleFontSize: 6,
        planTitleBold: false,
        isInteractionEnabled: true,
        isPageSwipeActive: false,
        visibleHour: .constant(0),
        selectedCategoryID: .constant(nil),
        isScheduleInteractionActive: .constant(false),
        onOpenPlan: { _ in },
        onOpenDay: { _ in },
        onScheduleChanged: {}
    )
    .liminalogPreviewEnvironment()
}

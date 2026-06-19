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

private struct WeekTimelineScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct WeekTimelinePlanSignature: Hashable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let createdAt: Date
    let isAllDay: Bool
    let categoryID: UUID?
}

private struct WeekTimelineDraftSignature: Hashable {
    let planID: UUID
    let startTime: Date
    let endTime: Date
}

private struct WeekTimelineRenderCacheKey: Hashable {
    let weekStart: Date
    let visibleCategoryIDs: [UUID]?
    let plans: [WeekTimelinePlanSignature]
    let drafts: [WeekTimelineDraftSignature]
}

private struct WeekTimelineRenderCache {
    let key: WeekTimelineRenderCacheKey
    let sortedPlans: [PlanBlock]
    let displayPlans: [PlanBlock]
    let plansByID: [UUID: PlanBlock]
    let snapshot: WeekTimelineRenderSnapshot
}

struct CalendarWeekTimelineView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    let anchorDate: Date
    let categories: [Category]
    let visibleCategoryIDs: Set<UUID>?
    let plans: [PlanBlock]
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let isInteractionEnabled: Bool
    let isPageSwipeActive: Bool
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onOpenPlan: (PlanBlock) -> Void
    let onOpenDay: (Date) -> Void
    let onScheduleChanged: () -> Void

    @State private var selectedPlanID: UUID?
    @State private var creationDraft: WeekPlanCreationDraft?
    @State private var creationGestureIsActive = false
    @State private var movingDrafts: [UUID: WeekPlanMoveDraft] = [:]
    @State private var movingSegmentIdentityDayByPlanID: [UUID: Int] = [:]
    @State private var resizeBaseline: WeekResizeBaseline?
    @State private var resizeMinimumLock: WeekResizeMinimumLock?
    @State private var activeResizeEdge: WeekResizeEdge?
    @State private var operationError: String?
    @State private var planPendingDeletion: PlanBlock?
    @State private var didWarnDuringScheduleGesture = false
    @State private var lastMoveFeedbackStep: WeekMoveFeedbackStep?
    @State private var lastResizeFeedbackMinute: Int?
    @State private var resizeDragStartGlobalY: CGFloat?
    @State private var renderCache: WeekTimelineRenderCache?

    private let calendar = Calendar.japanese
    private let hourColumnWidth: CGFloat = 50
    private let hourLabelHeight: CGFloat = 14
    private let timelineTopInset: CGFloat = 15
    private let daySpacing: CGFloat = 1
    private let blockInset: CGFloat = 1.5
    private let bottomScrollPadding: CGFloat = 24
    private let bottomChromeInset: CGFloat = 8
    private let minimumDurationMinutes = 15
    private let hourHeight: CGFloat = 29
    private let creationLongPressDuration = 0.28
    private let creationLongPressMaximumDistance: CGFloat = 28
    private let creationHorizontalCancelDistance: CGFloat = 22
    private let creationVerticalIntentRatio: CGFloat = 0.8

    init(
        anchorDate: Date,
        categories: [Category],
        visibleCategoryIDs: Set<UUID>?,
        plans: [PlanBlock],
        planTitleFontSize: Double,
        planTitleBold: Bool,
        isInteractionEnabled: Bool,
        isPageSwipeActive: Bool,
        visibleHour: Binding<Int>,
        selectedCategoryID: Binding<UUID?>,
        isScheduleInteractionActive: Binding<Bool>,
        onOpenPlan: @escaping (PlanBlock) -> Void,
        onOpenDay: @escaping (Date) -> Void,
        onScheduleChanged: @escaping () -> Void
    ) {
        self.anchorDate = Calendar.japanese.startOfDay(for: anchorDate)
        self.categories = categories
        self.visibleCategoryIDs = visibleCategoryIDs
        self.plans = plans
        self.planTitleFontSize = planTitleFontSize
        self.planTitleBold = planTitleBold
        self.isInteractionEnabled = isInteractionEnabled
        self.isPageSwipeActive = isPageSwipeActive
        self._visibleHour = visibleHour
        self._selectedCategoryID = selectedCategoryID
        self._isScheduleInteractionActive = isScheduleInteractionActive
        self.onOpenPlan = onOpenPlan
        self.onOpenDay = onOpenDay
        self.onScheduleChanged = onScheduleChanged
    }

    var body: some View {
        GeometryReader { proxy in
            let cache = currentRenderCache
            let snapshot = cache.snapshot
            let totalWidth = proxy.size.width
            let dayWidth = max(1, (totalWidth - hourColumnWidth - daySpacing * 6) / 7)
            let timelineViewportHeight = max(1, proxy.size.height - 46 - snapshot.allDayLaneHeight)

            VStack(spacing: 0) {
                weekHeader(dayWidth: dayWidth, totalWidth: totalWidth, snapshot: snapshot)

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            scrollOffsetReader

                            ZStack(alignment: .topLeading) {
                                timelineGridLayer(dayWidth: dayWidth, totalWidth: totalWidth, snapshot: snapshot)
                                hourScrollTargets

                                if isInteractionEnabled, let creationDraft {
                                    creationDraftView(draft: creationDraft, dayWidth: dayWidth)
                                    creationTimeGuide(draft: creationDraft, dayWidth: dayWidth, totalWidth: totalWidth)
                                }

                                ForEach(snapshot.timedSegments) { segment in
                                    timedPlanBlock(segment: segment, dayWidth: dayWidth)
                                }

                                if isInteractionEnabled {
                                    moveTimeGuide(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    resizeTimeGuide(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    resizeInteractionLayer(dayWidth: dayWidth, totalWidth: totalWidth, timedSegments: snapshot.timedSegments)

                                    currentTimeLine(dayWidth: dayWidth, totalWidth: totalWidth)

                                    deleteConfirmationBubble(
                                        dayWidth: dayWidth,
                                        totalWidth: totalWidth,
                                        timedSegments: snapshot.timedSegments
                                    )
                                }
                            }
                            .frame(width: totalWidth, height: timelineHeight, alignment: .topLeading)
                            .contentShape(Rectangle())

                            Color.clear
                                .frame(height: bottomScrollPadding)
                        }
                    }
                    .coordinateSpace(name: scrollCoordinateSpaceName)
                    .frame(width: totalWidth, height: timelineViewportHeight)
                    .scrollDisabled(shouldDisableTimelineScroll || isPageSwipeActive)
                    .scrollIndicators(.visible)
                    .background(timelineBackground)
                    .onAppear {
                        scrollToVisibleHour(with: scrollProxy)
                    }
                    .onChange(of: visibleHour) { _, _ in
                        guard !isInteractionEnabled else { return }
                        scrollToVisibleHour(with: scrollProxy)
                    }
                    .onPreferenceChange(WeekTimelineScrollOffsetPreferenceKey.self) { minY in
                        updateVisibleHour(fromScrollMinY: minY)
                    }
                    .onChange(of: anchorDate) { _, _ in
                        resetInteractionState()
                        scrollToVisibleHour(with: scrollProxy)
                    }
                    .onChange(of: snapshot.visibleTimedPlanIDs) { _, visiblePlanIDs in
                        resetSelectionIfHidden(visiblePlanIDs: visiblePlanIDs)
                    }
                }
            }
            .frame(width: totalWidth, height: proxy.size.height, alignment: .top)
            .background(timelineBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(timelineStroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, bottomChromeInset)
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first?.id
            }
            refreshRenderCache()
        }
        .onChange(of: categories.map(\.id)) { _, newIDs in
            if let selectedCategoryID, newIDs.contains(selectedCategoryID) {
                return
            }
            selectedCategoryID = categories.first?.id
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
    }

    private var scrollCoordinateSpaceName: String {
        "WeekTimelineScroll-\(weekStart.timeIntervalSinceReferenceDate)"
    }

    private var scrollOffsetReader: some View {
        Color.clear
            .frame(height: 0)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WeekTimelineScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(scrollCoordinateSpaceName)).minY
                    )
                }
            )
    }

    private var hourScrollTargets: some View {
        ForEach(0...23, id: \.self) { hour in
            Color.clear
                .frame(width: 1, height: 1)
                .id(hour)
                .offset(x: hourColumnWidth, y: yOffset(for: hour * 60))
                .allowsHitTesting(false)
        }
    }

    private func scrollToVisibleHour(with proxy: ScrollViewProxy) {
        let targetHour = min(23, max(0, visibleHour))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(targetHour, anchor: .top)
        }
    }

    private func updateVisibleHour(fromScrollMinY minY: CGFloat) {
        guard isInteractionEnabled,
              !isPageSwipeActive,
              !shouldDisableTimelineScroll
        else { return }

        let scrollOffset = max(0, -minY - timelineTopInset)
        let hour = min(23, max(0, Int((scrollOffset / hourHeight).rounded())))
        if visibleHour != hour {
            visibleHour = hour
        }
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
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(timelineBackground)
                .frame(width: totalWidth, height: timelineHeight)

            Rectangle()
                .fill(hourColumnBackground)
                .frame(width: hourColumnWidth, height: timelineHeight)

            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Rectangle()
                    .fill(dayColumnBackground(day))
                    .frame(width: dayWidth, height: timelineHeight)
                    .offset(x: dayX(index, dayWidth: dayWidth))
            }

            ForEach(0...7, id: \.self) { index in
                Rectangle()
                    .fill(gridLine)
                    .frame(width: 1, height: timelineHeight)
                    .offset(x: hourColumnWidth + CGFloat(index) * (dayWidth + daySpacing) - daySpacing)
            }

            ForEach(0...24, id: \.self) { hour in
                let tickY = hourTickCenterY(hour)
                Rectangle()
                    .fill(primaryLine)
                    .frame(width: max(0, totalWidth - hourColumnWidth), height: 1)
                    .position(
                        x: hourColumnWidth + max(0, totalWidth - hourColumnWidth) / 2,
                        y: tickY
                    )

                if hour < 24 {
                    Rectangle()
                        .fill(secondaryLine)
                        .frame(width: max(0, totalWidth - hourColumnWidth), height: 1)
                        .position(
                            x: hourColumnWidth + max(0, totalWidth - hourColumnWidth) / 2,
                            y: yOffset(for: hour * 60 + 30)
                        )
                }

                if hour < 24 {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(timeText)
                        .frame(width: hourColumnWidth - 9, height: hourLabelHeight, alignment: .trailing)
                        .position(
                            x: (hourColumnWidth - 9) / 2,
                            y: hourLabelCenterY(forTickY: tickY)
                        )
                }
            }
        }
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
    private func timedPlanBlock(segment: WeekTimedPlanSegment, dayWidth: CGFloat) -> some View {
        let color = planColor(segment.plan)
        let blockHeight = segment.height(hourHeight: hourHeight)
        let isSelected = selectedPlanID == segment.plan.id
        let isLocked = store.isPlanScheduleLocked(segment.plan)
        let overflow = WeekTimedPlanBlockMetrics.verticalOverflow
        let title = displayTitle(for: segment.plan)
        let cardWidth = max(1, dayWidth - blockInset * 2)

        let block = ZStack(alignment: .top) {
            weekPlanCard(
                segment: segment,
                dayWidth: dayWidth,
                blockHeight: blockHeight,
                color: color,
                isSelected: isSelected,
                isLocked: isLocked,
                activeResizeEdge: isSelected ? activeResizeEdge : nil
            )
                .onTapGesture {
                    handleSegmentTap(segment)
                }
                .simultaneousGesture(deleteLongPressGesture(for: segment))
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
        .offset(
            x: dayX(segment.dayIndex, dayWidth: dayWidth) + blockInset,
            y: yOffset(for: segment.startMinute) - overflow
        )
        .zIndex(isSelected ? 10 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(timeRangeText(segment))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleSegmentTap(segment)
        }
        .accessibilityAction(named: Text("詳細を編集")) {
            onOpenPlan(segment.plan)
        }

        if isSelected && !isLocked {
            block
                .accessibilityAction(named: Text("15分早める")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: -15, dayDelta: 0)
                }
                .accessibilityAction(named: Text("15分遅らせる")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: 15, dayDelta: 0)
                }
                .accessibilityAction(named: Text("前日に移動")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: 0, dayDelta: -1)
                }
                .accessibilityAction(named: Text("翌日に移動")) {
                    applyAccessibilityMove(segment: segment, dayWidth: dayWidth, minuteDelta: 0, dayDelta: 1)
                }
                .accessibilityAction(named: Text("開始を15分早める")) {
                    applyAccessibilityResize(segment: segment, edge: .start, minuteDelta: -15)
                }
                .accessibilityAction(named: Text("開始を15分遅らせる")) {
                    applyAccessibilityResize(segment: segment, edge: .start, minuteDelta: 15)
                }
                .accessibilityAction(named: Text("終了を15分早める")) {
                    applyAccessibilityResize(segment: segment, edge: .end, minuteDelta: -15)
                }
                .accessibilityAction(named: Text("終了を15分遅らせる")) {
                    applyAccessibilityResize(segment: segment, edge: .end, minuteDelta: 15)
                }
        } else {
            block
        }
    }

    private func handleSegmentTap(_ segment: WeekTimedPlanSegment) {
        guard planPendingDeletion?.id != segment.plan.id else { return }
        if selectedPlanID == segment.plan.id {
            onOpenPlan(segment.plan)
        } else {
            LiminalHaptics.selection()
            selectedPlanID = segment.plan.id
        }
    }

    private func deleteLongPressGesture(for segment: WeekTimedPlanSegment) -> some Gesture {
        LongPressGesture(
            minimumDuration: WeekTimedPlanBlockMetrics.deleteLongPressDuration,
            maximumDistance: WeekTimedPlanBlockMetrics.deleteLongPressMaximumDistance
        )
        .onEnded { completed in
            guard completed else { return }
            requestDeletePlan(segment.plan)
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
        activeResizeEdge: WeekResizeEdge?
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
                .strokeBorder(isSelected ? .white.opacity(activeResizeEdge == nil ? 0.92 : 0.98) : color.opacity(0.62), lineWidth: isSelected ? (activeResizeEdge == nil ? 1.6 : 2.2) : 1)
        )
        .shadow(color: .clear, radius: 0)
        .contentShape(Rectangle())
        .accessibilityHidden(true)

        if isSelected && !isLocked && activeResizeEdge == nil {
            card.highPriorityGesture(moveGesture(for: segment, dayWidth: dayWidth))
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
        let blockHeight = height(startMinute: draft.startMinute, endMinute: draft.endMinute)
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
        .offset(x: dayX(draft.dayIndex, dayWidth: dayWidth) + blockInset, y: yOffset(for: draft.startMinute))
        .allowsHitTesting(false)
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
        defer {
            creationDraft = nil
            resetScheduleGestureState()
        }
        guard completed,
              isCreationDragDirection(startLocation: startLocation, location: location),
              updateCreationDraft(startLocation: startLocation, location: location, dayWidth: dayWidth, timedSegments: timedSegments)
        else { return }
        commitCreationDraft()
    }

    @discardableResult
    private func updateCreationDraft(
        startLocation: CGPoint,
        location: CGPoint,
        dayWidth: CGFloat,
        timedSegments: [WeekTimedPlanSegment]
    ) -> Bool {
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
            intervals: creationCollisionIntervals(onDayIndex: dayIndex)
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
        anchorMinute: Int,
        currentMinute: Int,
        intervals: [PlanTimelineInterval]
    ) -> (start: Int, end: Int)? {
        let minimumDuration = 15
        guard !intervals.contains(where: { $0.startMinute < anchorMinute && anchorMinute < $0.endMinute }) else {
            return nil
        }

        if currentMinute >= anchorMinute {
            let desiredEnd = min(
                PlanTimelineRescheduler.dayEndMinute,
                max(currentMinute, anchorMinute + minimumDuration)
            )
            let nextBlockedStart = intervals
                .filter { $0.startMinute >= anchorMinute }
                .map(\.startMinute)
                .min() ?? PlanTimelineRescheduler.dayEndMinute
            let end = min(desiredEnd, nextBlockedStart)
            guard end - anchorMinute >= minimumDuration else { return nil }
            return (anchorMinute, end)
        } else {
            let desiredStart = max(0, min(currentMinute, anchorMinute - minimumDuration))
            let previousBlockedEnd = intervals
                .filter { $0.endMinute <= anchorMinute }
                .map(\.endMinute)
                .max() ?? 0
            let start = max(desiredStart, previousBlockedEnd)
            guard anchorMinute - start >= minimumDuration else { return nil }
            return (start, anchorMinute)
        }
    }

    private func creationCollisionIntervals(onDayIndex dayIndex: Int) -> [PlanTimelineInterval] {
        guard days.indices.contains(dayIndex) else { return [] }
        let dayStart = calendar.startOfDay(for: days[dayIndex])
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return sortedPlans
            .filter { !$0.isAllDay }
            .compactMap { plan -> PlanTimelineInterval? in
                guard plan.startTime < dayEnd, plan.endTime > dayStart else { return nil }
                let clippedStart = max(plan.startTime, dayStart)
                let clippedEnd = min(plan.endTime, dayEnd)
                guard clippedEnd > clippedStart else { return nil }
                return PlanTimelineInterval(
                    id: plan.id,
                    startMinute: minute(from: clippedStart, dayStart: dayStart),
                    endMinute: minute(from: clippedEnd, dayStart: dayStart)
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

    private func requestDeletePlan(_ plan: PlanBlock) {
        guard selectedPlanID == plan.id,
              !store.isPlanScheduleLocked(plan),
              movingDrafts.isEmpty,
              resizeBaseline == nil,
              activeResizeEdge == nil
        else { return }
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
            let x = dayX(segment.dayIndex, dayWidth: dayWidth) + blockInset
            let y = yOffset(for: segment.startMinute)
            let width = max(1, dayWidth - blockInset * 2)
            let height = segment.height(hourHeight: hourHeight)
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
        let centeredX = dayX(segment.dayIndex, dayWidth: dayWidth) + dayWidth / 2 - handleWidth / 2
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
        guard selectedPlanID != nil,
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

    @ViewBuilder
    private func deleteConfirmationBubble(
        dayWidth: CGFloat,
        totalWidth: CGFloat,
        timedSegments: [WeekTimedPlanSegment]
    ) -> some View {
        if let plan = planPendingDeletion,
           let segment = timedSegments.first(where: { $0.plan.id == plan.id }) {
            let cardWidth = max(1, dayWidth - blockInset * 2)
            let blockX = dayX(segment.dayIndex, dayWidth: dayWidth) + blockInset
            let blockY = yOffset(for: segment.startMinute)
            let blockHeight = height(startMinute: segment.startMinute, endMinute: segment.endMinute)
            let bubbleSize = deleteConfirmationBubbleSize(containerWidth: totalWidth)
            TimelineDeleteConfirmationBubble(
                onCancel: {
                    planPendingDeletion = nil
                },
                onDelete: {
                    deletePlan(plan)
                }
            )
            .frame(width: bubbleSize.width, height: bubbleSize.height)
            .position(
                deleteConfirmationBubbleCenter(
                    anchorX: blockX + cardWidth / 2,
                    blockY: blockY,
                    blockHeight: blockHeight,
                    containerWidth: totalWidth,
                    bubbleSize: bubbleSize
                )
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .zIndex(240)
        }
    }

    private func deleteConfirmationBubbleSize(containerWidth: CGFloat) -> CGSize {
        CGSize(
            width: min(max(180, containerWidth - 24), TimelineDeleteConfirmationBubble.preferredWidth),
            height: TimelineDeleteConfirmationBubble.preferredHeight
        )
    }

    private func deleteConfirmationBubbleCenter(
        anchorX: CGFloat,
        blockY: CGFloat,
        blockHeight: CGFloat,
        containerWidth: CGFloat,
        bubbleSize: CGSize
    ) -> CGPoint {
        let horizontalInset: CGFloat = 10
        let verticalInset: CGFloat = 6
        let gap: CGFloat = 8
        let minX = bubbleSize.width / 2 + horizontalInset
        let maxX = max(minX, containerWidth - bubbleSize.width / 2 - horizontalInset)
        let x = min(max(anchorX, minX), maxX)
        let minY = bubbleSize.height / 2 + verticalInset
        let maxY = max(minY, timelineHeight - bubbleSize.height / 2 - verticalInset)
        let aboveY = blockY - gap - bubbleSize.height / 2
        let belowY = blockY + blockHeight + gap + bubbleSize.height / 2
        let preferredY = aboveY >= minY ? aboveY : belowY
        return CGPoint(x: x, y: min(max(preferredY, minY), maxY))
    }

    private func moveGesture(for segment: WeekTimedPlanSegment, dayWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !store.isPlanScheduleLocked(segment.plan) else { return }
                markScheduleInteractionActive()
                if selectedPlanID != segment.plan.id {
                    selectedPlanID = segment.plan.id
                }
                if movingSegmentIdentityDayByPlanID[segment.plan.id] == nil {
                    movingSegmentIdentityDayByPlanID[segment.plan.id] = segment.dayIndex
                }
                resizeBaseline = nil
                if let step = moveFeedbackStep(for: segment, translation: dragTranslation(value), dayWidth: dayWidth),
                   lastMoveFeedbackStep == step {
                    return
                }
                if let drafts = moveDrafts(for: segment, translation: dragTranslation(value), dayWidth: dayWidth) {
                    updateMovingDrafts(drafts)
                    notifyMoveStepIfNeeded(from: drafts, planID: segment.plan.id, fallbackDayIndex: segment.dayIndex)
                } else {
                    warnOnceDuringScheduleGesture()
                }
            }
            .onEnded { value in
                guard !store.isPlanScheduleLocked(segment.plan),
                      let drafts = moveDrafts(for: segment, translation: dragTranslation(value), dayWidth: dayWidth)
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
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let baseline = currentResizeBaseline(for: segment)
                guard selectedPlanID == segment.plan.id,
                      !store.isPlanScheduleLocked(segment.plan)
                else { return }
                markScheduleInteractionActive()
                if resizeBaseline == nil {
                    resizeBaseline = baseline
                    resizeDragStartGlobalY = value.startLocation.y
                    lastResizeFeedbackMinute = baseline.startMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .start
                guard let drafts = resizeDrafts(
                    for: segment.plan,
                    baseline: baseline,
                    edge: .start,
                    translationY: resizeDragTranslationY(value),
                    currentGlobalY: value.location.y
                ) else {
                    warnOnceDuringScheduleGesture()
                    return
                }
                updateMovingDrafts(drafts)
                notifyResizeStepIfNeeded(from: drafts, planID: segment.plan.id, edge: .start, baseline: baseline)
            }
            .onEnded { value in
                finishResize(segment: segment, edge: .start, translationY: resizeDragTranslationY(value), currentGlobalY: value.location.y)
            }
    }

    private func endHandleGesture(for segment: WeekTimedPlanSegment) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let baseline = currentResizeBaseline(for: segment)
                guard selectedPlanID == segment.plan.id,
                      !store.isPlanScheduleLocked(segment.plan)
                else { return }
                markScheduleInteractionActive()
                if resizeBaseline == nil {
                    resizeBaseline = baseline
                    resizeDragStartGlobalY = value.startLocation.y
                    lastResizeFeedbackMinute = baseline.endMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .end
                guard let drafts = resizeDrafts(
                    for: segment.plan,
                    baseline: baseline,
                    edge: .end,
                    translationY: resizeDragTranslationY(value),
                    currentGlobalY: value.location.y
                ) else {
                    warnOnceDuringScheduleGesture()
                    return
                }
                updateMovingDrafts(drafts)
                notifyResizeStepIfNeeded(from: drafts, planID: segment.plan.id, edge: .end, baseline: baseline)
            }
            .onEnded { value in
                finishResize(segment: segment, edge: .end, translationY: resizeDragTranslationY(value), currentGlobalY: value.location.y)
            }
    }

    private func finishResize(segment: WeekTimedPlanSegment, edge: WeekResizeEdge, translationY: CGFloat, currentGlobalY: CGFloat? = nil) {
        let baseline = currentResizeBaseline(for: segment)
        guard let drafts = resizeDrafts(
            for: segment.plan,
            baseline: baseline,
            edge: edge,
            translationY: translationY,
            currentGlobalY: currentGlobalY
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
        guard lastResizeFeedbackMinute != minute else { return }
        lastResizeFeedbackMinute = minute
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
        guard lastMoveFeedbackStep != step else { return }
        lastMoveFeedbackStep = step
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
            let centeredX = dayX(baseline.dayIndex, dayWidth: dayWidth) + dayWidth / 2 - handleWidth / 2
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
           lastMoveFeedbackStep != nil,
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

    private var renderCacheKey: WeekTimelineRenderCacheKey {
        WeekTimelineRenderCacheKey(
            weekStart: weekStart,
            visibleCategoryIDs: visibleCategoryIDs?.sorted { $0.uuidString < $1.uuidString },
            plans: plans.map {
                WeekTimelinePlanSignature(
                    id: $0.id,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    createdAt: $0.createdAt,
                    isAllDay: $0.isAllDay,
                    categoryID: $0.category?.id
                )
            },
            drafts: movingDrafts.values
                .map { WeekTimelineDraftSignature(planID: $0.planID, startTime: $0.startTime, endTime: $0.endTime) }
                .sorted { $0.planID.uuidString < $1.planID.uuidString }
        )
    }

    private var currentRenderCache: WeekTimelineRenderCache {
        if let renderCache {
            return renderCache
        }
        return makeRenderCache(for: renderCacheKey)
    }

    private func refreshRenderCache() {
        let cache = makeRenderCache(for: renderCacheKey)
        renderCache = cache
        resetSelectionIfHidden(visiblePlanIDs: cache.snapshot.visibleTimedPlanIDs)
    }

    private func makeRenderCache(for key: WeekTimelineRenderCacheKey) -> WeekTimelineRenderCache {
        let days = days
        let sortedPlans = plans.sorted {
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
        let timedSegments = timedSegments(from: displayPlans, days: days)
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
            snapshot: snapshot
        )
    }

    private var sortedPlans: [PlanBlock] {
        currentRenderCache.sortedPlans
    }

    private func timedSegments(from displayPlans: [PlanBlock], days: [Date]) -> [WeekTimedPlanSegment] {
        displayPlans
            .filter { !$0.isAllDay }
            .flatMap { plan in
                let effectiveStart = movingDrafts[plan.id]?.startTime ?? plan.startTime
                let effectiveEnd = movingDrafts[plan.id]?.endTime ?? plan.endTime
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
                    let endMinute = max(startMinute + 15, minute(from: clippedEnd, dayStart: dayStart))
                    return WeekTimedPlanSegment(
                        plan: plan,
                        dayIndex: dayIndex,
                        identityDayIndex: movingSegmentIdentityDayByPlanID[plan.id] ?? dayIndex,
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
        timelineTopInset + hourHeight * 24
    }

    private var shouldDisableTimelineScroll: Bool {
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
        timelineTopInset + CGFloat(minute) / 60 * hourHeight
    }

    private func height(startMinute: Int, endMinute: Int) -> CGFloat {
        max(14, CGFloat(max(15, endMinute - startMinute)) / 60 * hourHeight - 1)
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
        let timelineY = max(0, min(hourHeight * 24, y - timelineTopInset))
        let raw = Int((timelineY / hourHeight * 60).rounded())
        return min(24 * 60, max(0, (raw / 15) * 15))
    }

    private func snappedMinuteDelta(_ y: CGFloat) -> Int {
        let raw = Int((y / hourHeight * 60).rounded())
        return Int((Double(raw) / 15.0).rounded()) * 15
    }

    private func dragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        value.location.y - value.startLocation.y
    }

    private func resizeDragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        let startY = resizeDragStartGlobalY ?? value.startLocation.y
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

    private func moveDrafts(for segment: WeekTimedPlanSegment, translation: CGSize, dayWidth: CGFloat) -> [UUID: WeekPlanMoveDraft]? {
        let originalDayIndex = segment.dayIndex
        let duration = max(15 * 60.0, segment.plan.endTime.timeIntervalSince(segment.plan.startTime))
        let dayDelta = Int((translation.width / max(1, dayWidth + daySpacing)).rounded())
        let targetDayIndex = max(0, min(days.count - 1, originalDayIndex + dayDelta))
        let originalMinute = segment.startMinute
        let durationMinutes = max(15, Int((duration / 60).rounded()))
        let proposedMinute = originalMinute + snappedMinuteDelta(translation.height)
        let clampedMinute = max(0, min(24 * 60 - durationMinutes, proposedMinute))
        let direction: PlanTimelinePushDirection = proposedMinute >= originalMinute ? .later : .earlier
        return resolvedDrafts(
            for: segment.plan,
            dayIndex: targetDayIndex,
            proposedStartMinute: clampedMinute,
            proposedEndMinute: clampedMinute + durationMinutes,
            direction: direction
        )
    }

    private func moveFeedbackStep(for segment: WeekTimedPlanSegment, translation: CGSize, dayWidth: CGFloat) -> WeekMoveFeedbackStep? {
        guard days.indices.contains(segment.dayIndex) else { return nil }
        let duration = max(15 * 60.0, segment.plan.endTime.timeIntervalSince(segment.plan.startTime))
        let dayDelta = Int((translation.width / max(1, dayWidth + daySpacing)).rounded())
        let targetDayIndex = max(0, min(days.count - 1, segment.dayIndex + dayDelta))
        let durationMinutes = max(15, Int((duration / 60).rounded()))
        let proposedMinute = segment.startMinute + snappedMinuteDelta(translation.height)
        let clampedMinute = max(0, min(24 * 60 - durationMinutes, proposedMinute))
        return WeekMoveFeedbackStep(dayIndex: targetDayIndex, minute: clampedMinute)
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
            height: CGFloat(minuteDelta) / 60 * hourHeight
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
        let translationY = CGFloat(minuteDelta) / 60 * hourHeight
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
        translationY: CGFloat,
        currentGlobalY: CGFloat? = nil
    ) -> [UUID: WeekPlanMoveDraft]? {
        guard days.indices.contains(baseline.dayIndex) else { return nil }
        let delta = snappedMinuteDelta(translationY)
        let resize = resizedBounds(
            from: baseline,
            edge: edge,
            delta: delta,
            currentGlobalY: currentGlobalY
        )
        switch edge {
        case .start:
            return resolvedDrafts(
                for: plan,
                dayIndex: baseline.dayIndex,
                proposedStartMinute: resize.start,
                proposedEndMinute: resize.end,
                direction: resize.direction
            )
        case .end:
            return resolvedDrafts(
                for: plan,
                dayIndex: baseline.dayIndex,
                proposedStartMinute: resize.start,
                proposedEndMinute: resize.end,
                direction: resize.direction
            )
        }
    }

    private func resizedBounds(
        from baseline: WeekResizeBaseline,
        edge: WeekResizeEdge,
        delta: Int,
        currentGlobalY: CGFloat?
    ) -> (start: Int, end: Int, direction: PlanTimelinePushDirection) {
        if let currentGlobalY,
           let locked = resizeMinimumLock,
           locked.planID == baseline.planID,
           locked.edge == edge {
            return resizedBoundsFromMinimumLock(locked, currentGlobalY: currentGlobalY)
        }

        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: baseline.startMinute,
            originalEndMinute: baseline.endMinute,
            edge: edge.timelineEdge,
            delta: delta,
            minimumDuration: minimumDurationMinutes
        )
        let reachedMinimum = result.endMinute - result.startMinute <= minimumDurationMinutes
        if let currentGlobalY, reachedMinimum, crossedMinimum(from: baseline, edge: edge, delta: delta) {
            resizeMinimumLock = WeekResizeMinimumLock(
                planID: baseline.planID,
                edge: edge,
                startMinute: result.startMinute,
                endMinute: result.endMinute,
                locationY: currentGlobalY
            )
        } else if !reachedMinimum {
            resizeMinimumLock = nil
        }
        return (result.startMinute, result.endMinute, result.pushDirection)
    }

    private func resizedBoundsFromMinimumLock(
        _ locked: WeekResizeMinimumLock,
        currentGlobalY: CGFloat
    ) -> (start: Int, end: Int, direction: PlanTimelinePushDirection) {
        let delta = snappedMinuteDelta(currentGlobalY - locked.locationY)
        switch locked.edge {
        case .start:
            if delta > 0 {
                let start = min(PlanTimelineRescheduler.dayEndMinute - minimumDurationMinutes, locked.startMinute + delta)
                let end = start + minimumDurationMinutes
                resizeMinimumLock = locked.updated(startMinute: start, endMinute: end, locationY: currentGlobalY)
                return (start, end, .later)
            }
            let start = max(PlanTimelineRescheduler.dayStartMinute, min(locked.endMinute - minimumDurationMinutes, locked.startMinute + delta))
            return (start, locked.endMinute, .earlier)

        case .end:
            if delta < 0 {
                let end = max(PlanTimelineRescheduler.dayStartMinute + minimumDurationMinutes, locked.endMinute + delta)
                let start = end - minimumDurationMinutes
                resizeMinimumLock = locked.updated(startMinute: start, endMinute: end, locationY: currentGlobalY)
                return (start, end, .earlier)
            }
            let end = min(PlanTimelineRescheduler.dayEndMinute, max(locked.startMinute + minimumDurationMinutes, locked.endMinute + delta))
            return (locked.startMinute, end, .later)
        }
    }

    private func crossedMinimum(from baseline: WeekResizeBaseline, edge: WeekResizeEdge, delta: Int) -> Bool {
        switch edge {
        case .start:
            baseline.startMinute + delta > baseline.endMinute - minimumDurationMinutes
        case .end:
            baseline.endMinute + delta < baseline.startMinute + minimumDurationMinutes
        }
    }

    private func resolvedDrafts(
        for editingPlan: PlanBlock,
        dayIndex: Int,
        proposedStartMinute: Int,
        proposedEndMinute: Int,
        direction: PlanTimelinePushDirection
    ) -> [UUID: WeekPlanMoveDraft]? {
        guard days.indices.contains(dayIndex) else { return nil }
        let day = days[dayIndex]
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let intervals = sortedPlans
            .filter { !$0.isAllDay }
            .compactMap { plan -> PlanTimelineInterval? in
                let startTime = plan.id == editingPlan.id ? date(on: day, minute: proposedStartMinute) : plan.startTime
                let endTime = plan.id == editingPlan.id ? date(on: day, minute: proposedEndMinute) : plan.endTime
                guard startTime < dayEnd, endTime > dayStart else { return nil }
                let clippedStart = max(startTime, dayStart)
                let clippedEnd = min(endTime, dayEnd)
                guard clippedEnd > clippedStart else { return nil }
                return PlanTimelineInterval(
                    id: plan.id,
                    startMinute: minute(from: clippedStart, dayStart: dayStart),
                    endMinute: minute(from: clippedEnd, dayStart: dayStart),
                    isLocked: store.isPlanScheduleLocked(plan) || !isPlanVisible(plan)
                )
            }

        guard let resolved = PlanTimelineRescheduler.resolve(
            items: intervals,
            editingID: editingPlan.id,
            proposedStartMinute: proposedStartMinute,
            proposedEndMinute: proposedEndMinute,
            pushDirection: direction
        ) else {
            return nil
        }

        return Dictionary(
            uniqueKeysWithValues: resolved.map {
                (
                    $0.id,
                    WeekPlanMoveDraft(
                        planID: $0.id,
                        startTime: date(on: day, minute: $0.startMinute),
                        endTime: date(on: day, minute: $0.endMinute)
                    )
                )
            }
        )
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
        movingSegmentIdentityDayByPlanID = [:]
        resizeBaseline = nil
        resizeMinimumLock = nil
        activeResizeEdge = nil
        resizeDragStartGlobalY = nil
        didWarnDuringScheduleGesture = false
        lastMoveFeedbackStep = nil
        lastResizeFeedbackMinute = nil
        isScheduleInteractionActive = false
    }

    private func warnOnceDuringScheduleGesture() {
        guard !didWarnDuringScheduleGesture else { return }
        didWarnDuringScheduleGesture = true
        LiminalHaptics.warning()
    }

    private func markScheduleInteractionActive() {
        guard !isScheduleInteractionActive else { return }
        isScheduleInteractionActive = true
    }

    private func updateMovingDrafts(_ drafts: [UUID: WeekPlanMoveDraft]) {
        guard movingDrafts != drafts else { return }
        movingDrafts = drafts
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
        String(format: "%02d:00", hour)
    }

    private func hourTickCenterY(_ hour: Int) -> CGFloat {
        let rawY = timelineTopInset + CGFloat(hour) * hourHeight
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

    func height(hourHeight: CGFloat) -> CGFloat {
        max(14, CGFloat(max(15, endMinute - startMinute)) / 60 * hourHeight - 1)
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

private struct WeekResizeMinimumLock {
    let planID: UUID
    let edge: WeekResizeEdge
    let startMinute: Int
    let endMinute: Int
    let locationY: CGFloat

    func updated(startMinute: Int, endMinute: Int, locationY: CGFloat) -> WeekResizeMinimumLock {
        WeekResizeMinimumLock(
            planID: planID,
            edge: edge,
            startMinute: startMinute,
            endMinute: endMinute,
            locationY: locationY
        )
    }
}

private enum WeekResizeEdge {
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
    static let deleteLongPressDuration = 0.65
    static let deleteLongPressMaximumDistance: CGFloat = 8
}

#Preview("Week Timeline") {
    CalendarWeekTimelineView(
        anchorDate: Date(),
        categories: [],
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

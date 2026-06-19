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

private struct EditableTimelineScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct EditableTimelinePlanSignature: Hashable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let createdAt: Date
    let isAllDay: Bool
    let categoryID: UUID?
}

private struct EditableTimelineRenderCacheKey: Hashable {
    let dayStart: Date
    let dayEnd: Date
    let visibleCategoryIDs: [UUID]?
    let plans: [EditableTimelinePlanSignature]
}

private struct EditableTimelineRenderCache {
    let key: EditableTimelineRenderCacheKey
    let editablePlans: [PlanBlock]
    let editablePlansByID: [UUID: PlanBlock]
    let displayIntervals: [PlanTimelineInterval]
    let renderItems: [EditablePlanTimelineRenderItem]
    let collisionIntervals: [PlanTimelineInterval]
    let visiblePlanIDs: Set<UUID>
}

struct EditablePlanTimelineView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    let date: Date
    let plans: [PlanBlock]
    let categories: [Category]
    let visibleCategoryIDs: Set<UUID>?
    let isEditingEnabled: Bool
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let isInteractionEnabled: Bool
    let isPageSwipeActive: Bool
    @Binding var visibleHour: Int
    @Binding var selectedCategoryID: UUID?
    @Binding var isScheduleInteractionActive: Bool
    let onEditPlan: (PlanBlock) -> Void
    let onScheduleChanged: () -> Void

    @State private var selectedPlanID: UUID?
    @State private var draftIntervals: [PlanTimelineInterval]?
    @State private var gestureBaseline: [PlanTimelineInterval]?
    @State private var resizeInteractionAnchor: PlanTimelineInterval?
    @State private var activeResizeEdge: EditablePlanResizeEdge?
    @State private var creationDraft: PlanCreationDraft?
    @State private var creationGestureIsActive = false
    @State private var operationError: String?
    @State private var planPendingDeletion: PlanBlock?
    @State private var didWarnDuringScheduleGesture = false
    @State private var lastMoveFeedbackMinute: Int?
    @State private var lastResizeFeedbackMinute: Int?
    @State private var resizeDragStartGlobalY: CGFloat?
    @State private var renderCache: EditableTimelineRenderCache?
    private let calendar = Calendar.japanese
    private let hourColumnWidth: CGFloat = 50
    private let hourLabelHeight: CGFloat = 14
    private let timelineTopInset: CGFloat = 30
    private let sideInset: CGFloat = 4
    private let bottomScrollPadding: CGFloat = 24
    private let snapMinutes = 15
    private let minimumDurationMinutes = 15
    private let hourHeight: CGFloat = 38
    private let creationLongPressDuration = 0.28
    private let creationLongPressMaximumDistance: CGFloat = 28
    private let creationHorizontalCancelDistance: CGFloat = 22
    private let creationVerticalIntentRatio: CGFloat = 0.8

    private var dayStart: Date {
        DayBoundary.dayStart(for: date, calendar: calendar)
    }

    private var renderCacheKey: EditableTimelineRenderCacheKey {
        EditableTimelineRenderCacheKey(
            dayStart: dayStart,
            dayEnd: dayEnd,
            visibleCategoryIDs: visibleCategoryIDs?.sorted { $0.uuidString < $1.uuidString },
            plans: plans.map {
                EditableTimelinePlanSignature(
                    id: $0.id,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    createdAt: $0.createdAt,
                    isAllDay: $0.isAllDay,
                    categoryID: $0.category?.id
                )
            }
        )
    }

    private var currentRenderCache: EditableTimelineRenderCache {
        if let renderCache {
            return renderCache
        }
        return makeRenderCache(for: renderCacheKey)
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
                isLocked: store.isPlanScheduleLocked($0) || !isPlanVisible($0)
            )
        }
        return EditableTimelineRenderCache(
            key: key,
            editablePlans: editablePlans,
            editablePlansByID: editablePlansByID,
            displayIntervals: displayIntervals,
            renderItems: renderItems,
            collisionIntervals: collisionIntervals,
            visiblePlanIDs: Set(editablePlans.map(\.id))
        )
    }

    private func refreshRenderCache() {
        let cache = makeRenderCache(for: renderCacheKey)
        renderCache = cache
        resetSelectionIfHidden(visiblePlanIDs: cache.visiblePlanIDs)
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
        let slots = PlanTimelineLayoutSlot.makeSlots(for: intervals)
        return intervals.compactMap { interval in
            guard let plan = cache.editablePlansByID[interval.id],
                  let slot = slots[interval.id]
            else { return nil }
            return EditablePlanTimelineRenderItem(plan: plan, interval: interval, slot: slot)
        }
    }

    var body: some View {
        timeline
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
        .onChange(of: renderCacheKey) { _, _ in
            refreshRenderCache()
        }
        .alert("予定を調整できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var timeline: some View {
        GeometryReader { proxy in
            let cache = currentRenderCache
            let renderItemsSnapshot = renderItems(using: cache)
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        scrollOffsetReader

                        ZStack(alignment: .topLeading) {
                            timelineCanvasLayer(width: proxy.size.width, renderItems: renderItemsSnapshot)
                            hourScrollTargets

                            if isInteractionEnabled, let creationDraft {
                                creationDraftView(draft: creationDraft, width: proxy.size.width)
                                creationTimeGuide(draft: creationDraft, width: proxy.size.width)
                            }

                            ForEach(renderItemsSnapshot) { item in
                                planBlock(
                                    plan: item.plan,
                                    interval: item.interval,
                                    slot: item.slot,
                                    width: proxy.size.width
                                )
                            }

                            if isInteractionEnabled {
                                moveTimeGuide(width: proxy.size.width)

                                resizeTimeGuide(width: proxy.size.width)

                                resizeInteractionLayer(width: proxy.size.width, renderItems: renderItemsSnapshot)

                                if currentMinuteForDisplayedDay != nil {
                                    currentTimeLine(width: proxy.size.width)
                                }

                                deleteConfirmationBubble(width: proxy.size.width, renderItems: renderItemsSnapshot)
                            }
                        }
                        .frame(height: timelineHeight)
                        .contentShape(Rectangle())

                        Color.clear
                            .frame(height: bottomScrollPadding)
                    }
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scrollDisabled(shouldDisableTimelineScroll || isPageSwipeActive)
                .scrollIndicators(.visible)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(timelineBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(timelineOuterStroke, lineWidth: 1)
                )
                .onAppear {
                    scrollToVisibleHour(with: scrollProxy)
                }
                .onChange(of: visibleHour) { _, _ in
                    guard !isInteractionEnabled else { return }
                    scrollToVisibleHour(with: scrollProxy)
                }
                .onPreferenceChange(EditableTimelineScrollOffsetPreferenceKey.self) { minY in
                    updateVisibleHour(fromScrollMinY: minY)
                }
                .onChange(of: date) { _, _ in
                    resetInteractionState()
                    scrollToVisibleHour(with: scrollProxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollCoordinateSpaceName: String {
        "EditablePlanTimelineScroll-\(dayStart.timeIntervalSinceReferenceDate)"
    }

    private var scrollOffsetReader: some View {
        Color.clear
            .frame(height: 0)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: EditableTimelineScrollOffsetPreferenceKey.self,
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

    private func timelineCanvas(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(timelineBackground)
                .frame(width: width, height: timelineHeight)

            Rectangle()
                .fill(timelineHourColumnBackground)
                .frame(width: hourColumnWidth, height: timelineHeight)

            Rectangle()
                .fill(timelinePrimaryLine)
                .frame(width: 1, height: timelineHeight)
                .offset(x: hourColumnWidth)

            ForEach(0...24, id: \.self) { hour in
                let tickY = hourTickCenterY(hour)
                Rectangle()
                    .fill(timelinePrimaryLine)
                    .frame(width: max(0, width - hourColumnWidth), height: 1)
                    .position(
                        x: hourColumnWidth + max(0, width - hourColumnWidth) / 2,
                        y: tickY
                    )

                if hour < 24 {
                    Rectangle()
                        .fill(timelineSecondaryLine)
                        .frame(width: max(0, width - hourColumnWidth), height: 1)
                        .position(
                            x: hourColumnWidth + max(0, width - hourColumnWidth) / 2,
                            y: yOffset(for: hour * 60 + 30)
                        )
                }

                if hour < 24 {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(timelineTimeText)
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
    private func planBlock(plan: PlanBlock, interval: PlanTimelineInterval, slot: PlanTimelineLayoutSlot, width: CGFloat) -> some View {
        let isSelected = selectedPlanID == plan.id
        let color = plan.category?.displayColor ?? LiminalTheme.accent
        let block = EditablePlanBlock(
            plan: plan,
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
            onDelete: {
                requestDeletePlan(plan)
            },
            moveGesture: moveGesture(for: plan)
        )
        .withBlockHeight(height(for: interval))
        .frame(
            width: blockWidth(for: width, slot: slot),
            height: height(for: interval) + EditablePlanBlockMetrics.verticalOverflow * 2,
            alignment: .topLeading
        )
        .offset(
            x: blockXOffset(for: width, slot: slot),
            y: yOffset(for: interval.startMinute) - EditablePlanBlockMetrics.verticalOverflow
        )
        .zIndex(isSelected ? 10 : 1)

        if isSelected && !store.isPlanScheduleLocked(plan) {
            block
                .accessibilityAction(named: Text("15分早める")) {
                    applyAccessibilityMove(plan: plan, minuteDelta: -snapMinutes)
                }
                .accessibilityAction(named: Text("15分遅らせる")) {
                    applyAccessibilityMove(plan: plan, minuteDelta: snapMinutes)
                }
                .accessibilityAction(named: Text("開始を15分早める")) {
                    applyAccessibilityResize(plan: plan, edge: .start, minuteDelta: -snapMinutes)
                }
                .accessibilityAction(named: Text("開始を15分遅らせる")) {
                    applyAccessibilityResize(plan: plan, edge: .start, minuteDelta: snapMinutes)
                }
                .accessibilityAction(named: Text("終了を15分早める")) {
                    applyAccessibilityResize(plan: plan, edge: .end, minuteDelta: -snapMinutes)
                }
                .accessibilityAction(named: Text("終了を15分遅らせる")) {
                    applyAccessibilityResize(plan: plan, edge: .end, minuteDelta: snapMinutes)
                }
        } else {
            block
        }
    }

    private func handlePlanTap(_ plan: PlanBlock) {
        guard planPendingDeletion?.id != plan.id else { return }
        if selectedPlanID == plan.id {
            onEditPlan(plan)
        } else {
            LiminalHaptics.selection()
            selectedPlanID = plan.id
        }
    }

    private func creationDraftView(draft: PlanCreationDraft, width: CGFloat) -> some View {
        let color = selectedCategory?.displayColor ?? LiminalTheme.accent
        return VStack(alignment: .leading, spacing: 3) {
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
        .frame(width: availableBlockWidth(width), height: height(for: draft.interval), alignment: .topLeading)
        .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .offset(x: hourColumnWidth + sideInset, y: yOffset(for: draft.startMinute))
        .allowsHitTesting(false)
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
        defer {
            creationDraft = nil
            resetScheduleGestureState()
        }
        guard completed,
              isCreationDragDirection(startLocation: startLocation, location: location),
              updateCreationDraft(startLocation: startLocation, location: location, width: width, renderItems: renderItems)
        else { return }
        commitCreationDraft()
    }

    @discardableResult
    private func updateCreationDraft(
        startLocation: CGPoint,
        location: CGPoint,
        width: CGFloat,
        renderItems: [EditablePlanTimelineRenderItem]
    ) -> Bool {
        guard isEditingEnabled else {
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
        guard let range = clampedCreationRange(
            anchorMinute: start,
            currentMinute: current,
            intervals: collisionIntervals
        ) else {
            creationDraft = nil
            return false
        }
        creationDraft = PlanCreationDraft(startMinute: range.start, endMinute: range.end)
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
        guard !intervals.contains(where: { $0.startMinute < anchorMinute && anchorMinute < $0.endMinute }) else {
            return nil
        }

        if currentMinute >= anchorMinute {
            let desiredEnd = min(
                PlanTimelineRescheduler.dayEndMinute,
                max(currentMinute, anchorMinute + minimumDurationMinutes)
            )
            let nextBlockedStart = intervals
                .filter { $0.startMinute >= anchorMinute }
                .map(\.startMinute)
                .min() ?? PlanTimelineRescheduler.dayEndMinute
            let end = min(desiredEnd, nextBlockedStart)
            guard end - anchorMinute >= minimumDurationMinutes else { return nil }
            return (anchorMinute, end)
        } else {
            let desiredStart = max(0, min(currentMinute, anchorMinute - minimumDurationMinutes))
            let previousBlockedEnd = intervals
                .filter { $0.endMinute <= anchorMinute }
                .map(\.endMinute)
                .max() ?? 0
            let start = max(desiredStart, previousBlockedEnd)
            guard anchorMinute - start >= minimumDurationMinutes else { return nil }
            return (start, anchorMinute)
        }
    }

    private func commitCreationDraft() {
        guard let creationDraft else { return }
        defer {
            self.creationDraft = nil
        }
        guard isEditingEnabled, selectedCategory != nil else { return }
        let start = date(forMinute: creationDraft.startMinute)
        let end = date(forMinute: creationDraft.endMinute)
        guard !store.hasTimedPlanOverlap(startTime: start, endTime: end) else {
            operationError = "既存の予定と重なっています。空いている時間をなぞってください。"
            LiminalHaptics.warning()
            return
        }
        guard let plan = store.createPlanBlock(
            category: selectedCategory,
            title: selectedCategory?.name ?? "予定",
            startTime: start,
            endTime: end,
            isAllDay: false
        ) else {
            operationError = "予定を作成できませんでした。今日以前の日付や重なった時間は直接追加できません。"
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
              gestureBaseline == nil,
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
        let handleWidth = min(
            availableBlockWidth(width),
            max(blockWidth + EditablePlanBlockMetrics.resizeHandleHorizontalSlop * 2, EditablePlanBlockMetrics.minimumResizeHandleWidth)
        )
        let centeredX = blockX + blockWidth / 2 - handleWidth / 2
        let handleX = min(max(centeredX, timelineMinX), max(timelineMinX, timelineMaxX - handleWidth))
        let topY = yOffset(for: interval.startMinute) - EditablePlanBlockMetrics.resizeHitHandleHeight
        let bottomY = yOffset(for: interval.startMinute) + height(for: interval)
        return isPoint(
            point,
            insideX: handleX,
            y: topY,
            width: handleWidth,
            height: EditablePlanBlockMetrics.resizeHitHandleHeight
        ) || isPoint(
            point,
            insideX: handleX,
            y: bottomY,
            width: handleWidth,
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
        guard selectedPlanID != nil,
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

    @ViewBuilder
    private func deleteConfirmationBubble(width: CGFloat, renderItems: [EditablePlanTimelineRenderItem]) -> some View {
        if let plan = planPendingDeletion,
           let item = renderItems.first(where: { $0.plan.id == plan.id }) {
            let blockWidth = blockWidth(for: width, slot: item.slot)
            let blockHeight = height(for: item.interval)
            let blockX = blockXOffset(for: width, slot: item.slot)
            let blockY = yOffset(for: item.interval.startMinute)
            let bubbleSize = deleteConfirmationBubbleSize(containerWidth: width)
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
                    anchorX: blockX + blockWidth / 2,
                    blockY: blockY,
                    blockHeight: blockHeight,
                    containerWidth: width,
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

    private func moveGesture(for plan: PlanBlock) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !store.isPlanScheduleLocked(plan) else { return }
                markScheduleInteractionActive()
                if selectedPlanID != plan.id {
                    selectedPlanID = plan.id
                }
                let baseline = gestureBaseline ?? collisionIntervals
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                }
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if lastMoveFeedbackMinute == nil {
                    lastMoveFeedbackMinute = original.startMinute
                    LiminalHaptics.selection()
                }
                let delta = snappedMinuteDelta(dragTranslationY(value))
                let proposedStart = original.startMinute + delta
                let proposedEnd = original.endMinute + delta
                guard lastMoveFeedbackMinute != proposedStart else { return }
                let direction: PlanTimelinePushDirection = delta >= 0 ? .later : .earlier
                if updateDraft(from: baseline, editingID: plan.id, start: proposedStart, end: proposedEnd, direction: direction) {
                    notifyMoveStepIfNeeded(proposedStart)
                }
            }
            .onEnded { _ in
                finishScheduleGesture()
            }
    }

    private func startHandleGesture(for plan: PlanBlock) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard selectedPlanID == plan.id, !store.isPlanScheduleLocked(plan) else { return }
                markScheduleInteractionActive()
                let baseline = gestureBaseline ?? collisionIntervals
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                    resizeInteractionAnchor = original
                    resizeDragStartGlobalY = value.startLocation.y
                    lastResizeFeedbackMinute = original.startMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .start
                let delta = snappedMinuteDelta(resizeDragTranslationY(value))
                let resize = resizedInterval(from: original, edge: .start, delta: delta)
                guard lastResizeFeedbackMinute != resize.feedbackMinute else { return }
                if updateDraft(from: baseline, editingID: plan.id, start: resize.start, end: resize.end, direction: resize.direction) {
                    notifyResizeStepIfNeeded(resize.feedbackMinute)
                }
            }
            .onEnded { _ in
                finishScheduleGesture()
            }
    }

    private func endHandleGesture(for plan: PlanBlock) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard selectedPlanID == plan.id, !store.isPlanScheduleLocked(plan) else { return }
                markScheduleInteractionActive()
                let baseline = gestureBaseline ?? collisionIntervals
                guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
                if gestureBaseline == nil {
                    gestureBaseline = baseline
                    resizeInteractionAnchor = original
                    resizeDragStartGlobalY = value.startLocation.y
                    lastResizeFeedbackMinute = original.endMinute
                    LiminalHaptics.selection()
                }
                activeResizeEdge = .end
                let delta = snappedMinuteDelta(resizeDragTranslationY(value))
                let resize = resizedInterval(from: original, edge: .end, delta: delta)
                guard lastResizeFeedbackMinute != resize.feedbackMinute else { return }
                if updateDraft(from: baseline, editingID: plan.id, start: resize.start, end: resize.end, direction: resize.direction) {
                    notifyResizeStepIfNeeded(resize.feedbackMinute)
                }
            }
            .onEnded { _ in
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
            let handleWidth = activeResizeEdge == nil
                ? min(
                    availableBlockWidth(width),
                    max(blockWidth + EditablePlanBlockMetrics.resizeHandleHorizontalSlop * 2, EditablePlanBlockMetrics.minimumResizeHandleWidth)
                )
                : timelineMaxX - timelineMinX
            let centeredX = blockX + blockWidth / 2 - handleWidth / 2
            let handleX = min(max(centeredX, timelineMinX), max(timelineMinX, timelineMaxX - handleWidth))
            let topY = yOffset(for: anchor.startMinute) - EditablePlanBlockMetrics.resizeHitHandleHeight
            let bottomY = yOffset(for: anchor.startMinute) + height(for: anchor)

            ZStack(alignment: .topLeading) {
                resizeHitHandle()
                    .frame(width: handleWidth)
                    .offset(x: handleX, y: topY)
                    .highPriorityGesture(startHandleGesture(for: plan), including: .all)

                resizeHitHandle()
                    .frame(width: handleWidth)
                    .offset(x: handleX, y: bottomY)
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
           lastMoveFeedbackMinute != nil,
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

                Text(timeText(minute))
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

    @discardableResult
    private func updateDraft(
        from baseline: [PlanTimelineInterval],
        editingID: UUID,
        start: Int,
        end: Int,
        direction: PlanTimelinePushDirection
    ) -> Bool {
        guard let resolved = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: editingID,
            proposedStartMinute: start,
            proposedEndMinute: end,
            pushDirection: direction
        ) else {
            warnOnceDuringScheduleGesture()
            return false
        }
        if draftIntervals != resolved {
            draftIntervals = resolved
        }
        return true
    }

    private func markScheduleInteractionActive() {
        guard !isScheduleInteractionActive else { return }
        isScheduleInteractionActive = true
    }

    private func notifyResizeStepIfNeeded(_ minute: Int) {
        guard lastResizeFeedbackMinute != minute else { return }
        lastResizeFeedbackMinute = minute
        LiminalHaptics.selection()
    }

    private func notifyMoveStepIfNeeded(_ minute: Int) {
        guard lastMoveFeedbackMinute != minute else { return }
        lastMoveFeedbackMinute = minute
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
        saveResolvedSchedule(
            from: baseline,
            editingID: plan.id,
            start: original.startMinute + minuteDelta,
            end: original.endMinute + minuteDelta,
            direction: minuteDelta >= 0 ? .later : .earlier,
            failureMessage: "予定を移動できませんでした。今日以前や収まりきらない玉突き移動は変更できません。"
        )
    }

    private func applyAccessibilityResize(plan: PlanBlock, edge: EditablePlanResizeEdge, minuteDelta: Int) {
        guard selectedPlanID == plan.id, !store.isPlanScheduleLocked(plan) else { return }
        let baseline = collisionIntervals
        guard let original = baseline.first(where: { $0.id == plan.id }) else { return }
        let resize = resizedInterval(from: original, edge: edge, delta: minuteDelta)
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
    }

    private func finishScheduleGesture() {
        defer {
            resetScheduleGestureState()
        }
        guard let draftIntervals else { return }
        let cache = currentRenderCache
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
        gestureBaseline = nil
        draftIntervals = nil
        resizeInteractionAnchor = nil
        activeResizeEdge = nil
        resizeDragStartGlobalY = nil
        didWarnDuringScheduleGesture = false
        lastMoveFeedbackMinute = nil
        lastResizeFeedbackMinute = nil
        isScheduleInteractionActive = false
    }

    private func warnOnceDuringScheduleGesture() {
        guard !didWarnDuringScheduleGesture else { return }
        didWarnDuringScheduleGesture = true
        LiminalHaptics.warning()
    }

    private func intervals(for plans: [PlanBlock]) -> [PlanTimelineInterval] {
        plans.map {
            PlanTimelineInterval(
                id: $0.id,
                startMinute: minute(for: max($0.startTime, dayStart)),
                endMinute: minute(for: min($0.endTime, dayEnd)),
                isLocked: store.isPlanScheduleLocked($0)
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
        displayedIntervals(using: currentRenderCache).first { $0.id == plan.id }
    }

    private var timelineHeight: CGFloat {
        timelineTopInset + hourHeight * 24
    }

    private var shouldDisableTimelineScroll: Bool {
        creationGestureIsActive ||
            creationDraft != nil ||
            gestureBaseline != nil ||
            resizeInteractionAnchor != nil ||
            activeResizeEdge != nil
    }

    private var timelineBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.125, green: 0.129, blue: 0.145)
            : Color(red: 0.985, green: 0.985, blue: 0.98)
    }

    private var timelineHourColumnBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.109, blue: 0.125)
            : Color(red: 0.955, green: 0.955, blue: 0.945)
    }

    private var timelineOuterStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.12)
    }

    private var timelinePrimaryLine: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.16)
    }

    private var timelineSecondaryLine: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.07)
    }

    private var timelineTimeText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.62)
            : Color.black.opacity(0.52)
    }

    private var currentMinuteForDisplayedDay: Int? {
        guard calendar.isDateInToday(date) else { return nil }
        return minute(for: Date())
    }

    private func blockWidth(for totalWidth: CGFloat, slot: PlanTimelineLayoutSlot) -> CGFloat {
        let gap = CGFloat(max(slot.columnCount - 1, 0)) * 2
        return max(42, (availableBlockWidth(totalWidth) - gap) / CGFloat(slot.columnCount))
    }

    private func blockXOffset(for totalWidth: CGFloat, slot: PlanTimelineLayoutSlot) -> CGFloat {
        let columnWidth = blockWidth(for: totalWidth, slot: slot)
        return hourColumnWidth + sideInset + CGFloat(slot.column) * (columnWidth + 2)
    }

    private func availableBlockWidth(_ totalWidth: CGFloat) -> CGFloat {
        max(42, totalWidth - hourColumnWidth - sideInset * 2)
    }

    private func yOffset(for minute: Int) -> CGFloat {
        timelineTopInset + CGFloat(minute) / 60 * hourHeight
    }

    private func height(for interval: PlanTimelineInterval) -> CGFloat {
        max(16, CGFloat(interval.duration) / 60 * hourHeight)
    }

    private func snappedMinute(fromY y: CGFloat) -> Int {
        let timelineY = max(0, min(hourHeight * 24, y - timelineTopInset))
        let raw = Int((timelineY / hourHeight * 60).rounded())
        return min(PlanTimelineRescheduler.dayEndMinute, max(0, (raw / snapMinutes) * snapMinutes))
    }

    private func snappedMinuteDelta(_ y: CGFloat) -> Int {
        let raw = Int((y / hourHeight * 60).rounded())
        return Int((Double(raw) / Double(snapMinutes)).rounded()) * snapMinutes
    }

    private func dragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        value.translation.height
    }

    private func resizeDragTranslationY(_ value: DragGesture.Value) -> CGFloat {
        let startY = resizeDragStartGlobalY ?? value.startLocation.y
        return value.location.y - startY
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

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

}

struct TimelineDeleteConfirmationBubble: View {
    static let preferredWidth: CGFloat = 220
    static let preferredHeight: CGFloat = 110

    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 2) {
                Text("予定を削除しますか？")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text("この予定は元に戻せません。")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("キャンセル")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.72))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

                Button(role: .destructive, action: onDelete) {
                    Text("削除")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        view.isMultipleTouchEnabled = false
        view.onTouchBegan = { [weak coordinator = context.coordinator] point in
            coordinator?.touchDownLocation = point
        }
        view.onTouchFinished = { [weak coordinator = context.coordinator] in
            coordinator?.touchDownLocation = nil
        }

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = minimumDuration
        longPressRecognizer.allowableMovement = maximumStationaryDistance
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.delaysTouchesBegan = false
        longPressRecognizer.delaysTouchesEnded = false
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
            true
        }
    }
}

private final class TimelineCreationTouchTrackingView: UIView {
    var onTouchBegan: ((CGPoint) -> Void)?
    var onTouchFinished: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self) {
            onTouchBegan?(point)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onTouchFinished?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onTouchFinished?()
    }
}

private struct PlanCreationDraft {
    let startMinute: Int
    let endMinute: Int

    var interval: PlanTimelineInterval {
        PlanTimelineInterval(id: UUID(), startMinute: startMinute, endMinute: endMinute)
    }
}

private struct PlanTimelineLayoutSlot {
    let column: Int
    let columnCount: Int

    static func makeSlots(for intervals: [PlanTimelineInterval]) -> [UUID: PlanTimelineLayoutSlot] {
        let sorted = intervals.sorted {
            if $0.startMinute == $1.startMinute {
                return $0.endMinute < $1.endMinute
            }
            return $0.startMinute < $1.startMinute
        }
        var slots: [UUID: PlanTimelineLayoutSlot] = [:]
        var cluster: [PlanTimelineInterval] = []
        var clusterEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            let assigned = assignColumns(in: cluster)
            let columnCount = max(assigned.values.max() ?? 0, 0) + 1
            for item in cluster {
                slots[item.id] = PlanTimelineLayoutSlot(
                    column: assigned[item.id] ?? 0,
                    columnCount: columnCount
                )
            }
            cluster.removeAll()
            clusterEnd = 0
        }

        for interval in sorted {
            if cluster.isEmpty {
                cluster = [interval]
                clusterEnd = interval.endMinute
                continue
            }
            if interval.startMinute < clusterEnd {
                cluster.append(interval)
                clusterEnd = max(clusterEnd, interval.endMinute)
            } else {
                flushCluster()
                cluster = [interval]
                clusterEnd = interval.endMinute
            }
        }
        flushCluster()
        return slots
    }

    private static func assignColumns(in intervals: [PlanTimelineInterval]) -> [UUID: Int] {
        var columnEndMinutes: [Int] = []
        var result: [UUID: Int] = [:]
        for interval in intervals {
            if let reusableIndex = columnEndMinutes.firstIndex(where: { $0 <= interval.startMinute }) {
                result[interval.id] = reusableIndex
                columnEndMinutes[reusableIndex] = interval.endMinute
            } else {
                result[interval.id] = columnEndMinutes.count
                columnEndMinutes.append(interval.endMinute)
            }
        }
        return result
    }
}

private enum EditablePlanBlockMetrics {
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
    static let resizeHandleHorizontalSlop: CGFloat = 22
    static let minimumResizeHandleWidth: CGFloat = 120
    static let deleteLongPressDuration = 0.65
    static let deleteLongPressMaximumDistance: CGFloat = 8
}

private enum EditablePlanResizeEdge {
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

private struct EditablePlanBlock<MoveGesture: Gesture>: View {
    let plan: PlanBlock
    let interval: PlanTimelineInterval
    let color: Color
    let isSelected: Bool
    let isLocked: Bool
    let planTitleFontSize: Double
    let planTitleBold: Bool
    let activeResizeEdge: EditablePlanResizeEdge?
    var blockHeight: CGFloat = 26
    let onSelect: () -> Void
    let onDelete: () -> Void
    let moveGesture: MoveGesture

    var body: some View {
        let overflow = EditablePlanBlockMetrics.verticalOverflow
        let title = displayTitle

        return ZStack(alignment: .topTrailing) {
            selectableBlockCard(height: blockHeight)
                .offset(y: overflow)

            if isSelected && !isLocked {
                resizeHandle(edge: .start)
                    .offset(y: -EditablePlanBlockMetrics.resizeHandleEdgeOutset)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityLabel("開始時刻を調整")

                resizeHandle(edge: .end)
                    .offset(y: blockHeight + overflow - EditablePlanBlockMetrics.resizeHandleEdgeOverlap)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityLabel("終了時刻を調整")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(timeText(interval.startMinute))から\(timeText(interval.endMinute))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect()
        }
        .accessibilityAction(named: Text("詳細を編集")) {
            onSelect()
        }
    }

    private func blockCard(height: CGFloat) -> some View {
        let title = displayTitle
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(timeText(interval.startMinute))
                    .font(.system(size: height < 24 ? 9.2 : 10.2, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .layoutPriority(3)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: height < 24 ? 7.2 : 8.2, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .layoutPriority(2)
                }

                if height < 34 {
                    Text(title)
                        .font(.system(size: compactTitleFontSize, weight: titleFontWeight))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .layoutPriority(1)
                }
            }

            if height >= 34 {
                Text(title)
                    .font(.system(size: regularTitleFontSize, weight: titleFontWeight))
                    .lineLimit(height < 52 ? 1 : 2)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, height < 24 ? 6 : 8)
        .padding(.vertical, height < 24 ? 3 : 5)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(isLocked ? 0.50 : 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(activeResizeEdge == nil ? 0.92 : 0.98) : color.opacity(0.42), lineWidth: isSelected ? (activeResizeEdge == nil ? 2 : 2.5) : 1)
        )
        .shadow(color: color.opacity(0.07), radius: 3, y: 3)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var displayTitle: String {
        plan.title.isEmpty ? (plan.category?.name ?? "予定") : plan.title
    }

    private func selectableBlockCard(height: CGFloat) -> some View {
        movableBlockCard(height: height)
            .onTapGesture {
                onSelect()
            }
    }

    @ViewBuilder
    private func movableBlockCard(height: CGFloat) -> some View {
        if isSelected && !isLocked && activeResizeEdge == nil {
            blockCard(height: height)
                .highPriorityGesture(moveGesture)
                .simultaneousGesture(deleteLongPressGesture)
        } else {
            blockCard(height: height)
        }
    }

    private var deleteLongPressGesture: some Gesture {
        LongPressGesture(
            minimumDuration: EditablePlanBlockMetrics.deleteLongPressDuration,
            maximumDistance: EditablePlanBlockMetrics.deleteLongPressMaximumDistance
        )
        .onEnded { completed in
            guard completed else { return }
            onDelete()
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
            .frame(
                width: EditablePlanBlockMetrics.resizeGripBackgroundWidth + (isActive ? 14 : 0),
                height: EditablePlanBlockMetrics.resizeGripBackgroundHeight + (isActive ? 3 : 0)
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(isActive ? 0.42 : 0.22), lineWidth: 1)
            }
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.96))
                    .frame(
                        width: EditablePlanBlockMetrics.resizeGripWidth + (isActive ? 12 : 0),
                        height: EditablePlanBlockMetrics.resizeGripHeight + (isActive ? 1 : 0)
                    )
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

    private var compactTitleFontSize: CGFloat {
        max(8.6, regularTitleFontSize - 1.2)
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

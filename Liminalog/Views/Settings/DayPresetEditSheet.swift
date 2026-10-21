import SwiftData
import SwiftUI

private struct DayPresetEditorItem: Identifiable, Equatable {
    let id: UUID
    var snapshot: PlanTemplateSnapshot

    init(id: UUID = UUID(), snapshot: PlanTemplateSnapshot) {
        self.id = snapshot.templateItemID ?? id
        self.snapshot = snapshot
        self.snapshot.templateItemID = self.id
    }
}

private struct DayPresetLibraryDrag {
    let preset: PlanPreset
    let snapshot: PlanTemplateSnapshot
    let location: CGPoint
}

/// A day preset is edited as a complete virtual day. It intentionally reuses
/// the same preset drawer as the real day/week timelines; only persistence is
/// different, because these blocks remain value snapshots until Save is tapped.
struct DayPresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanPresetStore.self) private var presetStore
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [
        SortDescriptor(\PlanPreset.sortOrder),
        SortDescriptor(\PlanPreset.createdAt)
    ]) private var planPresets: [PlanPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    private let preset: DayPreset?

    @State private var recurrenceRule: PlanRecurrenceRule?
    @State private var showingRecurrence = false
    @State private var name: String
    @State private var presetColor: Color
    @State private var presetIcon: String
    @State private var showingAppearance = false
    @State private var items: [DayPresetEditorItem]
    @State private var selectedItemID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var showingCategoryEditor = false
    @State private var deletionItem: DayPresetEditorItem?
    @State private var creationDraft: PlanTimelineCreationPolicy.MinuteRange?
    @State private var creationCategoryID: UUID?
    @State private var creationCancelledByZoom = false
    @State private var editingItem: DayPresetEditorItem?
    @State private var isLibraryPresented = false
    @State private var libraryDrag: DayPresetLibraryDrag?
    @State private var lastPresetFeedbackMinute: Int?
    @State private var timelineWindowFrame: CGRect?
    @State private var timelineViewportSize: CGSize = .zero
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var timelineScrollPosition = ScrollPosition()
    @State private var transientHourScale: CGFloat?
    @State private var zoomBaseScale: CGFloat?
    @State private var zoomAnchorMinute: CGFloat?
    @State private var moveBaseline: DayPresetEditorItem?
    @State private var moveDragSession: TimelineAxisDragSession?
    @State private var resizeBaseline: DayPresetEditorItem?
    @State private var resizeDragSession: TimelineAxisDragSession?
    @State private var activeResizeEdge: EditablePlanResizeEdge?
    @State private var operationError: String?
    @AppStorage(TimelineSnapPrecision.userDefaultsKey)
    private var storedSnapPrecisionMinutes = TimelineSnapPrecision.quarterHour.minutes
    @AppStorage(DayTimelineZoomPolicy.userDefaultsKey)
    private var storedHourScale = Double(DayTimelineZoomPolicy.defaultScale)
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = CalendarPlanTitleMetrics.defaultSize
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false

    private let coordinateSpaceName = "day-preset-editor"
    private let timelineTopInset: CGFloat = 30
    private let bottomScrollPadding: CGFloat = 24
    private let minimumBlockHeight = EditablePlanBlockMetrics.minimumReadableHeight
    private let blockSideInset: CGFloat = 4

    init(preset: DayPreset?) {
        self.preset = preset
        let decoded: [PlanTemplateSnapshot]
        if let preset {
            decoded = (try? DayPresetItemsCodec.decode(preset.itemsData)) ?? []
        } else {
            decoded = []
        }
        _recurrenceRule = State(initialValue: PlanRecurrenceRule.decode(preset?.recurrenceData))
        _name = State(initialValue: preset?.name ?? "")
        _presetColor = State(initialValue: Color(hex: preset?.colorHex ?? "#2F80ED"))
        _presetIcon = State(initialValue: preset?.icon ?? "calendar")
        _items = State(initialValue: decoded.map { DayPresetEditorItem(snapshot: $0) })
        #if DEBUG
        _isLibraryPresented = State(initialValue: ProcessInfo.processInfo.arguments.contains("-LiminalogDebugExpandDayPresetLibrary"))
        #endif
    }

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 0) {
                        categoryPalette
                        Button { showingRecurrence = true } label: {
                            Label(recurrenceRule?.summary ?? "繰り返しを設定", systemImage: "repeat")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .accessibilityIdentifier("day-preset-recurrence")
                        VStack(spacing: 0) {
                            nameField
                            if !allDayItems.isEmpty {
                                allDayStrip
                            }
                            timeline
                        }
                        .background(gridPalette.background)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(gridPalette.outerStroke, lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .padding(.horizontal, CalendarTimelineCardMetrics.horizontalPadding)
                        .padding(.top, CalendarTimelineCardMetrics.topPadding)
                        .padding(.bottom, CalendarTimelineCardMetrics.bottomPadding)
                    }

                    TimelinePlanPresetLibrary(
                        presets: planPresets,
                        categories: categories,
                        onFixedTimeTap: addFixedPreset,
                        onDurationDragChanged: updateDurationPresetPreview,
                        onDurationDrop: finishDurationPresetDrop,
                        onDraggingChanged: { active in
                            if !active {
                                libraryDrag = nil
                                lastPresetFeedbackMinute = nil
                            }
                        },
                        launcherPlacement: .externalControl,
                        isPresented: $isLibraryPresented
                    )
                    .zIndex(80)
                }
                .coordinateSpace(name: coordinateSpaceName)
                .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            }
            .navigationTitle(preset == nil ? "一日プリセットを作成" : "一日プリセットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("保存できませんでした", isPresented: operationErrorPresented) {
                Button("OK", role: .cancel) { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
            .sheet(item: $editingItem) { item in
                PlanCreateSheet(
                    snapshot: item.snapshot,
                    onSaveSnapshot: { saveDraftItem(item.id, snapshot: $0) },
                    onDeleteSnapshot: items.contains(where: { $0.id == item.id }) ? { remove(item.id) } : nil
                )
            }
            .sheet(isPresented: $showingCategoryEditor) {
                CategoryEditSheet(category: nil) { category in
                    selectedCategoryID = category.id
                }
            }
            .sheet(isPresented: $showingRecurrence) {
                NavigationStack {
                    Form { PlanRecurrenceControls(rule: $recurrenceRule) }
                        .navigationTitle("一日プリセットの繰り返し")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { showingRecurrence = false } } }
                }.presentationDetents([.fraction(0.75), .large])
            }
            .sheet(isPresented: $showingAppearance) {
                DayPresetAppearanceSheet(color: $presetColor, icon: $presetIcon)
            }
            .onAppear { normalizeSelectedCategory() }
            .onChange(of: categories.map(\.id)) { _, _ in normalizeSelectedCategory() }
            .alert("予定を外しますか？", isPresented: Binding(
                get: { deletionItem != nil },
                set: { if !$0 { deletionItem = nil } }
            ), presenting: deletionItem) { item in
                Button("外す", role: .destructive) { remove(item.id) }
                Button("キャンセル", role: .cancel) {}
            } message: { item in
                Text(item.snapshot.title.isEmpty ? category(for: item.snapshot.categoryID)?.name ?? "予定" : item.snapshot.title)
            }
        }
    }

    private var gridPalette: DayTimelineGridPalette {
        DayTimelineGridPalette(colorScheme: colorScheme, style: .calendarGrid)
    }

    private var categoryPalette: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    LiminalHaptics.openSheet()
                    isLibraryPresented = true
                } label: {
                    TimelineCategoryStatusChip(
                        title: "予定プリセット",
                        systemImage: "bookmark.fill",
                        accessibilityLabel: "予定プリセットを開く"
                    )
                }
                .buttonStyle(.plain)
                ForEach(categories) { category in
                    Button {
                        selectedCategoryID = category.id
                        LiminalHaptics.selection()
                    } label: {
                        TimelineCategoryChip(category: category, isSelected: selectedCategoryID == category.id)
                    }
                    .buttonStyle(.plain)
                }
                Button { showingCategoryEditor = true } label: {
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

    private func normalizeSelectedCategory() {
        if !categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = categories.first?.id
        }
    }

    // The preset name occupies the real day timeline's date-header position.
    private var nameField: some View {
        HStack(spacing: 1) {
            Button { showingAppearance = true } label: {
                Image(systemName: CategoryIconCatalog.displaySymbol(for: presetIcon))
                    .foregroundStyle(presetColor.liminalReadableDataColor())
                    .frame(width: TimelineHourAxisMetrics.columnWidth, height: 46)
                    .background(presetColor.opacity(0.12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("一日プリセットの色とアイコン")
            HStack(spacing: 8) {
                TextField("プリセット名", text: $name)
                    .font(.headline)
                Text("\(items.count)件")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(gridPalette.timeText)
                Button {
                    startNewItem(at: timelineScrollOffset + timelineViewportSize.height / 2)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("予定を追加")
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(gridPalette.background)
        }
        .foregroundStyle(LiminalTheme.text)
        .frame(height: 46)
        .background(gridPalette.primaryLine)
        .overlay(alignment: .bottom) {
            gridPalette.primaryLine.frame(height: 1).allowsHitTesting(false)
        }
    }

    private var timeline: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    timelineGrid(width: proxy.size.width)
                        .overlay(alignment: .topLeading) {
                            TimelineCreationLongPressOverlay(
                                minimumDuration: creationMinimumDuration,
                                maximumStationaryDistance: 28,
                                onChanged: { start, point in
                                    updateCreation(start: start, point: point)
                                },
                                onEnded: { start, point, completed in
                                    finishCreation(start: start, point: point, completed: completed)
                                },
                                onTap: { _ in selectedItemID = nil }
                            )
                        }

                    let slots = timelineSlots
                    ForEach(timedItems) { item in
                        timelineBlock(item, width: proxy.size.width, slot: slots[item.id] ?? PlanTimelineLayoutSlot(column: 0, columnCount: 1))
                    }

                    if let creationDraft {
                        creationPreview(creationDraft, width: proxy.size.width)
                    }

                }
                .frame(
                    width: proxy.size.width,
                    height: timelineTopInset + axisMap.contentHeight + bottomScrollPadding,
                    alignment: .topLeading
                )
            }
            .scrollPosition($timelineScrollPosition)
            .scrollIndicators(.visible)
            .scrollDisabled(moveBaseline != nil || resizeBaseline != nil || libraryDrag != nil || creationDraft != nil)
            .background(gridPalette.background)
            .background {
                TimelineWindowFrameReader { frame in
                    if timelineWindowFrame != frame {
                        timelineWindowFrame = frame
                    }
                }
            }
            .onAppear {
                timelineViewportSize = proxy.size
                normalizeStoredHourScale()
            }
            .onChange(of: proxy.size) { _, size in
                timelineViewportSize = size
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                timelineScrollOffset = max(0, newValue)
            }
            .simultaneousGesture(timelineZoomGesture)
            .overlay(alignment: .topLeading) {
                if let libraryDrag {
                    dragPreview(libraryDrag)
                }
            }
        }
    }

    private func timelineGrid(width: CGFloat) -> some View {
        DayTimelineGrid(
            axisMap: axisMap,
            topInset: timelineTopInset,
            contentHeight: timelineTopInset + axisMap.contentHeight + bottomScrollPadding,
            colorStyle: .calendarGrid
        )
        .frame(width: width, height: timelineTopInset + axisMap.contentHeight + bottomScrollPadding)
    }

    private func updateCreation(start: CGPoint, point: CGPoint) {
        let horizontal = abs(point.x - start.x)
        let vertical = abs(point.y - start.y)
        guard !creationCancelledByZoom, zoomBaseScale == nil, moveBaseline == nil, resizeBaseline == nil, libraryDrag == nil,
              start.x > TimelineHourAxisMetrics.columnWidth,
              start.y >= timelineTopInset,
              horizontal <= 22 || vertical >= horizontal * 0.8,
              selectedCategoryID != nil
        else { creationDraft = nil; return }
        let anchor = creationMinute(at: start.y)
        let current = creationMinute(at: point.y)
        let intervals = timedItems.filter { !$0.snapshot.isMemo }.flatMap { item -> [PlanTimelineInterval] in
            let snapshot = item.snapshot
            var parts = [PlanTimelineInterval(id: item.id, startMinute: snapshot.startMinute,
                                             endMinute: min(1440, snapshot.endMinute))]
            if snapshot.endMinute > 1440 {
                parts.append(PlanTimelineInterval(id: item.id, startMinute: 0,
                                                  endMinute: snapshot.endMinute - 1440))
            }
            return parts
        }
        let next = PlanTimelineCreationPolicy.range(
            anchorMinute: anchor,
            currentMinute: current,
            minimumDuration: snapPrecision.minutes,
            intervals: intervals
        )
        if creationDraft == nil { creationCategoryID = selectedCategoryID }
        if next != creationDraft, next != nil { LiminalHaptics.selection() }
        creationDraft = next
        if next != nil { selectedItemID = nil }
    }

    private var creationMinimumDuration: TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LiminalogDebugImmediateTimelineCreation") { return 0 }
        #endif
        return 0.28
    }

    private func creationMinute(at y: CGFloat) -> Int {
        // Match the real day's empty-space creation anchor (15-minute grid).
        let raw = Int(axisMap.minute(atY: y - timelineTopInset).rounded())
        return min(1440, max(0, raw / 15 * 15))
    }

    private func finishCreation(start: CGPoint, point: CGPoint, completed: Bool) {
        defer { creationDraft = nil; creationCategoryID = nil; creationCancelledByZoom = false }
        guard completed, !creationCancelledByZoom else { return }
        updateCreation(start: start, point: point)
        guard let range = creationDraft else { return }
        let selected = category(for: creationCategoryID)
        let snapshot = PlanTemplateSnapshot(
            title: selected?.name ?? "予定", categoryID: selected?.id,
            startMinute: range.start, endMinute: range.end,
            isAllDay: false, isImportant: false, note: nil, isPublic: false
        )
        if let error = saveDraftItem(UUID(), snapshot: snapshot) {
            operationError = error
            LiminalHaptics.warning()
        }
    }

    private func creationPreview(_ range: PlanTimelineCreationPolicy.MinuteRange, width: CGFloat) -> some View {
        let selected = category(for: creationCategoryID)
        let tint = selected?.displayColor ?? LiminalTheme.accent
        let height = max(minimumBlockHeight, axisMap.height(startMinute: range.start, endMinute: range.end))
        return VStack(alignment: .leading, spacing: 3) {
            Text(minuteText(range.start))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .lineLimit(1)
            Text(selected?.name ?? "予定")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: max(1, width - TimelineHourAxisMetrics.columnWidth - blockSideInset * 2),
               height: height, alignment: .topLeading)
        .background(tint.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .offset(x: TimelineHourAxisMetrics.columnWidth + blockSideInset,
                y: timelineTopInset + axisMap.y(forMinute: range.start))
        .allowsHitTesting(false)
    }

    private var timelineSlots: [UUID: PlanTimelineLayoutSlot] {
        PlanTimelineLayoutSlot.makeSlots(for: timedItems.map {
            PlanTimelineInterval(id: $0.id, startMinute: $0.snapshot.startMinute,
                endMinute: $0.snapshot.endMinute, isMemo: $0.snapshot.isMemo)
        })
    }

    private func timelineBlock(_ item: DayPresetEditorItem, width: CGFloat, slot: PlanTimelineLayoutSlot) -> some View {
        let snapshot = item.snapshot
        let category = category(for: snapshot.categoryID)
        let start = min(1440, max(0, snapshot.startMinute))
        let end = min(1440, max(start + 1, snapshot.endMinute))
        let y = timelineTopInset + axisMap.y(forMinute: start)
        let height = max(minimumBlockHeight, axisMap.height(startMinute: start, endMinute: end))
        let available = max(1, width - TimelineHourAxisMetrics.columnWidth - blockSideInset * 2)

        let blockWidth = snapshot.isMemo ? max(1, (available * 0.48 - CGFloat(slot.columnCount - 1) * 2) / CGFloat(slot.columnCount)) : available
        let isSelected = selectedItemID == item.id
        let overflow = EditablePlanBlockMetrics.verticalOverflow

        return ZStack(alignment: .topLeading) {
            EditablePlanBlock(
                title: snapshot.title.isEmpty ? category?.name ?? "予定" : snapshot.title,
                interval: PlanTimelineInterval(id: item.id, startMinute: start, endMinute: snapshot.endMinute, isMemo: snapshot.isMemo),
                color: category?.displayColor ?? LiminalTheme.accent,
                isSelected: isSelected,
                isLocked: false,
                planTitleFontSize: CalendarPlanTitleMetrics.clamped(planTitleFontSize),
                planTitleBold: planTitleBold,
                activeResizeEdge: isSelected ? activeResizeEdge : nil,
                onSelect: {
                    if selectedItemID == item.id {
                        editingItem = item
                    } else {
                        selectedItemID = item.id
                        LiminalHaptics.selection()
                    }
                },
                onLongPress: { state, _ in if state == .began { deletionItem = item } },
                moveGesture: moveGesture(for: item)
            )
            .withBlockHeight(height)
            .frame(width: blockWidth, height: height + overflow * 2, alignment: .topLeading)
            .offset(y: -overflow)

            if isSelected {
                resizeHitTarget(edge: .start, item: item, width: blockWidth)
                    .offset(y: -EditablePlanBlockMetrics.resizeHitHandleHeight)
                resizeHitTarget(edge: .end, item: item, width: blockWidth)
                    .offset(y: height)
            }
        }
        .frame(width: blockWidth, height: height, alignment: .topLeading)
        .offset(x: TimelineHourAxisMetrics.columnWidth + blockSideInset + (snapshot.isMemo ? available * 0.52 + CGFloat(slot.column) * (blockWidth + 2) : 0), y: y)
        .zIndex(snapshot.isMemo ? (isSelected ? 10 : 5) : (isSelected ? 3 : 1))
    }

    private func resizeHitTarget(edge: EditablePlanResizeEdge, item: DayPresetEditorItem, width: CGFloat) -> some View {
        Color.clear
            .frame(width: min(width, EditablePlanBlockMetrics.resizeGripBackgroundWidth),
                   height: EditablePlanBlockMetrics.resizeHitHandleHeight)
            .contentShape(Rectangle())
            .gesture(resizeGesture(for: item, edge: edge))
            .frame(width: width)
            .accessibilityLabel(edge == .start ? "開始時刻を調整" : "終了時刻を調整")
    }

    private var allDayStrip: some View {
        HStack(spacing: 1) {
            gridPalette.hourColumn
                .frame(width: TimelineHourAxisMetrics.columnWidth)
            VStack(spacing: 1.5) {
                ForEach(allDayItems) { item in
                    let category = category(for: item.snapshot.categoryID)
                    Button { editingItem = item } label: {
                        CalendarDayTimelineAllDayRow(
                            title: item.snapshot.title.isEmpty ? category?.name ?? "予定" : item.snapshot.title,
                            tint: category?.displayColor ?? LiminalTheme.accent,
                            titleFontSize: CalendarPlanTitleMetrics.clamped(planTitleFontSize)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("予定を外す", role: .destructive) { deletionItem = item }
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(gridPalette.background)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(gridPalette.primaryLine)
    }

    private func moveGesture(for item: DayPresetEditorItem) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard activeResizeEdge == nil, zoomBaseScale == nil else { return }
                if moveBaseline?.id != item.id {
                    moveBaseline = item
                    moveDragSession = TimelineAxisDragSession(
                        startGlobalY: value.startLocation.y,
                        originalMinute: item.snapshot.startMinute,
                        axisMap: axisMap
                    )
                    selectedItemID = item.id
                }
                guard let baseline = moveBaseline,
                      baseline.id == item.id,
                      var session = moveDragSession
                else { return }
                let rawDelta = session.update(currentGlobalY: value.location.y, precision: snapPrecision)
                moveDragSession = session
                let alignedDelta = TimelineSnapPolicy.alignedDelta(
                    originalMinute: baseline.snapshot.startMinute,
                    relativeDelta: rawDelta,
                    precision: snapPrecision
                )
                let duration = baseline.snapshot.durationMinutes
                let start = min(24 * 60 - 1, max(0, baseline.snapshot.startMinute + alignedDelta))
                var candidate = baseline.snapshot
                candidate.startMinute = start
                candidate.endMinute = start + duration
                update(item.id, with: candidate)
            }
            .onEnded { _ in
                moveBaseline = nil
                moveDragSession = nil
                LiminalHaptics.commit()
            }
    }

    private func resizeGesture(
        for item: DayPresetEditorItem,
        edge: EditablePlanResizeEdge
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard zoomBaseScale == nil else { return }
                if resizeBaseline?.id != item.id || activeResizeEdge != edge {
                    resizeBaseline = item
                    resizeDragSession = TimelineAxisDragSession(
                        startGlobalY: value.startLocation.y,
                        originalMinute: edge == .start ? item.snapshot.startMinute : item.snapshot.endMinute,
                        axisMap: axisMap
                    )
                    activeResizeEdge = edge
                }
                guard let baseline = resizeBaseline,
                      baseline.id == item.id,
                      var session = resizeDragSession
                else { return }
                let rawDelta = session.update(currentGlobalY: value.location.y, precision: snapPrecision)
                resizeDragSession = session
                var candidate = baseline.snapshot
                switch edge {
                case .start:
                    let aligned = TimelineSnapPolicy.alignedMinute(
                        originalMinute: baseline.snapshot.startMinute,
                        relativeDelta: rawDelta,
                        precision: snapPrecision
                    )
                    candidate.startMinute = min(
                        baseline.snapshot.endMinute - snapPrecision.minutes,
                        max(0, aligned)
                    )
                case .end:
                    let aligned = TimelineSnapPolicy.alignedMinute(
                        originalMinute: baseline.snapshot.endMinute,
                        relativeDelta: rawDelta,
                        precision: snapPrecision
                    )
                    candidate.endMinute = min(
                        baseline.snapshot.startMinute + 24 * 60,
                        max(baseline.snapshot.startMinute + snapPrecision.minutes, aligned)
                    )
                }
                update(item.id, with: candidate)
            }
            .onEnded { _ in
                resizeBaseline = nil
                resizeDragSession = nil
                activeResizeEdge = nil
                LiminalHaptics.commit()
            }
    }

    private func updateDurationPresetPreview(_ preset: PlanPreset, at windowLocation: CGPoint?) {
        guard let local = localTimelineLocation(windowLocation),
              let snapshot = placedSnapshot(for: preset, at: local)
        else {
            libraryDrag = nil
            return
        }
        let height = max(
            minimumBlockHeight,
            axisMap.height(
                startMinute: snapshot.startMinute,
                endMinute: min(24 * 60, snapshot.endMinute)
            )
        )
        let location = CGPoint(
            x: timelineViewportSize.width / 2,
            y: TimelinePlanPresetPlacementGeometry.previewTopY(
                fingerY: local.y,
                cardHeight: height,
                viewportHeight: timelineViewportSize.height
            ) + height / 2
        )
        libraryDrag = DayPresetLibraryDrag(
            preset: preset,
            snapshot: snapshot,
            location: location
        )
        if lastPresetFeedbackMinute != snapshot.startMinute {
            lastPresetFeedbackMinute = snapshot.startMinute
            LiminalHaptics.selection()
        }
    }

    private func finishDurationPresetDrop(
        _ preset: PlanPreset,
        at windowLocation: CGPoint?
    ) -> String? {
        defer { libraryDrag = nil }
        guard let local = localTimelineLocation(windowLocation),
              let snapshot = placedSnapshot(for: preset, at: local)
        else {
            return "タイムラインの中へ置いてください。"
        }
        return add(snapshot, sourcePreset: preset)
    }

    private func placedSnapshot(for preset: PlanPreset, at local: CGPoint) -> PlanTemplateSnapshot? {
        guard local.y >= 0,
              local.y <= timelineViewportSize.height
        else { return nil }
        let contentY = local.y + timelineScrollOffset - timelineTopInset
            - TimelinePlanPresetPlacementGeometry.bottomGripClearance
        let rawEndMinute = Int(axisMap.minute(atY: contentY).rounded())
        let rawMinute = rawEndMinute - preset.snapshot.durationMinutes
        let snappedMinute = Int(
            (Double(rawMinute) / Double(snapPrecision.minutes)).rounded()
        ) * snapPrecision.minutes
        let latestStart = max(0, 24 * 60 - preset.snapshot.durationMinutes)
        return preset.snapshot.placed(at: min(latestStart, max(0, snappedMinute)))
    }

    private func localTimelineLocation(_ windowLocation: CGPoint?) -> CGPoint? {
        TimelinePlanPresetInteractionCoordinator.localLocation(
            windowLocation,
            in: timelineWindowFrame
        )
    }

    private func dragPreview(_ drag: DayPresetLibraryDrag) -> some View {
        let category = category(for: drag.snapshot.categoryID)
        let tint = category?.displayColor ?? LiminalTheme.accent
        let height = max(
            minimumBlockHeight,
            axisMap.height(
                startMinute: drag.snapshot.startMinute,
                endMinute: min(24 * 60, drag.snapshot.endMinute)
            )
        )
        let overflow = EditablePlanBlockMetrics.verticalOverflow
        return EditablePlanBlock(
            title: drag.preset.displayName,
            interval: PlanTimelineInterval(id: drag.preset.id,
                                           startMinute: drag.snapshot.startMinute,
                                           endMinute: drag.snapshot.endMinute),
            color: tint,
            isSelected: false,
            isLocked: false,
            planTitleFontSize: CalendarPlanTitleMetrics.clamped(planTitleFontSize),
            planTitleBold: planTitleBold,
            activeResizeEdge: nil,
            onSelect: {},
            onLongPress: { _, _ in },
            moveGesture: DragGesture()
        )
        .withBlockHeight(height)
        .frame(
            width: max(1, timelineViewportSize.width - TimelineHourAxisMetrics.columnWidth - blockSideInset * 2),
            height: height + overflow * 2
        )
        .position(
            x: drag.location.x + TimelineHourAxisMetrics.columnWidth / 2,
            y: drag.location.y
        )
        .allowsHitTesting(false)
    }

    private var axisMap: TimelineAxisMap {
        TimelineAxisMap(
            hourHeight: hourHeight,
            intervals: timedItems.map {
                TimelineAxisInterval(
                    startMinute: min(24 * 60, max(0, $0.snapshot.startMinute)),
                    endMinute: min(24 * 60, max(1, $0.snapshot.endMinute))
                )
            },
            minimumIntervalHeight: minimumBlockHeight
        )
    }

    private var hourHeight: CGFloat {
        DayTimelineZoomPolicy.hourHeight(
            for: transientHourScale ?? DayTimelineZoomPolicy.normalizedScale(storedHourScale)
        )
    }

    private var timelineZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard moveBaseline == nil, resizeBaseline == nil, libraryDrag == nil else { return }
                if creationDraft != nil { creationCancelledByZoom = true }
                creationDraft = nil
                creationCategoryID = nil
                if zoomBaseScale == nil {
                    zoomBaseScale = DayTimelineZoomPolicy.normalizedScale(storedHourScale)
                    zoomAnchorMinute = axisMap.minute(
                        atY: timelineScrollOffset + timelineViewportSize.height / 2 - timelineTopInset
                    )
                }
                guard let zoomBaseScale else { return }
                applyZoomScale(DayTimelineZoomPolicy.magnifiedScale(
                    baseScale: zoomBaseScale,
                    magnification: value.magnification
                ))
            }
            .onEnded { _ in
                guard zoomBaseScale != nil else { return }
                let scale = DayTimelineZoomPolicy.snappedScale(
                    transientHourScale ?? DayTimelineZoomPolicy.normalizedScale(storedHourScale)
                )
                applyZoomScale(scale)
                storedHourScale = Double(scale)
                transientHourScale = nil
                zoomBaseScale = nil
                zoomAnchorMinute = nil
            }
    }

    private func applyZoomScale(_ scale: CGFloat) {
        guard let zoomAnchorMinute else { return }
        transientHourScale = scale
        let map = axisMap
        let maximumY = max(
            0,
            timelineTopInset + map.contentHeight + bottomScrollPadding - timelineViewportSize.height
        )
        let targetY = min(
            maximumY,
            max(0, timelineTopInset + map.y(forMinute: zoomAnchorMinute) - timelineViewportSize.height / 2)
        )
        timelineScrollPosition.scrollTo(y: targetY)
        timelineScrollOffset = targetY
    }

    private var snapPrecision: TimelineSnapPrecision {
        TimelineSnapPrecision.normalized(minutes: storedSnapPrecisionMinutes)
    }

    private var timedItems: [DayPresetEditorItem] {
        items.filter { !$0.snapshot.isAllDay }.sorted {
            if $0.snapshot.startMinute == $1.snapshot.startMinute {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.snapshot.startMinute < $1.snapshot.startMinute
        }
    }

    private var allDayItems: [DayPresetEditorItem] {
        items.filter(\.snapshot.isAllDay)
    }

    private var canSave: Bool {
        !items.isEmpty
            && items.count <= 24
            && allDayItems.count <= 3
            && !DayPresetApplyPlanner.hasConflictsWithinPreset(items.map(\.snapshot))
    }

    private func addFixedPreset(_ preset: PlanPreset) {
        if let error = add(preset.snapshot, sourcePreset: preset) {
            operationError = error
        }
    }

    private func add(
        _ snapshot: PlanTemplateSnapshot,
        sourcePreset: PlanPreset
    ) -> String? {
        if let error = saveDraftItem(UUID(), snapshot: snapshot) { return error }
        _ = presetStore.markUsed(sourcePreset)
        return nil
    }

    private func startNewItem(at contentY: CGFloat) {
        let minute = Int(axisMap.minute(atY: contentY - timelineTopInset))
        let start = min(23 * 60, max(0, minute / snapPrecision.minutes * snapPrecision.minutes))
        editingItem = DayPresetEditorItem(snapshot: PlanTemplateSnapshot(
            title: "",
            categoryID: selectedCategoryID,
            startMinute: start,
            endMinute: start + 60,
            isAllDay: false,
            isImportant: false,
            note: nil,
            isPublic: false
        ))
    }

    private func saveDraftItem(_ id: UUID, snapshot: PlanTemplateSnapshot) -> String? {
        guard snapshot.hasValidTime else { return "開始と終了の時刻を確認してください。" }
        var proposedItems = items
        if let index = proposedItems.firstIndex(where: { $0.id == id }) {
            proposedItems[index].snapshot = snapshot
        } else {
            proposedItems.append(DayPresetEditorItem(id: id, snapshot: snapshot))
        }
        let proposed = proposedItems.map(\.snapshot)
        guard proposed.count <= 24 else {
            return "一日に入れられる予定は24件までです。"
        }
        guard proposed.filter(\.isAllDay).count <= 3 else {
            return "終日の予定は3件までです。"
        }
        guard !DayPresetApplyPlanner.hasConflictsWithinPreset(proposed) else {
            return "ほかの予定と重なっています。空いている位置へ置いてください。"
        }
        items = proposedItems
        selectedItemID = id
        LiminalHaptics.commit()
        return nil
    }

    private func update(_ id: UUID, with snapshot: PlanTemplateSnapshot) {
        guard snapshot.hasValidTime,
              let index = items.firstIndex(where: { $0.id == id })
        else { return }
        var proposed = items
        proposed[index].snapshot = snapshot
        guard !DayPresetApplyPlanner.hasConflictsWithinPreset(proposed.map(\.snapshot)) else {
            return
        }
        guard items[index].snapshot != snapshot else { return }
        items = proposed
        LiminalHaptics.selection()
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selectedItemID == id { selectedItemID = nil }
        LiminalHaptics.commit()
    }

    private func save() {
        let snapshots = items.map { item in
            var snapshot = item.snapshot
            snapshot.templateItemID = item.id
            return snapshot
        }.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startMinute < $1.startMinute
        }
        let didSave: Bool
        if let preset {
            didSave = presetStore.updateDayPreset(preset, name: name, items: snapshots, colorHex: presetColor.hexString, icon: presetIcon, recurrence: .some(recurrenceRule))
        } else {
            didSave = presetStore.createDayPreset(name: name, items: snapshots, colorHex: presetColor.hexString, icon: presetIcon, recurrence: .some(recurrenceRule)) != nil
        }
        guard didSave else {
            operationError = "内容を確認して、もう一度保存してください。"
            return
        }
        LiminalHaptics.commit()
        dismiss()
    }

    private func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    private func timeRange(_ snapshot: PlanTemplateSnapshot) -> String {
        "\(minuteText(snapshot.startMinute))–\(minuteText(snapshot.endMinute))"
    }

    private func minuteText(_ minute: Int) -> String {
        let normalized = max(0, minute)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private func normalizeStoredHourScale() {
        let normalized = DayTimelineZoomPolicy.normalizedScale(storedHourScale)
        if storedHourScale != Double(normalized) {
            storedHourScale = Double(normalized)
        }
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented { operationError = nil }
        }
    }
}

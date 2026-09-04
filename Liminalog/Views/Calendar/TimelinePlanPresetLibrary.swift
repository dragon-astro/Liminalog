import SwiftUI
import UIKit

/// ページングの外にあるプリセットドロワーと、現在表示中のタイムラインを接続する。
///
/// ドロワー自体は日付ページに属さず、日間・週間それぞれの配置ロジックだけを
/// 現在のページから登録することで、ページを送っても画面下に留まれる。
@MainActor
final class TimelinePlanPresetInteractionCoordinator {
    typealias FixedTimeHandler = (PlanPreset) -> Void
    typealias DragHandler = (PlanPreset, CGPoint?) -> Void
    typealias DropHandler = (PlanPreset, CGPoint?) -> String?
    typealias DraggingHandler = (Bool) -> Void

    private var activeTargetID: String?
    private var activeTargetFrame: CGRect?
    private var fixedTimeHandler: FixedTimeHandler?
    private var dragChangedHandler: DragHandler?
    private var dropHandler: DropHandler?
    private var draggingChangedHandler: DraggingHandler?

    func activate(
        targetID: String,
        targetFrame: CGRect,
        onFixedTimeTap: @escaping FixedTimeHandler,
        onDurationDragChanged: @escaping DragHandler,
        onDurationDrop: @escaping DropHandler,
        onDraggingChanged: @escaping DraggingHandler
    ) {
        activeTargetID = targetID
        activeTargetFrame = targetFrame
        fixedTimeHandler = onFixedTimeTap
        dragChangedHandler = onDurationDragChanged
        dropHandler = onDurationDrop
        draggingChangedHandler = onDraggingChanged
    }

    func deactivate(targetID: String) {
        guard activeTargetID == targetID else { return }
        activeTargetID = nil
        activeTargetFrame = nil
        fixedTimeHandler = nil
        dragChangedHandler = nil
        dropHandler = nil
        draggingChangedHandler = nil
    }

    func addFixedTimePreset(_ preset: PlanPreset) {
        fixedTimeHandler?(preset)
    }

    func updateDurationPreset(_ preset: PlanPreset, at location: CGPoint?) {
        dragChangedHandler?(preset, localLocation(for: location))
    }

    func finishDurationPreset(_ preset: PlanPreset, at location: CGPoint?) -> String? {
        guard let dropHandler else {
            return "表示中のタイムラインを読み取れませんでした。"
        }
        return dropHandler(preset, localLocation(for: location))
    }

    func setDragging(_ active: Bool) {
        draggingChangedHandler?(active)
    }

    private func localLocation(for location: CGPoint?) -> CGPoint? {
        Self.localLocation(location, in: activeTargetFrame)
    }

    static func localLocation(_ location: CGPoint?, in targetFrame: CGRect?) -> CGPoint? {
        guard let location, let targetFrame else { return nil }
        return CGPoint(
            x: location.x - targetFrame.minX,
            y: location.y - targetFrame.minY
        )
    }
}

enum TimelinePlanPresetPlacementGeometry {
    static let bottomGripClearance: CGFloat = 8

    static func axisY(
        windowFingerY: CGFloat,
        contentFrameMinY: CGFloat,
        timelineTopInset: CGFloat
    ) -> CGFloat {
        windowFingerY - contentFrameMinY - timelineTopInset
    }

    static func previewTopY(
        fingerY: CGFloat,
        cardHeight: CGFloat,
        viewportHeight: CGFloat,
        minimumY: CGFloat = 0,
        bottomGripClearance: CGFloat = bottomGripClearance
    ) -> CGFloat {
        let safeMinimumY = max(0, minimumY)
        let maximumY = max(safeMinimumY, viewportHeight - max(0, cardHeight))
        let proposedY = fingerY - max(0, cardHeight) - max(0, bottomGripClearance)
        return min(maximumY, max(safeMinimumY, proposedY))
    }
}

/// 日間・週間タイムラインから直接使う予定プリセットドロワー。
/// 閉じている間は小さな起動ボタンだけを置き、開いた時だけタブバーの領域まで使う。
enum TimelinePlanPresetLauncherPlacement {
    case bottomLeading
    case bottomTrailing
    case externalControl
}

struct TimelinePlanPresetLibrary: View {
    let presets: [PlanPreset]
    let categories: [Category]
    let onFixedTimeTap: (PlanPreset) -> Void
    let onDurationDragChanged: (PlanPreset, CGPoint?) -> Void
    let onDurationDrop: (PlanPreset, CGPoint?) -> String?
    let onDraggingChanged: (Bool) -> Void
    let launcherPlacement: TimelinePlanPresetLauncherPlacement
    private let externalIsPresented: Binding<Bool>?
    private let onDismiss: () -> Void

    @State private var internalIsPresented = false
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var draggedPresetID: UUID?
    @State private var placementError: String?
    @State private var selectedPresentationDetent: PresentationDetent = .height(264)

    init(
        presets: [PlanPreset],
        categories: [Category],
        onFixedTimeTap: @escaping (PlanPreset) -> Void,
        onDurationDragChanged: @escaping (PlanPreset, CGPoint?) -> Void,
        onDurationDrop: @escaping (PlanPreset, CGPoint?) -> String?,
        onDraggingChanged: @escaping (Bool) -> Void,
        launcherPlacement: TimelinePlanPresetLauncherPlacement = .bottomTrailing,
        isPresented: Binding<Bool>? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.presets = presets
        self.categories = categories
        self.onFixedTimeTap = onFixedTimeTap
        self.onDurationDragChanged = onDurationDragChanged
        self.onDurationDrop = onDurationDrop
        self.onDraggingChanged = onDraggingChanged
        self.launcherPlacement = launcherPlacement
        self.externalIsPresented = isPresented
        self.onDismiss = onDismiss
    }

    var body: some View {
        positionedLauncher
            .sheet(isPresented: drawerPresentation, onDismiss: handleDrawerDismiss) {
                drawer
            }
            .accessibilityIdentifier("timeline-plan-preset-library")
    }

    @ViewBuilder
    private var positionedLauncher: some View {
        switch launcherPlacement {
        case .bottomLeading:
            launcher
                .padding(.leading, 12)
                .padding(.bottom, 10)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 60,
                    maxHeight: 60,
                    alignment: .bottomLeading
                )
        case .bottomTrailing:
            launcher
                .padding(.trailing, 12)
                .padding(.bottom, 10)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 60,
                    maxHeight: 60,
                    alignment: .bottomTrailing
                )
        case .externalControl:
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var drawer: some View {
        drawerContents
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LiminalTheme.plainSheetBackground)
            .background {
                TimelinePlanPresetSheetRetreatBridge(
                    isRetreated: isDurationDragActive
                )
            }
            .presentationDetents(
                [compactPresentationDetent, expandedPresentationDetent],
                selection: $selectedPresentationDetent
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(LiminalTheme.plainSheetBackground)
            .presentationBackgroundInteraction(.enabled)
            .alert("予定を追加できませんでした", isPresented: placementErrorPresented) {
                Button("OK", role: .cancel) { placementError = nil }
            } message: {
                Text(placementError ?? "")
            }
    }

    private var launcher: some View {
        Button {
            LiminalHaptics.openSheet()
            drawerPresentation.wrappedValue = true
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(LiminalTheme.accent, in: Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("予定プリセットを開く")
    }

    private var drawerContents: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("予定プリセット", systemImage: "bookmark.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    closeDrawer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("予定プリセットを閉じる")
            }
            .frame(height: 48)
            .padding(.horizontal, 14)

            quickShelf
                .padding(.bottom, 8)

            Divider()

            compactControls
                .padding(.vertical, 7)

            fullLibrary
        }
        .frame(maxWidth: .infinity)
    }

    private var quickShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPresets) { preset in
                    tile(preset, style: .quick)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 1)
        }
    }

    private var compactControls: some View {
        PlanPresetFilterControls(
            searchText: $searchText,
            selectedCategoryID: $selectedCategoryID,
            categories: libraryCategories,
            compact: true
        )
        .padding(.horizontal, 14)
    }

    private var fullLibrary: some View {
        ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(filteredPresets) { preset in
                    tile(preset, style: .library)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 1)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func tile(_ preset: PlanPreset, style: PlanPresetLibraryCardStyle) -> some View {
        if preset.isAllDay || preset.placementMode == .fixedTime {
            tileContent(preset, style: style)
                .onTapGesture {
                    onFixedTimeTap(preset)
                    closeDrawer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "追加") { onFixedTimeTap(preset) }
        } else {
            durationTile(preset, style: style)
                .overlay {
                    TimelinePlanPresetLongPressDragSurface(
                        minimumDuration: durationLongPressMinimumDuration,
                        maximumDistance: durationLongPressMaximumDistance
                    ) { event in
                        handleDurationDragEvent(event, preset: preset)
                    }
                }
        }
    }

    private func durationTile(
        _ preset: PlanPreset,
        style: PlanPresetLibraryCardStyle
    ) -> some View {
        tileContent(preset, style: style)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(preset.displayName)、\(durationText(preset.snapshot.durationMinutes))、長押しして配置")
    }

    private func tileContent(_ preset: PlanPreset, style: PlanPresetLibraryCardStyle) -> some View {
        let category = category(for: preset.categoryID)
        let isFixed = preset.isAllDay || preset.placementMode == .fixedTime
        return PlanPresetLibraryCard(
            preset: preset,
            category: category,
            style: style,
            trailingSymbol: isFixed ? "plus.circle.fill" : "hand.draw.fill"
        )
    }

    private func handleDurationDragEvent(
        _ event: TimelinePlanPresetLongPressDragEvent,
        preset: PlanPreset
    ) {
        switch event {
        case .began(let location), .changed(let location):
            beginDurationDrag(for: preset)
            onDurationDragChanged(preset, location)
        case .ended(let location):
            completeDurationDrag(preset, at: location)
        case .cancelled:
            guard draggedPresetID == preset.id else { return }
            draggedPresetID = nil
            onDraggingChanged(false)
        }
    }

    private var durationLongPressMinimumDuration: Double {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LiminalogDebugImmediatePresetDrag") {
            return 0
        }
        #endif
        return 0.14
    }

    private var durationLongPressMaximumDistance: CGFloat {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LiminalogDebugImmediatePresetDrag") {
            return 10_000
        }
        #endif
        return 12
    }

    private func beginDurationDrag(for preset: PlanPreset) {
        guard draggedPresetID == nil else { return }
        draggedPresetID = preset.id
        LiminalHaptics.selection()
        onDraggingChanged(true)
    }

    private func completeDurationDrag(_ preset: PlanPreset, at location: CGPoint) {
        let error = onDurationDrop(preset, location)
        withAnimation(.snappy(duration: 0.18)) {
            draggedPresetID = nil
        }
        onDraggingChanged(false)
        if let error {
            LiminalHaptics.warning()
            // sheetの復帰アニメーション後にalertを出す。
            // 同時に出すとpresentationの最前面がalertに切り替わり、
            // 退避中のsheetを戻せない。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                placementError = error
            }
        }
    }

    private var placementErrorPresented: Binding<Bool> {
        Binding {
            placementError != nil
        } set: { isPresented in
            if !isPresented { placementError = nil }
        }
    }

    private var compactPresentationDetent: PresentationDetent {
        .height(264)
    }

    private var isDurationDragActive: Bool {
        draggedPresetID != nil
    }

    private var expandedPresentationDetent: PresentationDetent {
        .medium
    }

    private func resetPresentation() {
        draggedPresetID = nil
        selectedPresentationDetent = compactPresentationDetent
        onDraggingChanged(false)
    }

    private var drawerPresentation: Binding<Bool> {
        externalIsPresented ?? $internalIsPresented
    }

    private func handleDrawerDismiss() {
        resetPresentation()
        onDismiss()
    }

    private func closeDrawer() {
        draggedPresetID = nil
        onDraggingChanged(false)
        drawerPresentation.wrappedValue = false
    }

    private var quickPresets: [PlanPreset] {
        Array(presets.sorted {
            if $0.useCount == $1.useCount { return $0.sortOrder < $1.sortOrder }
            return $0.useCount > $1.useCount
        }.prefix(6))
    }

    private var filteredPresets: [PlanPreset] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.filter {
            (selectedCategoryID == nil || $0.categoryID == selectedCategoryID)
                && (search.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    private var libraryCategories: [Category] {
        let usedIDs = Set(presets.compactMap(\.categoryID))
        return categories.filter { usedIDs.contains($0.id) }
    }

    private func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    private func fixedTimeText(_ preset: PlanPreset) -> String {
        if preset.isAllDay { return "終日" }
        return "\(minuteText(preset.startMinute))–\(minuteText(preset.endMinute))"
    }

    private func minuteText(_ minute: Int) -> String {
        let value = max(0, minute)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }
}

enum TimelinePlanPresetLongPressDragEvent {
    case began(CGPoint)
    case changed(CGPoint)
    case ended(CGPoint)
    case cancelled
}

/// SwiftUIの `.global` は標準sheetと背面で原点が一致しない。
/// UIKitのwindow座標で長押し〜移動〜終了を追跡し、日間・週間に同じ座標を渡す。
struct TimelinePlanPresetLongPressDragSurface: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let maximumDistance: CGFloat
    let onEvent: (TimelinePlanPresetLongPressDragEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = maximumDistance
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.recognizer?.minimumPressDuration = minimumDuration
        context.coordinator.recognizer?.allowableMovement = maximumDistance
    }

    final class Coordinator: NSObject {
        var onEvent: (TimelinePlanPresetLongPressDragEvent) -> Void
        weak var recognizer: UILongPressGestureRecognizer?

        init(onEvent: @escaping (TimelinePlanPresetLongPressDragEvent) -> Void) {
            self.onEvent = onEvent
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let window = recognizer.view?.window else {
                if recognizer.state == .cancelled || recognizer.state == .failed {
                    onEvent(.cancelled)
                }
                return
            }
            let location = recognizer.location(in: window)
            switch recognizer.state {
            case .began:
                onEvent(.began(location))
            case .changed:
                onEvent(.changed(location))
            case .ended:
                onEvent(.ended(location))
            case .cancelled, .failed:
                onEvent(.cancelled)
            default:
                break
            }
        }
    }
}

/// 長押し成立後はsheet全体を画面外へ退避させる。
/// 認識器はUIKitのwindow座標を追うため、親Viewを移動しても指の追跡が継続する。
private struct TimelinePlanPresetSheetRetreatBridge: UIViewRepresentable {
    let isRetreated: Bool

    func makeUIView(context: Context) -> RetreatView {
        RetreatView()
    }

    func updateUIView(_ uiView: RetreatView, context: Context) {
        uiView.setRetreated(isRetreated, animated: uiView.window != nil)
    }

    static func dismantleUIView(_ uiView: RetreatView, coordinator: Void) {
        uiView.restoreImmediately()
    }

    final class RetreatView: UIView {
        private weak var presentationContainer: UIView?
        private var shouldRetreat = false
        private var updateGeneration = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyRetreat(animated: false)
        }

        func setRetreated(_ value: Bool, animated: Bool) {
            shouldRetreat = value
            updateGeneration += 1
            let generation = updateGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.updateGeneration else { return }
                self.applyRetreat(animated: animated)
            }
        }

        func restoreImmediately() {
            updateGeneration += 1
            presentationContainer?.layer.removeAllAnimations()
            presentationContainer?.transform = .identity
        }

        private func applyRetreat(animated: Bool) {
            guard let window else { return }
            let container: UIView
            if shouldRetreat {
                guard let currentContainer = currentPresentationContainer(in: window) else { return }
                presentationContainer = currentContainer
                container = currentContainer
            } else if let presentationContainer {
                container = presentationContainer
            } else {
                guard let currentContainer = currentPresentationContainer(in: window) else { return }
                container = currentContainer
            }
            let targetTransform = shouldRetreat
                ? CGAffineTransform(translationX: 0, y: container.bounds.height + 24)
                : .identity
            guard container.transform != targetTransform else { return }
            let changes = {
                container.transform = targetTransform
            }
            if animated {
                UIView.animate(
                    withDuration: shouldRetreat ? 0.16 : 0.20,
                    delay: 0,
                    options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
                    animations: changes
                )
            } else {
                changes()
            }
        }

        private func currentPresentationContainer(in window: UIWindow) -> UIView? {
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller?.presentationController?.containerView
        }
    }
}

/// SwiftUI Viewの領域をUIKitのwindow座標で通知する。
/// sheetと背面のHostingControllerが別でも同じ原点にそろえられる。
@MainActor
final class TimelineWindowFrameSource {
    fileprivate weak var view: UIView?

    var currentFrame: CGRect? {
        guard let view, let window = view.window else { return nil }
        let frame = view.convert(view.bounds, to: window)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}

struct TimelineWindowFrameReader: UIViewRepresentable {
    let frameSource: TimelineWindowFrameSource?
    let onChange: ((CGRect) -> Void)?

    /// Keeps a weak UIKit view reference so callers can read its current frame
    /// on demand. No callback is scheduled while the enclosing scroll view moves.
    init(frameSource: TimelineWindowFrameSource) {
        self.frameSource = frameSource
        self.onChange = nil
    }

    /// Publishes changes for viewport readers whose frame is expected to stay
    /// stable while timeline content scrolls underneath them.
    init(onChange: @escaping (CGRect) -> Void) {
        self.frameSource = nil
        self.onChange = onChange
    }

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        frameSource?.view = view
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onChange = onChange
        frameSource?.view = uiView
        if onChange != nil {
            uiView.publishFrameIfNeeded()
        }
    }

    final class ReaderView: UIView {
        var onChange: ((CGRect) -> Void)?
        private var lastFrame: CGRect?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishFrameIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishFrameIfNeeded()
        }

        func publishFrameIfNeeded() {
            guard let onChange, let window else { return }
            let frame = convert(bounds, to: window)
            guard frame.width > 0, frame.height > 0, frame != lastFrame else { return }
            lastFrame = frame
            DispatchQueue.main.async {
                onChange(frame)
            }
        }
    }
}

enum PlanPresetLibraryCardStyle {
    case quick
    case library
}

struct PlanPresetLibraryCard: View {
    let preset: PlanPreset
    let category: Category?
    let style: PlanPresetLibraryCardStyle
    let trailingSymbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: style == .quick ? 3 : 2) {
            HStack(spacing: 4) {
                Image(
                    systemName: CategoryIconCatalog.displaySymbol(
                        for: category?.icon ?? "questionmark.circle"
                    )
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 13)
                .accessibilityHidden(true)

                Text(preset.displayName)
                    .font((style == .quick ? Font.caption : Font.caption2).weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }

            Text(category == nil ? "\(summary) · カテゴリ未設定" : summary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiminalTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, style == .quick ? 8 : 7)
        .padding(.vertical, style == .quick ? 7 : 5)
        .frame(
            width: style == .quick ? 106 : nil,
            height: style == .quick ? 54 : 44,
            alignment: .topLeading
        )
        .frame(maxWidth: style == .quick ? nil : .infinity, alignment: .topLeading)
        .background(tint.opacity(isFixed ? 0.11 : 0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    tint.opacity(isFixed ? 0.28 : 0.52),
                    style: StrokeStyle(lineWidth: 1, dash: isFixed ? [] : [4, 3])
                )
        }
        .contentShape(Rectangle())
    }

    private var tint: Color {
        category?.displayColor ?? LiminalTheme.secondaryText
    }

    private var isFixed: Bool {
        preset.isAllDay || preset.placementMode == .fixedTime
    }

    private var summary: String {
        if preset.isAllDay { return "終日" }
        if preset.placementMode == .fixedTime {
            return "\(Self.minuteText(preset.startMinute))–\(Self.minuteText(preset.endMinute))"
        }
        return Self.durationText(preset.snapshot.durationMinutes)
    }

    private static func minuteText(_ minute: Int) -> String {
        let value = max(0, minute)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }
}

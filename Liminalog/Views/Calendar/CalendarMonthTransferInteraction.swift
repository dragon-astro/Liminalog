import SwiftUI

@MainActor
@Observable
final class CalendarMonthTransferInteraction {
    struct Request: Identifiable {
        let id = UUID()
        let planID: UUID
        let title: String
        let mode: CalendarPlanTransferMode
        let timeText: String
        let tint: Color
        // Remains true after the finger lifts, until the transfer finishes.
        let keepsDrawerPresented: Bool
    }
    enum Action { case confirm, cancel }
    var presetRequest: Request?
    var request: Request?
    var selectedDates: Set<Date> = []
    var hoveredDate: Date?
    var isDragging = false
    var dragLocation: CGPoint?
    var action: Action?
    var error: String?
    #if DEBUG || LIMINALOG_UI_TESTING
    // Test observation only: incremented by the real hold callback, never simulated.
    var recognizedHoldCount = 0
    var drawerDismissCount = 0
    private var releasedAt: TimeInterval?
    private var commitMilliseconds: Double = -1
    private var restoreMilliseconds: Double = -1
    var uiTestingValue: String {
        let value = "recognizedHolds:\(recognizedHoldCount)"
        guard ProcessInfo.processInfo.arguments.contains("-LiminalogMeasureMonthDrop") else { return value }
        return "\(value)|commit:\(commitMilliseconds)|restore:\(restoreMilliseconds)|dismiss:\(drawerDismissCount)"
    }
    func recordCommit() {
        if let releasedAt { commitMilliseconds = (ProcessInfo.processInfo.systemUptime - releasedAt) * 1000 }
    }
    func recordRestoreRequest() {
        if let releasedAt { restoreMilliseconds = (ProcessInfo.processInfo.systemUptime - releasedAt) * 1000 }
    }
    #endif
    var dayStatuses: [Date: CalendarPlanTransferDayStatus] = [:]
    @ObservationIgnored let rootFrame = TimelineWindowFrameSource()
    @ObservationIgnored let viewportFrame = TimelineWindowFrameSource()
    @ObservationIgnored var dayFrames: [UUID: (date: Date, source: TimelineWindowFrameSource)] = [:]

    static func dropDate(at point: CGPoint, viewport: CGRect, frames: [(Date, CGRect)]) -> Date? {
        guard viewport.contains(point) else { return nil }
        return frames.first { $0.1.contains(point) }?.0
    }

    func begin(_ plan: PlanBlock, mode: CalendarPlanTransferMode, dragging: Bool = false) {
        #if DEBUG || LIMINALOG_UI_TESTING
        if dragging { recognizedHoldCount += 1 }
        releasedAt = nil
        commitMilliseconds = -1
        restoreMilliseconds = -1
        drawerDismissCount = 0
        #endif
        isDragging = dragging
        selectedDates = []
        hoveredDate = nil
        action = nil
        error = nil
        dayStatuses = [:]
        request = Request(planID: plan.id, title: plan.title, mode: mode,
            timeText: plan.isAllDay ? "終日" : "\(plan.startTime.shortTime)–\(plan.endTime.shortTime)",
            tint: plan.category?.displayColor ?? LiminalTheme.accent,
            keepsDrawerPresented: dragging)
    }

    func beginPreset(_ preset: PlanPreset, tint: Color, at point: CGPoint) {
        guard request == nil else { return }
        presetRequest = Request(planID: preset.id, title: preset.displayName, mode: .copy,
            timeText: preset.isAllDay ? "終日" : preset.placementMode == .duration
                ? "\(preset.snapshot.durationMinutes)分・置いて開始時刻を指定"
                : String(format: "%02d:%02d–%02d:%02d", preset.startMinute / 60, preset.startMinute % 60, preset.endMinute / 60, preset.endMinute % 60),
            tint: tint, keepsDrawerPresented: true)
        isDragging = true
        updateDrag(at: point)
        LiminalHaptics.selection()
    }

    func endPreset(at point: CGPoint?) -> Date? {
        guard presetRequest != nil else { return nil }
        let target = point.flatMap { date(at: $0) }
        presetRequest = nil; isDragging = false; hoveredDate = nil; dragLocation = nil
        return target
    }

    func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if selectedDates.contains(day) { selectedDates.remove(day) }
        else if request?.mode == .move { selectedDates = [day] }
        else { selectedDates.insert(day) }
        LiminalHaptics.selection()
    }

    func updateDrag(at point: CGPoint) {
        guard isDragging else { return }
        dragLocation = point
        let day = date(at: point)
        if hoveredDate != day {
            hoveredDate = day
            if day != nil { LiminalHaptics.selection() }
        }
    }

    func finishDrag(at point: CGPoint?) {
        guard isDragging else { return }
        #if DEBUG || LIMINALOG_UI_TESTING
        releasedAt = ProcessInfo.processInfo.systemUptime
        #endif
        if let point { updateDrag(at: point) }
        let target = point == nil ? nil : hoveredDate
        isDragging = false
        dragLocation = nil
        hoveredDate = nil
        selectedDates = target.map { [$0] } ?? []
        action = target == nil ? .cancel : .confirm
    }

    func date(at point: CGPoint) -> Date? {
        guard let viewport = viewportFrame.currentFrame else { return nil }
        let frames = dayFrames.values.compactMap { entry -> (Date, CGRect)? in
            guard let frame = entry.source.currentFrame else { return nil }
            return (entry.date, frame)
        }
        return Self.dropDate(at: point, viewport: viewport, frames: frames)
    }

    func cancel() {
        request = nil
        selectedDates = []
        hoveredDate = nil
        isDragging = false
        dragLocation = nil
        action = nil
        dayStatuses = [:]
        error = nil
    }
}

private struct CalendarMonthTransferKey: EnvironmentKey {
    static let defaultValue: CalendarMonthTransferInteraction? = nil
}
extension EnvironmentValues {
    var monthPlanTransfer: CalendarMonthTransferInteraction? {
        get { self[CalendarMonthTransferKey.self] }
        set { self[CalendarMonthTransferKey.self] = newValue }
    }
}

struct CalendarPlanDropTarget: ViewModifier {
    @Environment(\.monthPlanTransfer) private var interaction
    @State private var frameSource = TimelineWindowFrameSource()
    @State private var frameID = UUID()
    let date: Date

    func body(content: Content) -> some View {
        content
            .background(TimelineWindowFrameReader(frameSource: frameSource))
            .onAppear { interaction?.dayFrames[frameID] = (date, frameSource) }
            .onDisappear { interaction?.dayFrames.removeValue(forKey: frameID) }
            .overlay {
                if let interaction, (interaction.request != nil || interaction.presetRequest != nil) {
                    let day = Calendar.current.startOfDay(for: date)
                    let selected = interaction.selectedDates.contains(day)
                    let hovered = interaction.hoveredDate == day
                    if selected || hovered {
                        Rectangle().fill(LiminalTheme.accent.opacity(0.22))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .font(.body).foregroundStyle(LiminalTheme.accent).padding(4)
                            }
                            .allowsHitTesting(false)
                    }
                    if let warning = interaction.dayStatuses[day]?.warning {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                    .padding(3).background(.background, in: Circle())
                                    .accessibilityLabel(warning)
                            }
                            Spacer()
                        }
                        .padding(3).allowsHitTesting(false)
                    }
                }
            }
            .accessibilityHint(interaction?.dayStatuses[Calendar.current.startOfDay(for: date)]?.warning ?? "")
    }
}

struct CalendarMonthDragPreview: View {
    let interaction: CalendarMonthTransferInteraction

    var body: some View {
        if interaction.isDragging, let request = interaction.presetRequest ?? interaction.request, let point = interaction.dragLocation,
           let frame = interaction.rootFrame.currentFrame {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title).font(.subheadline.bold()).lineLimit(1)
                Text(request.timeText).font(.caption.monospacedDigit())
                if let day = interaction.hoveredDate {
                    Label(day.japaneseMonthDayShortWeekday,
                          systemImage: interaction.dayStatuses[day]?.warning == nil ? "calendar" : "exclamationmark.triangle.fill")
                        .font(.caption)
                }
            }
            .foregroundStyle(LiminalTheme.text)
            .padding(10).frame(width: 180, alignment: .leading)
            .background(CalendarDrawerStyle.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(request.tint, lineWidth: 2))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .position(x: min(max(90, point.x - frame.minX), max(90, frame.width - 90)),
                      y: max(44, point.y - frame.minY - 55))
            .allowsHitTesting(false)
        }
    }
}

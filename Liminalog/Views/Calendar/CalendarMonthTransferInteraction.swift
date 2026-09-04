import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CalendarMonthTransferInteraction {
    struct Request {
        let planID: UUID
        let title: String
        let mode: CalendarPlanTransferMode
    }
    struct Drop: Equatable {
        let planID: UUID
        let date: Date
    }
    static let dragType = "app.YasudaRyuga.Liminalog.calendar-plan"
    static func dropDate(x: CGFloat, width: CGFloat, dates: [Date]) -> Date? {
        guard width > 0, x >= 0, x < width, !dates.isEmpty else { return nil }
        return dates[min(dates.count - 1, Int(x / width * CGFloat(dates.count)))]
    }
    var request: Request?
    var selectedDates: Set<Date> = []
    var draggedPlanID: UUID?
    var hoveredDate: Date?
    var pendingDrop: Drop?
    var error: String?

    func begin(_ plan: PlanBlock, mode: CalendarPlanTransferMode) {
        request = Request(planID: plan.id, title: plan.title, mode: mode)
        selectedDates = []
        draggedPlanID = nil
        hoveredDate = nil
    }

    func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if selectedDates.contains(day) { selectedDates.remove(day) }
        else if request?.mode == .move { selectedDates = [day] }
        else { selectedDates.insert(day) }
        LiminalHaptics.selection()
    }

    func cancel() {
        request = nil
        selectedDates = []
        draggedPlanID = nil
        hoveredDate = nil
    }

    func dragProvider(for plan: PlanBlock) -> NSItemProvider {
        draggedPlanID = plan.id
        let provider = NSItemProvider()
        let data = Data(plan.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        LiminalHaptics.selection()
        return provider
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
    let date: Date

    func body(content: Content) -> some View {
        content
            .overlay {
                if let interaction {
                    let selected = interaction.selectedDates.contains(Calendar.current.startOfDay(for: date))
                    let hovered = interaction.hoveredDate == date
                    if selected || hovered {
                        Rectangle().fill(LiminalTheme.accent.opacity(0.22))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .font(.body).foregroundStyle(LiminalTheme.accent)
                                    .padding(4)
                            }
                            .allowsHitTesting(false)
                    }
                }
            }
    }
}

/// The entire week accepts drops, including the multi-day bars over the day cells.
struct CalendarPlanWeekDropTarget: ViewModifier {
    @Environment(\.monthPlanTransfer) private var interaction
    @State private var width: CGFloat = 0
    let dates: [Date]

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onDrop(of: [CalendarMonthTransferInteraction.dragType],
                    delegate: CalendarPlanDayDropDelegate(dates: dates, width: width, interaction: interaction))
    }
}

private struct CalendarPlanDayDropDelegate: DropDelegate {
    let dates: [Date]
    let width: CGFloat
    let interaction: CalendarMonthTransferInteraction?

    private func date(for info: DropInfo) -> Date? {
        CalendarMonthTransferInteraction.dropDate(x: info.location.x, width: width, dates: dates)
    }

    func validateDrop(info: DropInfo) -> Bool {
        interaction?.request == nil && interaction?.draggedPlanID != nil
            && info.hasItemsConforming(to: [CalendarMonthTransferInteraction.dragType])
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info), let date = date(for: info), interaction?.hoveredDate != date else { return }
        interaction?.hoveredDate = date
        LiminalHaptics.selection()
    }

    func dropExited(info: DropInfo) {
        if let hovered = interaction?.hoveredDate, dates.contains(hovered) { interaction?.hoveredDate = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropEntered(info: info)
        return DropProposal(operation: validateDrop(info: info) && date(for: info) != nil ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let date = date(for: info), let interaction, let id = interaction.draggedPlanID,
              let provider = info.itemProviders(for: [CalendarMonthTransferInteraction.dragType]).first else { return false }
        interaction.hoveredDate = nil
        interaction.draggedPlanID = nil
        provider.loadDataRepresentation(forTypeIdentifier: CalendarMonthTransferInteraction.dragType) { data, _ in
            guard let data, String(data: data, encoding: .utf8) == id.uuidString else { return }
            Task { @MainActor in
                interaction.pendingDrop = .init(planID: id, date: date)
            }
        }
        return true
    }
}

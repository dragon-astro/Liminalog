import SwiftUI

/// 月表示と一日のまとめで使うプリセット画面。見出しの位置で「予定｜一日」を切り替え、最後に開いた方を覚える。
struct CalendarPresetSheet: View {
    @Environment(ChapterStore.self) private var store
    @AppStorage(PresetDrawerKind.storageKey) private var kindRawValue = PresetDrawerKind.plan.rawValue

    let targetDate: Date
    var allowsDateSelection = false
    var transfer: CalendarMonthTransferInteraction? = nil
    var onAppliedToDate: (Date) -> Void = { _ in }

    private var dayStart: Date {
        Calendar.japanese.startOfDay(for: targetDate)
    }

    var body: some View {
        switch kind {
        case .plan:
            MonthPlanPresetApplySheet(
                targetDate: dayStart,
                allowsDateSelection: allowsDateSelection,
                titleAccessory: AnyView(PresetKindTabs(selection: kindSelection, compact: true)),
                onAppliedToDate: onAppliedToDate
            )
            .environment(\.monthPlanTransfer, transfer)
        case .day:
            DayPresetApplySheet(
                targetDate: dayStart,
                existingPlans: store.plannedBlocks(
                    from: dayStart,
                    to: Calendar.japanese.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
                ),
                allowsDateSelection: allowsDateSelection,
                titleAccessory: AnyView(PresetKindTabs(selection: kindSelection, compact: true)),
                onAppliedToDate: onAppliedToDate
            )
            .presentationDetents([.fraction(0.65), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var kind: PresetDrawerKind {
        PresetDrawerKind(rawValue: kindRawValue) ?? .plan
    }

    private var kindSelection: Binding<PresetDrawerKind> {
        Binding { kind } set: { kindRawValue = $0.rawValue }
    }
}

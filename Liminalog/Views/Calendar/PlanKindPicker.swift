import SwiftUI

struct TimelineKindDragHint: View {
    let isMemo: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text("← メイン予定")
                .foregroundStyle(isMemo ? Color.secondary : Color.accentColor)
            Spacer(minLength: 0)
            Text("予定メモ →")
                .foregroundStyle(isMemo ? Color.accentColor : Color.secondary)
        }
        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(5).accessibilityHidden(true)
    }
}

struct PlanMemoButton: View {
    @Binding var isMemo: Bool
    var body: some View {
        Button {
            LiminalHaptics.selection()
            isMemo.toggle()
        } label: {
            Image(systemName: "rectangle.dashed")
                .font(.title3)
                .foregroundStyle(isMemo ? LiminalTheme.accent : LiminalTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(isMemo ? LiminalTheme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("予定メモ")
        .accessibilityValue(isMemo ? "オン" : "オフ")
        .accessibilityHint(isMemo ? "メイン予定に切り替え" : "予定メモに切り替え")
        .accessibilityAddTraits(isMemo ? .isSelected : [])
        .accessibilityIdentifier("plan-memo-toggle")
    }
}

struct PlanImportanceButton: View {
    @Binding var isImportant: Bool
    var body: some View {
        Button {
            isImportant.toggle()
        } label: {
            Image(systemName: isImportant ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isImportant ? LiminalTheme.reward : LiminalTheme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重要な予定")
        .accessibilityValue(isImportant ? "オン" : "オフ")
        .accessibilityIdentifier("plan-important")
    }
}

struct PlanMemoPromotionRequest: Identifiable {
    let id = UUID()
    let changes: [PlanMemoPromotionChange]
}

struct PlanMemoPromotionSheet: View {
    let request: PlanMemoPromotionRequest
    let title: String
    let start: Date
    let end: Date
    let colorHex: String?
    let icon: String?
    let apply: (PlanMemoPromotionMode) -> Void
    @State private var mode = PlanTemplateReplacementMode.keepRemainders
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(start.japaneseMonthDayShortWeekday).font(.subheadline.weight(.semibold))
                    PlanReplacementComparison(targetDate: start,
                        incoming: [.init(id: "incoming", title: title, colorHex: colorHex, icon: icon,
                            interval: .init(start: start, end: end), isIncoming: true)],
                        partial: PlanMemoPromotionMode.keepRemainders.replacement(changes: request.changes, start: start, end: end),
                        mode: $mode)
                }.padding(12)
            }
            .navigationTitle("予定を入れ替える")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { apply(mode) } label: {
                    Text(mode == .keepRemainders ? "時間だけ入れ替える" : "予定ごと入れ替える")
                        .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent).padding(.horizontal, 16).padding(.vertical, 10)
                .background(.background)
                .accessibilityIdentifier("memo-promotion-apply")
            }
        }
        .presentationBackground(LiminalTheme.plainSheetBackground)
        .presentationDetents([.fraction(0.75)])
        .presentationDragIndicator(.visible)
    }
}

import SwiftUI

enum CalendarMonthDrawerMotion {
    enum Destination: Equatable { case compact, expanded, dismissed }

    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    static func height(base: CGFloat, translation: CGFloat, compact: CGFloat, expanded: CGFloat) -> CGFloat {
        min(expanded, max(compact, base - translation))
    }

    static func offset(base: CGFloat, translation: CGFloat, compact: CGFloat) -> CGFloat {
        max(0, translation - (base - compact))
    }

    static func destination(base: CGFloat, translation: CGFloat, predicted: CGFloat,
                            compact: CGFloat, expanded: CGFloat) -> Destination {
        let projectedHeight = base - predicted
        if base - translation < compact - 80 || projectedHeight < compact - 160 {
            return .dismissed
        }
        return projectedHeight > (compact + expanded) / 2 ? .expanded : .compact
    }
}

/// Drag state stays local: the calendar only receives the settled height, not every pointer update.
struct CalendarMonthDrawerContainer<Content: View>: View {
    @Binding var isExpanded: Bool
    let compactHeight: CGFloat
    let expandedHeight: CGFloat
    let bottomInset: CGFloat
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @GestureState(resetTransaction: Transaction(animation: CalendarMonthDrawerMotion.animation))
    private var translation: CGFloat = 0

    private var baseHeight: CGFloat { isExpanded ? expandedHeight : compactHeight }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(CalendarMonthDrawerMotion.animation) { isExpanded.toggle() }
            } label: {
                Capsule()
                    .fill(LiminalTheme.secondaryText.opacity(0.5))
                    .frame(width: 48, height: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "当日の予定を小さくする" : "当日の予定を広げる")
            .accessibilityIdentifier("month-drawer-grabber")
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($translation) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let destination = CalendarMonthDrawerMotion.destination(
                            base: baseHeight, translation: value.translation.height,
                            predicted: value.predictedEndTranslation.height,
                            compact: compactHeight, expanded: expandedHeight
                        )
                        switch destination {
                        case .dismissed: onClose()
                        case .compact:
                            withAnimation(CalendarMonthDrawerMotion.animation) { isExpanded = false }
                        case .expanded:
                            withAnimation(CalendarMonthDrawerMotion.animation) { isExpanded = true }
                        }
                    }
            )
            content()
        }
        .frame(height: CalendarMonthDrawerMotion.height(
            base: baseHeight, translation: translation, compact: compactHeight, expanded: expandedHeight
        ))
        .background(LiminalTheme.plainSheetBackground, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .background(alignment: .bottom) {
            LiminalTheme.plainSheetBackground.frame(height: bottomInset + 20).offset(y: bottomInset)
        }
        .offset(y: CalendarMonthDrawerMotion.offset(base: baseHeight, translation: translation, compact: compactHeight))
    }
}

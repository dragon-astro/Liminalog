import SwiftUI

/// Shared system-sheet chrome for the preset library and the selected-day list.
enum CalendarDrawerStyle {
    static let compact: PresentationDetent = .height(264)
    static let expanded: PresentationDetent = .medium
    static let headerHeight: CGFloat = 48
    static let horizontalInset: CGFloat = 14
    static var background: Color { LiminalTheme.plainSheetBackground }
}

private struct CalendarDrawerStyleModifier: ViewModifier {
    @Binding var selection: PresentationDetent

    func body(content: Content) -> some View {
        content
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(CalendarDrawerStyle.background)
            .presentationDetents([CalendarDrawerStyle.compact, CalendarDrawerStyle.expanded], selection: $selection)
            .presentationDragIndicator(.visible)
            .presentationBackground(CalendarDrawerStyle.background)
            .presentationBackgroundInteraction(.enabled)
    }
}

extension View {
    func calendarDrawerStyle(selection: Binding<PresentationDetent>) -> some View {
        modifier(CalendarDrawerStyleModifier(selection: selection))
    }
}

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
            .background(CalendarDrawerShadow())
            .presentationDetents([CalendarDrawerStyle.compact, CalendarDrawerStyle.expanded], selection: $selection)
            .presentationDragIndicator(.visible)
            .presentationBackground(CalendarDrawerStyle.background)
            .presentationBackgroundInteraction(.enabled)
    }
}

/// Only adjust the public presented view's shadow; keep native sheet geometry and gestures.
private struct CalendarDrawerShadow: UIViewRepresentable {
    func makeUIView(context: Context) -> ShadowView { ShadowView() }
    func updateUIView(_ uiView: ShadowView, context: Context) { uiView.setNeedsLayout() }
    static func dismantleUIView(_ uiView: ShadowView, coordinator: Void) { uiView.restore() }

    final class ShadowView: UIView {
        private weak var styledView: UIView?
        private var original: (Float, CGFloat, CGSize, CGColor?)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let presented = controller.presentationController?.presentedView,
                   controller.presentingViewController != nil {
                    let layer = presented.layer
                    if styledView !== presented {
                        restore()
                        original = (layer.shadowOpacity, layer.shadowRadius, layer.shadowOffset, layer.shadowColor)
                        styledView = presented
                    }
                    layer.shadowColor = UIColor.black.cgColor
                    layer.shadowOpacity = 0.05
                    layer.shadowRadius = 14
                    layer.shadowOffset = CGSize(width: 0, height: -2)
                    return
                }
                responder = current.next
            }
        }

        func restore() {
            if let layer = styledView?.layer, let original {
                layer.shadowOpacity = original.0
                layer.shadowRadius = original.1
                layer.shadowOffset = original.2
                layer.shadowColor = original.3
            }
            styledView = nil
            original = nil
        }
    }
}

extension View {
    func calendarDrawerStyle(selection: Binding<PresentationDetent>) -> some View {
        modifier(CalendarDrawerStyleModifier(selection: selection))
    }
}

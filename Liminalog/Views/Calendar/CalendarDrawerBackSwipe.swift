import SwiftUI
import UIKit

/// Observe the presented drawer, including its empty scroll area and bottom inset.
/// A horizontal pan cancels button taps; vertical pans remain native sheet/scroll gestures.
struct CalendarDrawerBackSwipe: UIViewRepresentable {
    let isEnabled: Bool
    let onBack: () -> Void

    func makeUIView(context: Context) -> SwipeView { SwipeView() }

    func updateUIView(_ view: SwipeView, context: Context) {
        view.onBack = onBack
        if view.pan.isEnabled != isEnabled { view.pan.isEnabled = isEnabled }
        view.attachIfNeeded()
    }

    static func dismantleUIView(_ view: SwipeView, coordinator: Void) { view.detach() }

    final class SwipeView: UIView, UIGestureRecognizerDelegate {
        var onBack: (() -> Void)?
        lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delegate = self
            return pan
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attachIfNeeded() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard window != nil, pan.view == nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   controller.presentingViewController != nil,
                   let presented = controller.presentationController?.presentedView {
                    presented.addGestureRecognizer(pan)
                    return
                }
                responder = current.next
            }
        }

        func detach() { pan.view?.removeGestureRecognizer(pan) }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let delta = pan.translation(in: pan.view)
            return delta.x > 0 && delta.x > abs(delta.y) * 1.5
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Do not compete with vertical scrolling or sheet detents. A plan's
            // existing long-press recognizer retains priority over ancestor pans.
            other is UIPanGestureRecognizer
        }

        @objc private func handlePan() {
            guard pan.state == .ended else { return }
            let delta = pan.translation(in: pan.view)
            if CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: delta.x, vertical: delta.y) {
                onBack?()
            }
        }
    }
}

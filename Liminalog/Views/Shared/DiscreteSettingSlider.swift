import SwiftUI

/// One coordinate system for the thumb, stops and labels; one source of feedback.
struct DiscreteSettingSlider: View {
    @Binding var selection: Int
    let count: Int
    var labels: [String] = []
    let accessibilityTitle: String
    let accessibilityText: String
    @State private var drag: DiscreteSliderSelection?
    @State private var grabOffset: CGFloat = 0

    private let inset: CGFloat = 16
    private var position: Double { drag?.position ?? Double(selection) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let travel = max(1, geometry.size.width - inset * 2)
                let thumbX = inset + travel * position / Double(count - 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 4)
                        .padding(.horizontal, inset)
                    Capsule().fill(LiminalTheme.accent)
                        .frame(width: max(0, thumbX - inset), height: 4).offset(x: inset)
                    ForEach(0..<count, id: \.self) { index in
                        Circle().fill(index <= selection ? LiminalTheme.accent : LiminalTheme.secondaryText)
                            .frame(width: 5, height: 5)
                            .position(x: inset + travel * Double(index) / Double(count - 1), y: 22)
                    }
                    Circle().fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 0.5))
                        .frame(width: 28, height: 28)
                        .position(x: thumbX, y: 22)
                }
                .frame(height: 44)
                .overlay {
                    SliderGestureSurface { event in
                        switch event {
                        case .began(let x):
                            drag = DiscreteSliderSelection(index: selection, count: count)
                            let startX = inset + travel * Double(selection) / Double(count - 1)
                            let offset = x - startX
                            grabOffset = abs(offset) <= 14 ? offset : 0
                        case .changed(let x):
                            update(x: x, travel: travel, finishing: false)
                        case .ended(let x):
                            update(x: x, travel: travel, finishing: true)
                            withAnimation(.easeOut(duration: 0.12)) { drag = nil }
                        case .cancelled:
                            drag = nil
                        case .tapped(let x):
                            drag = DiscreteSliderSelection(index: selection, count: count)
                            grabOffset = 0
                            update(x: x, travel: travel, finishing: true)
                            drag = nil
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(height: 44)
            if !labels.isEmpty {
                SliderStopLabels(inset: inset) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption2.weight(index == selection ? .bold : .medium))
                            .foregroundStyle(index == selection ? LiminalTheme.accent : LiminalTheme.secondaryText)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(min(count - 1, selection + 1))
            case .decrement: commit(max(0, selection - 1))
            @unknown default: break
            }
        }
        .onDisappear { drag = nil }
    }

    private func update(x: CGFloat, travel: CGFloat, finishing: Bool) {
        guard var session = drag else { return }
        let next = session.update(position: Double((x - inset - grabOffset) / travel) * Double(count - 1), finishing: finishing)
        drag = session
        commit(next)
    }

    private func commit(_ index: Int) {
        guard selection != index else { return }
        selection = index
        LiminalHaptics.selection()
    }
}

/// A vertical pan belongs to the surrounding Form, including one starting on the track.
private struct SliderGestureSurface: UIViewRepresentable {
    enum Event {
        case began(CGFloat), changed(CGFloat), ended(CGFloat), tapped(CGFloat), cancelled
    }
    let onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.onEvent = onEvent }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onEvent: (Event) -> Void
        private var touchStartX: CGFloat = 0
        init(onEvent: @escaping (Event) -> Void) { self.onEvent = onEvent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer is UIPanGestureRecognizer {
                touchStartX = touch.location(in: gestureRecognizer.view).x
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let x = gesture.location(in: gesture.view).x
            switch gesture.state {
            case .began:
                onEvent(.began(touchStartX))
                onEvent(.changed(x))
            case .changed: onEvent(.changed(x))
            case .ended: onEvent(.ended(x))
            case .cancelled, .failed: onEvent(.cancelled)
            default: break
            }
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { onEvent(.tapped(gesture.location(in: gesture.view).x)) }
        }
    }
}

private struct SliderStopLabels: Layout {
    let inset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 200, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let stop = inset + (bounds.width - 2 * inset) * CGFloat(index) / CGFloat(max(1, subviews.count - 1))
            let x = min(bounds.width - size.width / 2, max(size.width / 2, stop))
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(size))
        }
    }
}

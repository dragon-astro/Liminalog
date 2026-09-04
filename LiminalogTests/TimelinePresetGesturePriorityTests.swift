import UIKit
import Testing
@testable import Liminalog

@MainActor
struct TimelinePresetGesturePriorityTests {
    @Test func holdingHasPriorityOverAncestorScrollAndTap() {
        let parent = UIScrollView()
        let surface = UIView()
        parent.addSubview(surface)
        let drag = TimelinePresetLongPressRecognizer()
        surface.addGestureRecognizer(drag)
        let tap = UITapGestureRecognizer()
        parent.addGestureRecognizer(tap)
        #expect(TimelinePlanPresetLongPressDragSurface.Coordinator.hasPriority(over: parent.panGestureRecognizer, drag: drag))
        #expect(TimelinePlanPresetLongPressDragSurface.Coordinator.hasPriority(over: tap, drag: drag))
    }

    @Test func unrelatedScrollAndDisabledDragAreNotBlocked() {
        let parent = UIScrollView()
        let surface = UIView()
        parent.addSubview(surface)
        let drag = TimelinePresetLongPressRecognizer()
        surface.addGestureRecognizer(drag)
        let unrelated = UIScrollView()
        #expect(!TimelinePlanPresetLongPressDragSurface.Coordinator.hasPriority(over: unrelated.panGestureRecognizer, drag: drag))
        drag.isEnabled = false
        #expect(!TimelinePlanPresetLongPressDragSurface.Coordinator.hasPriority(over: parent.panGestureRecognizer, drag: drag))
    }

    @Test func delegateMakesParentWaitForHoldFailure() {
        let parent = UIScrollView()
        let surface = UIView()
        parent.addSubview(surface)
        let drag = TimelinePresetLongPressRecognizer()
        surface.addGestureRecognizer(drag)
        let coordinator = TimelinePlanPresetLongPressDragSurface.Coordinator(
            onEvent: { _ in }, onTap: nil, onSwipeRight: nil, onSwipeLeft: nil)
        coordinator.recognizer = drag
        #expect(coordinator.gestureRecognizer(drag, shouldBeRequiredToFailBy: parent.panGestureRecognizer))
        #expect(!coordinator.gestureRecognizer(parent.panGestureRecognizer, shouldBeRequiredToFailBy: drag))
    }
}

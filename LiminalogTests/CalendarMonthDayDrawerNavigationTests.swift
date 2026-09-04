import Foundation
import CoreGraphics
import Testing
@testable import Liminalog

struct CalendarMonthDayDrawerNavigationTests {
    @MainActor
    @Test func rowSwipeDoesNotBecomeTap() {
        let origin = CGPoint(x: 200, y: 700)
        #expect(TimelinePlanPresetLongPressDragSurface.Coordinator.isTap(from: origin, to: CGPoint(x: 204, y: 703)))
        #expect(!TimelinePlanPresetLongPressDragSurface.Coordinator.isTap(from: origin, to: CGPoint(x: 80, y: 700)))
        #expect(!TimelinePlanPresetLongPressDragSurface.Coordinator.isTap(from: origin, to: CGPoint(x: 200, y: 650)))
    }
    @Test func rightSwipeReturnsToList() {
        #expect(CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: 100, vertical: 10))
    }
    @Test func shortOrLeftSwipeDoesNotNavigate() {
        #expect(!CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: 40, vertical: 0))
        #expect(!CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: -100, vertical: 0))
    }
    @Test func verticalScrollOrSheetDragDoesNotNavigate() {
        #expect(!CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: 80, vertical: 120))
        #expect(!CalendarMonthDayDrawerNavigation.shouldReturnToList(horizontal: 80, vertical: -120))
    }
}

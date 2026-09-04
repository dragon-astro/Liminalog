import Foundation
import Testing
@testable import Liminalog

struct CalendarMonthDayDrawerNavigationTests {
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

import XCTest

@MainActor
final class CalendarMonthDrawerUITests: XCTestCase {
    private let sourceID = "00000000-0000-0000-0000-000000000101"
    private var fixtureDay: Date {
        let cal = Calendar.current
        let month = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return cal.date(byAdding: .day, value: 9, to: cal.date(byAdding: .month, value: 1, to: month)!)!
    }
    private func dayID(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func launch(longNote: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogMonthDrawerUITests", "-LiminalogInitialRootTab", "calendar",
                               "-LiminalogInitialCalendarMode", "month", "-calendar.filter.usesCustomCategories", "NO"]
        if longNote { app.launchArguments.append("-LiminalogUITestLongNote") }
        app.launch()
        let day = element(app, "calendar-month-day-\(dayID(fixtureDay))")
        XCTAssertTrue(day.waitForExistence(timeout: 30), app.debugDescription)
        day.tap()
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").waitForExistence(timeout: 5))
        return app
    }
    private func assertMoved(_ app: XCUIApplication, to day: Date) {
        // SwiftUI propagates the outer drawer identifier onto the header text.
        // Match its semantic day value instead of depending on that inherited identifier.
        let header = app.staticTexts.matching(NSPredicate(format: "value == %@", dayID(day))).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongPressFromListMovesToAnotherDay() {
        let app = launch()
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        let source = element(app, "calendar-drawer-plan-\(sourceID)")
        let target = element(app, "calendar-month-day-\(dayID(destination))")
        // Production threshold is 0.28 seconds; no immediate-drag debug flag is used.
        source.press(forDuration: 0.7, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertMoved(app, to: destination)
    }

    func testLongPressFromDetailMovesToAnotherDay() {
        let app = launch()
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        element(app, "calendar-drawer-plan-\(sourceID)").press(forDuration: 0.7,
            thenDragTo: element(app, "calendar-month-day-\(dayID(destination))"),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        assertMoved(app, to: destination)
    }

    func testSwipeOnlyRevealsDeleteAndCancelKeepsPlan() {
        let app = launch()
        let source = element(app, "calendar-drawer-plan-\(sourceID)")
        let delete = element(app, "calendar-drawer-delete-\(sourceID)")
        XCTAssertFalse(delete.isHittable)
        source.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertTrue(delete.isHittable)
        XCTAssertFalse(element(app, "calendar-drawer-edit").exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        delete.tap()
        let alert = app.alerts["予定を削除しますか？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["キャンセル"].tap()
        XCTAssertTrue(source.exists)
    }

    func testLongNoteScrollRevealsAllEditorButtonsTogether() {
        let app = launch(longNote: true)
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        let scroll = app.scrollViews.matching(identifier: "calendar-month-day-drawer").firstMatch
        let copy = element(app, "calendar-drawer-copy")
        for _ in 0..<8 {
            if copy.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(element(app, "calendar-drawer-edit").isHittable)
        XCTAssertTrue(copy.isHittable)
        XCTAssertTrue(element(app, "calendar-drawer-move").isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

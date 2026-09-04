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
    private func launch(longNote: Bool = false, previewSource: Bool = false, measureDrop: Bool = false, overlap: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogMonthDrawerUITests", "-LiminalogInitialRootTab", "calendar",
                               "-LiminalogInitialCalendarMode", "month", "-calendar.filter.usesCustomCategories", "NO"]
        if longNote { app.launchArguments.append("-LiminalogUITestLongNote") }
        if previewSource { app.launchArguments.append("-LiminalogUITestPreviewSource") }
        if measureDrop { app.launchArguments.append("-LiminalogMeasureMonthDrop") }
        if overlap { app.launchArguments.append("-LiminalogUITestDropOverlap") }
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
        // Use the production threshold, without an immediate-drag debug flag.
        source.press(forDuration: 0.7, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertMoved(app, to: destination)
    }

    func testDropLatencyMetric() {
        for sample in 1...3 {
            let app = launch(measureDrop: true)
            let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
            element(app, "calendar-drawer-plan-\(sourceID)").press(forDuration: 0.4,
                thenDragTo: element(app, "calendar-month-day-\(dayID(destination))"),
                withVelocity: .slow, thenHoldForDuration: 0)
            assertMoved(app, to: destination)
            let value = element(app, "calendar-drawer-plan-\(sourceID)").value as? String ?? "missing"
            print("MONTH_DROP_SAMPLE \(sample) \(value)")
            let attachment = XCTAttachment(string: value)
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(value.contains("|commit:"))
            XCTAssertTrue(value.contains("|dismiss:0"), value)
        }
    }

    func testDropOutsideCalendarRestoresWithoutDismissing() {
        let app = launch(measureDrop: true)
        let row = element(app, "calendar-drawer-plan-\(sourceID)")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // The original drawer position exposes another day once it retreats.
        // Use the top of the app, above the calendar viewport, as a real outside drop.
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.4, thenDragTo: outside,
                    withVelocity: .slow, thenHoldForDuration: 0)
        assertMoved(app, to: fixtureDay)
        let value = row.value as? String ?? ""
        XCTAssertTrue(value.contains("recognizedHolds:1|commit:-1.0"), value)
        XCTAssertTrue(value.contains("|dismiss:0"), value)
    }

    func testOverlappingDropCancelRestoresSource() {
        assertOverlappingDrop(approve: false)
    }

    func testOverlappingDropConfirmRestoresDestination() {
        assertOverlappingDrop(approve: true)
    }

    private func assertOverlappingDrop(approve: Bool) {
        let app = launch(measureDrop: true, overlap: true)
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        element(app, "calendar-drawer-plan-\(sourceID)").press(forDuration: 0.4,
            thenDragTo: element(app, "calendar-month-day-\(dayID(destination))"),
            withVelocity: .slow, thenHoldForDuration: 0)
        let alert = app.alerts["重なる予定を置換しますか？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        alert.buttons[approve ? "置換して移動" : "キャンセル"].tap()
        assertMoved(app, to: approve ? destination : fixtureDay)
        XCTAssertTrue((element(app, "calendar-drawer-plan-\(sourceID)").value as? String ?? "").contains("|dismiss:1"))
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

    func testPreviewSourcePlanCanBeGrabbed() {
        let app = launch(previewSource: true)
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        element(app, "calendar-drawer-plan-\(sourceID)").press(forDuration: 0.3,
            thenDragTo: element(app, "calendar-month-day-\(dayID(destination))"),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        assertMoved(app, to: destination)
    }

    func testDetailKeepsDrawerHeight() {
        let app = launch()
        let header = app.staticTexts.matching(NSPredicate(format: "value == %@", dayID(fixtureDay))).firstMatch
        let originalY = header.frame.minY
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
        app.buttons["当日の予定一覧に戻る"].tap()
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
    }

    func testHoldSurvivesMovementBeforeRecognition() {
        let app = launch()
        let row = element(app, "calendar-drawer-plan-\(sourceID)")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Move 18pt before the recognition deadline, then keep holding there.
        // This is deliberately not the previous perfectly stationary 0.7s hold.
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 18, dy: 0)),
                    withVelocity: XCUIGestureVelocity(rawValue: 200), thenHoldForDuration: 0.4)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "recognizedHolds:1")
    }

    func testImmediateVerticalSwipeDoesNotGrabPlan() {
        let app = launch()
        let row = element(app, "calendar-drawer-plan-\(sourceID)")
        let originalY = row.frame.minY
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -160)),
                    withVelocity: XCUIGestureVelocity(rawValue: 800), thenHoldForDuration: 0)
        let anotherRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "calendar-drawer-plan-")).firstMatch
        XCTAssertEqual(anotherRow.value as? String, "recognizedHolds:0")
        XCTAssertFalse(element(app, "calendar-drawer-edit").exists)
        XCTAssertTrue(!row.isHittable || abs(row.frame.minY - originalY) > 20)
    }

    func testLongPressOnListIconMovesToAnotherDay() {
        assertCoordinateHoldMoves(dx: 0.04, dy: 0.5)
    }

    func testLongPressOnListTitleMovesToAnotherDay() {
        assertCoordinateHoldMoves(dx: 0.3, dy: 0.2)
    }

    func testLongPressOnListBottomPaddingMovesToAnotherDay() {
        assertCoordinateHoldMoves(dx: 0.5, dy: 0.96)
    }

    func testLongPressOnListTopPaddingMovesToAnotherDay() {
        assertCoordinateHoldMoves(dx: 0.5, dy: 0.04)
    }

    private func assertCoordinateHoldMoves(dx: CGFloat, dy: CGFloat) {
        let app = launch()
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        let source = element(app, "calendar-drawer-plan-\(sourceID)").coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
        let target = element(app, "calendar-month-day-\(dayID(destination))").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 0.7, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
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
        func fullyVisible(_ element: XCUIElement) -> Bool {
            let viewport = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 24)
            return element.isHittable && viewport.contains(element.frame)
        }
        for _ in 0..<12 {
            if fullyVisible(copy) { break }
            // A compact sheet reaches the home-indicator area. XCTest's default
            // swipe starts there on iPhone 16; keep both endpoints inside content.
            let visible = scroll.frame.intersection(app.frame)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: visible.maxY - 64))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: visible.minY + 32))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(fullyVisible(element(app, "calendar-drawer-edit")))
        XCTAssertTrue(fullyVisible(copy))
        XCTAssertTrue(fullyVisible(element(app, "calendar-drawer-move")))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

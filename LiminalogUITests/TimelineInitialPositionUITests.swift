import XCTest

@MainActor
final class TimelineInitialPositionUITests: XCTestCase {
    private func launch(tab: String, mode: String = "week") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogMonthDrawerUITests", "-LiminalogUITestInitialTimeline",
            "-LiminalogInitialRootTab", tab, "-LiminalogInitialCalendarMode", mode,
            "-home.tomorrowPlanMode", "timeline", "-calendar.filter.usesCustomCategories", "NO",
            "-timeline.day.hourScale", "1", "-timeline.week.hourScale", "1"]
        app.launch()
        return app
    }

    private func visibleTimeline(_ app: XCUIApplication, id: String) -> XCUIElement {
        let query = app.scrollViews.matching(identifier: id)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        return query.allElementsBoundByIndex.first { $0.isHittable } ?? query.firstMatch
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTomorrowOpensAtSevenAndRetainsUserScroll() {
        let app = launch(tab: "today")
        let tomorrow = app.buttons["明日の予定"].firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 30), app.debugDescription)
        tomorrow.tap()
        let timeline = visibleTimeline(app, id: "day-timeline")
        let morning = app.buttons["day-plan-00000000-0000-0000-0000-000000000702"]
        XCTAssertTrue(morning.waitForExistence(timeout: 10))
        screenshot(app, name: "明日の初期位置")
        XCTAssertTrue(morning.isHittable)
        XCTAssertEqual(morning.frame.minY, timeline.frame.minY, accuracy: 35)
        // Scroll along the time labels, where ordinary scrolling cannot edit a plan.
        let origin = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
        origin.press(forDuration: 0.01, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.4)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let scrolledY = morning.frame.minY
        XCTAssertLessThan(scrolledY, timeline.frame.minY - 60)
        app.buttons["今日の記録"].firstMatch.tap()
        app.buttons["明日の予定"].firstMatch.tap()
        let restored = visibleTimeline(app, id: "day-timeline")
        XCTAssertLessThan(morning.frame.minY, restored.frame.minY - 60)
        screenshot(app, name: "明日のスクロール位置を保持")
    }
    func testWeekStartsAtSevenAndDaySwitchKeepsUserPosition() {
        let app = launch(tab: "calendar")
        let timeline = visibleTimeline(app, id: "week-timeline")
        let morning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'UITest 朝の予定、'")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(morning, app.debugDescription)
        screenshot(app, name: "週間の初期位置")
        XCTAssertEqual(morning?.frame.minY ?? -1000, timeline.frame.minY, accuracy: 35)
        let origin = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.41))
        origin.press(forDuration: 0.01, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(morning?.frame.minY ?? -1000, timeline.frame.minY + 60)
        app.buttons["calendar-period-button"].tap()
        app.buttons["日間"].tap()
        _ = visibleTimeline(app, id: "day-timeline")
        app.buttons["calendar-period-button"].tap()
        app.buttons["週間"].tap()
        let returned = visibleTimeline(app, id: "week-timeline")
        XCTAssertGreaterThan(morning?.frame.minY ?? -1000, returned.frame.minY + 60)
        screenshot(app, name: "日間から週間へ戻っても位置を保持")
    }

}

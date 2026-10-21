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
    private func launch(longNote: Bool = false, previewSource: Bool = false, measureDrop: Bool = false, overlap: Bool = false, templateReplacement: Bool = false, expandedMode: String? = "summary", measureExpansion: Bool = false, planMemos: Bool = false, contentSize: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogMonthDrawerUITests", "-LiminalogInitialRootTab", "calendar",
                               "-LiminalogInitialCalendarMode", "month", "-calendar.filter.usesCustomCategories", "NO"]
        if planMemos { app.launchArguments.append("-LiminalogUITestPlanMemos") }
        if longNote { app.launchArguments.append("-LiminalogUITestLongNote") }
        if previewSource { app.launchArguments.append("-LiminalogUITestPreviewSource") }
        if measureDrop { app.launchArguments.append("-LiminalogMeasureMonthDrop") }
        if measureExpansion { app.launchArguments.append("-LiminalogMeasureDayExpansion") }
        if overlap { app.launchArguments.append("-LiminalogUITestDropOverlap") }
        if templateReplacement { app.launchArguments.append("-LiminalogUITestTemplateReplacement") }
        if let expandedMode { app.launchArguments += ["-calendar.month.expandedDayMode", expandedMode] }
        app.launchArguments += ["-timeline.day.hourScale", "1"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.terminate()
        app.launch()
        let day = element(app, "calendar-month-day-\(dayID(fixtureDay))")
        XCTAssertTrue(day.waitForExistence(timeout: 30), app.debugDescription)
        day.tap()
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").waitForExistence(timeout: 5))
        return app
    }
    private func openEditor(_ app: XCUIApplication, planID: String) {
        element(app, "calendar-drawer-plan-\(planID)").tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        app.buttons["calendar-drawer-edit"].tap()
        XCTAssertTrue(app.segmentedControls["plan-kind-picker"].waitForExistence(timeout: 5))
    }

    private func dragAcrossDay(_ app: XCUIApplication, plan: XCUIElement, fraction: CGFloat) {
        let timelines = app.scrollViews.matching(identifier: "day-timeline")
        let timeline = timelines.allElementsBoundByIndex.first { $0.isHittable } ?? timelines.firstMatch
        let origin = plan.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: timeline.frame.minX + timeline.frame.width * fraction, dy: plan.frame.midY))
        origin.press(forDuration: 0.05, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func testUnselectedTimelineLongPressAddsMemoWithoutDeletingMain() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let main = element(app, "day-plan-\(sourceID)")
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        let before = main.label
        let all = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-plan-'"))
        let count = all.count
        let press = main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        press.press(forDuration: 0.8, thenDragTo: press.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(all.count, count + 1, app.debugDescription)
        XCTAssertEqual(main.label, before)
        XCTAssertEqual(main.value as? String, "メイン予定")
        XCTAssertFalse(app.buttons["削除"].exists)
        let newMemo = all.matching(NSPredicate(format: "value == '予定メモ' AND label BEGINSWITH '仕事、'")).firstMatch
        XCTAssertTrue(newMemo.exists, app.debugDescription)
        XCTAssertLessThanOrEqual(abs(planMinutes(newMemo.label)[0] - 600), 5, newMemo.label)
        XCTAssertGreaterThan(planMinutes(newMemo.label)[1], 600, newMemo.label)
        XCTAssertLessThanOrEqual(newMemo.frame.maxX, visibleDayTimeline(app).frame.maxX + 1)
        keepScreenshot(app, name: "未選択予定の長押しでメモを重ねて追加")
        let start = planMinutes(newMemo.label)[0]
        let origin = newMemo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(planMinutes(newMemo.label)[0], start)
        XCTAssertLessThanOrEqual(planMinutes(newMemo.label)[0] - start, 120, newMemo.label)
        XCTAssertEqual(main.label, before)
        newMemo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["削除"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(newMemo.exists)
    }

    func testLongPressMemoExtendsUpFromAnchorAndShortMemoHasMinimumHeight() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let main = element(app, "day-plan-\(sourceID)")
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        let before = main.label
        let press = main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        press.press(forDuration: 0.8, thenDragTo: press.withOffset(CGVector(dx: 0, dy: -38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let memos = app.buttons.matching(NSPredicate(format: "value == '予定メモ' AND label BEGINSWITH '仕事、'"))
        XCTAssertTrue(memos.firstMatch.waitForExistence(timeout: 5))
        let stretched = planMinutes(memos.firstMatch.label)
        XCTAssertLessThan(stretched[0], 600)
        XCTAssertLessThanOrEqual(abs(stretched[1] - 600), 5, memos.firstMatch.label)
        XCTAssertEqual(main.label, before)
        keepScreenshot(app, name: "長押しした時刻を終点に上へ伸ばす")
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.8)
        XCTAssertEqual(memos.count, 2)
        let short = memos.allElementsBoundByIndex.first { item in
            let times = planMinutes(item.label)
            return times.count == 2 && times[1] - times[0] <= 15
        }
        XCTAssertNotNil(short, app.debugDescription)
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertGreaterThanOrEqual(short?.frame.height ?? 0, 17.5)
        XCTAssertEqual(main.label, before)
        keepScreenshot(app, name: "短いメモも共通の時間軸で最小の高さを確保")
    }

    func testPromotionCanReplaceOnlyOverlappingTime() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let memo = element(app, "day-plan-00000000-0000-0000-0000-000000000102")
        XCTAssertTrue(memo.waitForExistence(timeout: 10))
        memo.tap(); dragAcrossDay(app, plan: memo, fraction: 0.25)
        let option = app.buttons["replacement-option-keepRemainders"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertTrue(option.isSelected)
        XCTAssertFalse(app.buttons["メモに残す"].exists)
        XCTAssertTrue(element(app, "replacement-comparison").exists)
        keepScreenshot(app, name: "重なる時間だけを入れ替える結果")
        app.buttons["memo-promotion-apply"].tap()
        XCTAssertEqual(memo.value as? String, "メイン予定")
        let mains = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-plan-' AND label BEGINSWITH '仕事、' AND value == 'メイン予定'"))
        XCTAssertEqual(mains.count, 2, app.debugDescription)
        let times = mains.allElementsBoundByIndex.map { planMinutes($0.label) }.sorted { $0[0] < $1[0] }
        XCTAssertEqual(times, [[540, 570], [630, 660]])
        XCTAssertTrue(element(app, "day-plan-00000000-0000-0000-0000-000000000103").exists)
        keepScreenshot(app, name: "元の予定の前後を残して保存")
    }

    func testPromotionCanReplaceWholeMainFromEditor() {
        let app = launch(planMemos: true)
        let memoID = "00000000-0000-0000-0000-000000000102"
        openEditor(app, planID: memoID)
        app.segmentedControls["plan-kind-picker"].buttons["メイン予定"].tap()
        app.buttons["保存"].tap()
        let whole = app.buttons["replacement-option-replaceWholePlans"]
        XCTAssertTrue(whole.waitForExistence(timeout: 5))
        whole.tap()
        keepScreenshot(app, name: "重なる予定ごとの入れ替え結果")
        app.buttons["memo-promotion-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 8))
        app.buttons["当日の予定一覧に戻る"].tap()
        XCTAssertFalse(element(app, "calendar-drawer-plan-\(sourceID)").exists)
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(memoID)").exists)
        XCTAssertTrue(element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000103").exists)
    }

    func testTimelineHorizontalDragSwitchesKindWithoutMovingOtherPlans() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let main = element(app, "day-plan-\(sourceID)")
        let memo = element(app, "day-plan-00000000-0000-0000-0000-000000000102")
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        let memoLabel = memo.label
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        dragAcrossDay(app, plan: main, fraction: 0.9)
        XCTAssertEqual(main.value as? String, "予定メモ", app.debugDescription)
        XCTAssertEqual(memo.label, memoLabel)
        keepScreenshot(app, name: "右へ動かして予定メモに切り替え")
        dragAcrossDay(app, plan: main, fraction: 0.25)
        XCTAssertEqual(main.value as? String, "メイン予定", app.debugDescription)
        XCTAssertEqual(memo.label, memoLabel)
        keepScreenshot(app, name: "左へ戻してメイン予定に切り替え")
    }

    func testTimelinePromotionDropConfirmsAndCancelRestoresOriginal() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let main = element(app, "day-plan-\(sourceID)")
        let memo = element(app, "day-plan-00000000-0000-0000-0000-000000000102")
        XCTAssertTrue(memo.waitForExistence(timeout: 10))
        memo.tap()
        dragAcrossDay(app, plan: memo, fraction: 0.25)
        XCTAssertTrue(app.buttons["memo-promotion-apply"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "ドラッグでメインへ移すときに実際の予定で確認")
        app.buttons["キャンセル"].tap()
        XCTAssertEqual(memo.value as? String, "予定メモ")
        XCTAssertEqual(main.value as? String, "メイン予定")
        dragAcrossDay(app, plan: memo, fraction: 0.25)
        XCTAssertTrue(app.buttons["memo-promotion-apply"].waitForExistence(timeout: 5))
        app.buttons["memo-promotion-apply"].tap()
        XCTAssertEqual(memo.value as? String, "メイン予定")
        XCTAssertEqual(main.value as? String, "メイン予定")
        XCTAssertEqual(planMinutes(main.label), [540, 570])
    }

    private func openFixtureWeek(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "週間")
        let timelines = app.scrollViews.matching(identifier: "week-timeline")
        XCTAssertTrue(timelines.firstMatch.waitForExistence(timeout: 8))
        (timelines.allElementsBoundByIndex.first { $0.isHittable } ?? timelines.firstMatch).swipeLeft()
        let main = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '仕事、'")).firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(main.isHittable)
        return main
    }

    func testWeeklyHorizontalDragKeepsMainWithinSameDate() {
        let app = launch(planMemos: true)
        let main = openFixtureWeek(app)
        let original = main.frame, label = main.label
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let origin = main.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: original.minX + original.width * 0.9, dy: original.midY))
        origin.press(forDuration: 0.05, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(main.value as? String, "メイン予定")
        XCTAssertEqual(main.label, label)
        XCTAssertEqual(main.frame.minX, original.minX, accuracy: 1)
        XCTAssertEqual(main.frame.width, original.width, accuracy: 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "value == '予定メモ'")).firstMatch.exists)
        keepScreenshot(app, name: "週間の左右移動ではメインのまま")
    }

    func testWeeklyMainDragMovesToNextDayWithoutChangingKind() {
        let app = launch(planMemos: true)
        let main = openFixtureWeek(app)
        let frame = main.frame, times = planMinutes(main.label)
        main.tap()
        let origin = main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.width + 4, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let moved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '仕事、'")).firstMatch
        XCTAssertEqual(moved.value as? String, "メイン予定")
        XCTAssertEqual(planMinutes(moved.label), times)
        XCTAssertEqual(moved.frame.minX, frame.minX + frame.width + 4, accuracy: 2)
        switchCalendarMode(app, "月間")
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        element(app, "calendar-month-day-\(dayID(destination))").tap()
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testWeeklyMainDragUsesOriginalTimeForEveryPreviewFrame() {
        let app = launch(planMemos: true)
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "週間")
        let timelines = app.scrollViews.matching(identifier: "week-timeline")
        XCTAssertTrue(timelines.firstMatch.waitForExistence(timeout: 8))
        (timelines.allElementsBoundByIndex.first { $0.isHittable } ?? timelines.firstMatch).swipeLeft()
        let mains = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '仕事、' AND value == 'メイン予定'"))
        XCTAssertTrue(mains.firstMatch.waitForExistence(timeout: 5))
        let main = mains.allElementsBoundByIndex.first { $0.isHittable } ?? mains.firstMatch
        let before = planMinutes(main.label)
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let origin = main.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let after = planMinutes(main.label)
        XCTAssertEqual(after.count, 2)
        XCTAssertGreaterThan(after[0], before[0])
        XCTAssertLessThanOrEqual(after[0] - before[0], 120, main.label)
        XCTAssertEqual(after[1] - after[0], before[1] - before[0])
        XCTAssertEqual(main.value as? String, "メイン予定")
        keepScreenshot(app, name: "週間メイン予定は指の移動量だけ時間が動く")
    }

    func testWeeklyLongPressSelectsMainWithoutCreatingMemo() {
        let app = launch(planMemos: true)
        let main = openFixtureWeek(app)
        let before = planMinutes(main.label)
        let press = main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        press.press(forDuration: 0.8, thenDragTo: press.withOffset(CGVector(dx: 0, dy: 20)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-'")).count, 1)
        XCTAssertEqual(main.value as? String, "メイン予定")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "value == '予定メモ'")).firstMatch.exists)
        // The long press selects the existing block; the next drag moves it normally.
        let move = main.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        move.press(forDuration: 0.05, thenDragTo: move.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(planMinutes(main.label)[0], before[0])
        XCTAssertEqual(planMinutes(main.label)[1] - planMinutes(main.label)[0], before[1] - before[0])
        keepScreenshot(app, name: "週間の予定上の長押しは選択")
    }

    func testWeeklyEmptyLongPressCreatesMainEvenOnRightSide() {
        let app = launch(planMemos: true)
        let main = openFixtureWeek(app)
        app.buttons["仕事を選択"].tap()
        let original = main.label
        let press = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: main.frame.minX + main.frame.width * 0.85, dy: main.frame.maxY + 70))
        press.press(forDuration: 0.5, thenDragTo: press.withOffset(CGVector(dx: 0, dy: -20)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let plans = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-'"))
        XCTAssertEqual(plans.count, 2, app.debugDescription)
        XCTAssertTrue(plans.allElementsBoundByIndex.allSatisfy { $0.value as? String == "メイン予定" })
        XCTAssertEqual(main.label, original)
        keepScreenshot(app, name: "週間の空き時間は右側でもメイン予定を作成")
    }

    func testEditorPrioritizesTimeAndStoresCustomReminder() {
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        XCTAssertLessThan(app.staticTexts["開始"].firstMatch.frame.minY, app.segmentedControls["plan-kind-picker"].frame.minY)
        let important = app.buttons["plan-important"]
        XCTAssertTrue(important.exists)
        for _ in 0..<3 where !important.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        important.tap()
        XCTAssertEqual(important.value as? String, "オン")
        XCTAssertLessThan(important.frame.minY, app.staticTexts["開始"].firstMatch.frame.minY)
        keepScreenshot(app, name: "予定名の横の星ボタンと時間、シンプルな種類切替")
        let reminder = app.buttons["plan-reminder-picker"]
        for _ in 0..<4 where !reminder.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        reminder.tap(); app.buttons["数日・数週間前"].tap(); app.buttons["2週間前"].tap()
        XCTAssertTrue(reminder.label.contains("2週間前") || app.staticTexts["2週間前"].exists)
        reminder.tap(); app.buttons["日時を指定…"].tap()
        XCTAssertTrue(element(app, "plan-reminder-date").waitForExistence(timeout: 5))
        app.scrollViews["plan-editor-scroll"].swipeUp()
        keepScreenshot(app, name: "通知プリセットと任意日時の指定")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        app.buttons["calendar-drawer-edit"].tap()
        let fixedDate = element(app, "plan-reminder-date")
        XCTAssertTrue(fixedDate.waitForExistence(timeout: 5))
        for _ in 0..<4 where !fixedDate.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        XCTAssertTrue(fixedDate.isHittable)
        let visibility = app.switches["友達に見せる"]
        for _ in 0..<4 where !visibility.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        XCTAssertTrue(visibility.isHittable, app.debugDescription)
        XCTAssertFalse(element(app, "plan-editor-options").exists)
        keepScreenshot(app, name: "公開範囲とメモを直接表示")
        app.buttons["キャンセル"].tap()
    }

    func testExpandedDrawerMainCreationOwnsDragAndNormalScrollingStillWorks() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let main = element(app, "day-plan-\(sourceID)")
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        let before = main.label
        let timeline = visibleDayTimeline(app)
        let top = app.buttons["calendar-expanded-day-back"].frame.minY
        let all = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-plan-'"))
        let count = all.count
        let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: timeline.frame.minX + timeline.frame.width * 0.25,
            dy: main.frame.maxY + 14))
        origin.press(forDuration: 0.6, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 32)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(all.count, count + 1, app.debugDescription)
        XCTAssertEqual(main.label, before)
        XCTAssertEqual(app.buttons["calendar-expanded-day-back"].frame.minY, top, accuracy: 2)
        let newMain = all.allElementsBoundByIndex.first { $0.identifier != main.identifier && $0.value as? String == "メイン予定" }
        XCTAssertNotNil(newMain)
        keepScreenshot(app, name: "ドロワーを動かさず空き時間へメイン予定を作成")
        // A normal swipe starts moving before the hold threshold and still scrolls.
        let previousY = main.frame.minY
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.7))
            .press(forDuration: 0.01, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.35)),
                withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertLessThan(main.frame.minY, previousY - 20)
        XCTAssertTrue(app.buttons["calendar-expanded-day-back"].isHittable)
    }

    func testTimelinePresetDropsChooseMainAndMemoAndKeepFixedTimes() {
        let app = launch(templateReplacement: true, expandedMode: "timeline")
        openPresetDay(app, offset: 1)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let timeline = visibleDayTimeline(app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        for (name, fraction) in [("読書", 0.88), ("読書", 0.24), ("休憩", 0.88)] {
            openPresets(app, entry: "timeline-open-presets", kind: "plan")
            let labels = app.staticTexts.matching(identifier: name)
            XCTAssertTrue(labels.firstMatch.waitForExistence(timeout: 5))
            let label = labels.allElementsBoundByIndex.first { $0.isHittable } ?? labels.firstMatch
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: timeline.frame.minX + timeline.frame.width * fraction,
                dy: timeline.frame.minY + timeline.frame.height * 0.4))
            label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(app.buttons["予定プリセットを閉じる"].waitForExistence(timeout: 5))
            app.buttons["予定プリセットを閉じる"].tap()
        }
        let reading = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-plan-' AND label BEGINSWITH '読書、'"))
        XCTAssertEqual(reading.count, 2, app.debugDescription)
        XCTAssertEqual(Set(reading.allElementsBoundByIndex.compactMap { $0.value as? String }), Set(["メイン予定", "予定メモ"]))
        for plan in reading.allElementsBoundByIndex { let times = planMinutes(plan.label); XCTAssertEqual(times[1] - times[0], 60) }
        let rest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-plan-' AND label BEGINSWITH '休憩、'" )).firstMatch
        XCTAssertEqual(rest.value as? String, "予定メモ")
        XCTAssertEqual(planMinutes(rest.label), [600, 660])
        keepScreenshot(app, name: "プリセットも左でメイン右でメモに配置")
    }

    func testWeeklyPresetDropsStayMainOnBothSidesOfDay() {
        let app = launch(templateReplacement: true, planMemos: true)
        let main = openFixtureWeek(app)
        let frame = main.frame
        for (offset, fraction) in [0.15, 0.85].enumerated() {
            openPresets(app, entry: "calendar-open-presets", kind: "plan")
            let labels = app.staticTexts.matching(identifier: "休憩")
            XCTAssertTrue(labels.firstMatch.waitForExistence(timeout: 5))
            let label = labels.allElementsBoundByIndex.last { $0.isHittable } ?? labels.firstMatch
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: frame.minX + CGFloat(offset) * (frame.width + 4) + frame.width * fraction, dy: frame.midY))
            label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
            if offset == 0 {
                XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 8), app.debugDescription)
                app.buttons["replacement-apply"].tap()
            }
            XCTAssertTrue(app.buttons["予定プリセットを閉じる"].waitForExistence(timeout: 5))
            app.buttons["予定プリセットを閉じる"].tap()
        }
        let added = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '休憩、'"))
        XCTAssertEqual(added.count, 2, app.debugDescription)
        for plan in added.allElementsBoundByIndex {
            XCTAssertEqual(plan.value as? String, "メイン予定")
            XCTAssertEqual(planMinutes(plan.label), [600, 660])
        }
        keepScreenshot(app, name: "週間プリセットは左右ともメイン予定")
    }

    func testWeeklyDurationPresetDropsAsMainOnRightSide() {
        let app = launch(templateReplacement: true, planMemos: true)
        let main = openFixtureWeek(app)
        let frame = main.frame
        openPresets(app, entry: "calendar-open-presets", kind: "plan")
        let label = app.staticTexts["読書"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let library = app.scrollViews.containing(.staticText, identifier: "読書").firstMatch
        for _ in 0..<3 where !label.isHittable || label.frame.maxY > app.frame.maxY - 60 {
            library.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(label.isHittable)
        XCTAssertLessThan(label.frame.maxY, app.frame.maxY - 50)
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: frame.minX + (frame.width + 4) * 2 + frame.width * 0.85, dy: frame.midY))
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        app.buttons["予定プリセットを閉じる"].tap()
        let added = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '読書、'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(added.value as? String, "メイン予定")
        let times = planMinutes(added.label)
        XCTAssertEqual(times[1] - times[0], 60)
        keepScreenshot(app, name: "週間の長さ指定プリセットも右側でメイン")
    }

    func testWeeklyMemoPresetTapAndDropExplainDayViewWithoutAdding() {
        let app = launch(planMemos: true)
        let main = openFixtureWeek(app)
        let original = main.label, frame = main.frame
        for drag in [false, true] {
            openPresets(app, entry: "calendar-open-presets", kind: "plan")
            let label = app.staticTexts["配達のメモ"].firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 5))
            if drag {
                let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
            } else { label.tap() }
            XCTAssertTrue(app.alerts.staticTexts["予定メモは日表示のプリセットから追加できます。"].waitForExistence(timeout: 5), app.debugDescription)
            app.alerts.buttons.firstMatch.tap()
            if app.buttons["予定プリセットを閉じる"].exists { app.buttons["予定プリセットを閉じる"].tap() }
            XCTAssertEqual(main.label, original)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '配達のメモ、'")).firstMatch.exists)
        }
        keepScreenshot(app, name: "週間のメモプリセットは日表示を案内")
    }

    func testRecurrenceStaysEnabledAfterIdleScrollAndHelp() {
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        let scroll = app.scrollViews["plan-editor-scroll"]
        let toggle = app.switches["plan-recurrence-enabled"]
        for _ in 0..<5 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 120 { scroll.swipeUp() }
        for attempt in 0..<3 {
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "1", "enable \(attempt)")
            for tick in 0..<10 {
                Thread.sleep(forTimeInterval: 1)
                XCTAssertEqual(toggle.value as? String, "1", "idle \(attempt):\(tick)")
            }
            scroll.swipeUp(); scroll.swipeDown()
            for _ in 0..<4 where !toggle.isHittable { scroll.swipeDown() }
            XCTAssertEqual(toggle.value as? String, "1")
            app.buttons["繰り返しについて"].tap()
            XCTAssertTrue(element(app, "information-popover").waitForExistence(timeout: 3))
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
            if attempt < 2 { toggle.tap(); XCTAssertEqual(toggle.value as? String, "0") }
        }
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        app.buttons["calendar-drawer-edit"].tap()
        XCTAssertTrue(app.buttons["繰り返しの元を編集"].exists)
    }

    func testMonthlyOrdinalWeekdayRecurrenceShowsSummaryAndSaves() {
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        let scroll = app.scrollViews["plan-editor-scroll"]
        let toggle = app.switches["plan-recurrence-enabled"]
        for _ in 0..<5 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 120 { scroll.swipeUp() }
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let monthly = app.segmentedControls["plan-recurrence-frequency"].buttons["毎月"]
        for _ in 0..<4 where !monthly.isHittable { scroll.swipeUp() }
        monthly.tap()
        let byWeekday = app.segmentedControls["plan-recurrence-monthly-mode"].buttons["曜日で"]
        for _ in 0..<4 where !byWeekday.isHittable { scroll.swipeUp() }
        byWeekday.tap()
        let second = app.buttons["第2週"]
        let fourth = app.buttons["第4週"]
        for _ in 0..<4 where !fourth.isHittable { scroll.swipeUp() }
        // 第1は初期値。第2・第4を足してから第1を外し、水曜を選ぶ（例：資源ごみ）。
        second.tap(); fourth.tap(); app.buttons["第1週"].tap()
        let wednesdays = app.buttons.matching(NSPredicate(format: "label == '水曜日'"))
        let wednesday = wednesdays.allElementsBoundByIndex.first { $0.isHittable } ?? wednesdays.firstMatch
        wednesday.tap()
        let summary = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '毎月 第2・第4水曜'")).firstMatch
        for _ in 0..<4 where !summary.exists { scroll.swipeDown() }
        XCTAssertTrue(summary.waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "毎月 第2・第4水曜の繰り返し")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
    }

    func testRecurrenceYearCountAndInfoAreSavedInMaster() {
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        let toggle = app.switches["plan-recurrence-enabled"]
        for _ in 0..<5 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 120 {
            app.scrollViews["plan-editor-scroll"].swipeUp()
        }
        app.buttons["繰り返しについて"].tap()
        let bubble = element(app, "information-popover")
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.swipeUp(); bubble.swipeDown()
        XCTAssertEqual(app.state, .runningForeground)
        keepScreenshot(app, name: "繰り返しの説明はアンカー付き吹き出し")
        // Outside the bubble: dismiss without toggling recurrence.
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(bubble.exists)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let yearly = app.segmentedControls["plan-recurrence-frequency"].buttons["毎年"]
        for _ in 0..<4 where !yearly.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        yearly.tap()
        let ending = app.segmentedControls["plan-recurrence-ending"].buttons["回数"]
        for _ in 0..<4 where !ending.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        ending.tap()
        let count = app.textFields["plan-recurrence-count"]
        count.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        count.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "3")
        XCTAssertEqual(count.value as? String, "3")
        keepScreenshot(app, name: "毎年と回数で終了する繰り返し")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        app.buttons["calendar-drawer-edit"].tap()
        let master = app.buttons["繰り返しの元を編集"]
        for _ in 0..<5 where !master.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        master.tap()
        XCTAssertTrue(app.navigationBars["プリセットを編集"].waitForExistence(timeout: 5))
        let stars = app.buttons.matching(NSPredicate(format: "label == '重要な予定'"))
        let starEvidence = XCTAttachment(string: stars.debugDescription)
        starEvidence.name = "プリセットの星ボタンの操作対象"
        starEvidence.lifetime = .keepAlways
        add(starEvidence)
        let important = stars.allElementsBoundByIndex.first { $0.isHittable } ?? stars.firstMatch
        XCTAssertTrue(important.isHittable, app.debugDescription)
        important.tap()
        XCTAssertEqual(important.value as? String, "オン")
        let summary = app.staticTexts["3回で終了"]
        for _ in 0..<5 where !summary.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(summary.exists, app.debugDescription)
        XCTAssertFalse(app.textFields["plan-recurrence-count"].exists)
        keepScreenshot(app, name: "設定済みの繰り返しは短い要約で表示")
        app.buttons.matching(NSPredicate(format: "label CONTAINS '3回で終了'")).firstMatch.tap()
        app.segmentedControls["plan-recurrence-ending"].buttons["日時"].tap()
        let endDate = element(app, "plan-recurrence-end-date")
        for _ in 0..<4 where !endDate.isHittable { app.scrollViews.allElementsBoundByIndex.first { $0.isHittable }?.swipeUp() }
        XCTAssertTrue(endDate.isHittable, app.debugDescription)
        XCTAssertFalse(count.exists)
        keepScreenshot(app, name: "繰り返しを日時で終了する設定")
        app.navigationBars["プリセットを編集"].buttons["保存"].tap()
        XCTAssertTrue(master.waitForExistence(timeout: 5))
        master.tap()
        XCTAssertTrue(app.navigationBars["プリセットを編集"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '毎年' AND label CONTAINS 'まで'")).firstMatch.exists)
        XCTAssertEqual(stars.allElementsBoundByIndex.first { $0.isHittable }?.value as? String, "オン")
    }

    func testMainAndMemoSwitchPreservesTimeAndPersists() {
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        let kind = app.segmentedControls["plan-kind-picker"]
        kind.buttons["予定メモ"].tap()
        keepScreenshot(app, name: "予定の種類を編集画面で切り替え")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").label.contains("予定メモ"))
        app.buttons["calendar-drawer-edit"].tap()
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertTrue(kind.buttons["予定メモ"].isSelected)
        kind.buttons["メイン予定"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        let row = element(app, "calendar-drawer-plan-\(sourceID)")
        XCTAssertFalse(row.label.contains("予定メモ"))
        XCTAssertTrue(row.label.contains("9:00") && row.label.contains("11:00"), row.label)
    }

    func testMemoPromotionCancelPreservesMemoAndApplyKeepsMainRemainders() {
        let app = launch(planMemos: true)
        let memoID = "00000000-0000-0000-0000-000000000102"
        openEditor(app, planID: memoID)
        let kind = app.segmentedControls["plan-kind-picker"]
        kind.buttons["メイン予定"].tap()
        app.buttons["保存"].tap()
        let apply = app.buttons["memo-promotion-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "重なるメインとメモの切替を確認")
        app.buttons["キャンセル"].firstMatch.tap()
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(memoID)").label.contains("予定メモ"))
        app.buttons["calendar-drawer-edit"].tap()
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertTrue(kind.buttons["予定メモ"].isSelected)
        kind.buttons["メイン予定"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 8))
        XCTAssertFalse(element(app, "calendar-drawer-plan-\(memoID)").label.contains("予定メモ"))
        app.buttons["当日の予定一覧に戻る"].tap()
        let original = element(app, "calendar-drawer-plan-\(sourceID)")
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertFalse(original.label.contains("予定メモ"))
        XCTAssertTrue(original.label.contains("9:00") && original.label.contains("9:30"), original.label)
        keepScreenshot(app, name: "重なる時間だけを入替して前後を保持")
    }

    func testMemoTimelineMoveAndResizeLeaveMainUnchanged() {
        let app = launch(expandedMode: "timeline", planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        _ = visibleDayTimeline(app)
        let main = app.buttons["day-plan-\(sourceID)"]
        let memo = app.buttons["day-plan-00000000-0000-0000-0000-000000000102"]
        let phone = app.buttons["day-plan-00000000-0000-0000-0000-000000000103"]
        XCTAssertTrue(main.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(memo.exists && phone.exists)
        let mainLabel = main.label
        let mainWidth = main.frame.width
        let phoneLabel = phone.label
        let before = planMinutes(memo.label)
        memo.tap()
        keepScreenshot(app, name: "メインの上に二つの予定メモ")
        let origin = memo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let moved = planMinutes(memo.label)
        XCTAssertGreaterThan(moved[0], before[0])
        XCTAssertEqual(main.label, mainLabel)
        XCTAssertEqual(phone.label, phoneLabel)
        XCTAssertEqual(main.frame.width, mainWidth, accuracy: 1)
        let endGrip = memo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: -24))
        endGrip.press(forDuration: 0.05, thenDragTo: endGrip.withOffset(CGVector(dx: 0, dy: 19)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let resized = planMinutes(memo.label)
        XCTAssertGreaterThan(resized[1], moved[1])
        XCTAssertEqual(main.label, mainLabel)
        XCTAssertEqual(phone.label, phoneLabel)
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(memo.isHittable, "メイン選択中も予定メモが隠れない")
        let memoLabel = memo.label
        let mainOrigin = main.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        mainOrigin.press(forDuration: 0.05, thenDragTo: mainOrigin.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertNotEqual(main.label, mainLabel)
        XCTAssertEqual(memo.label, memoLabel)
        XCTAssertEqual(phone.label, phoneLabel)
        keepScreenshot(app, name: "メモとメインを独立して移動・伸縮")
    }

    func testMemoPresetsApplyFromMonthWithoutReplacingMain() {
        let app = launch(planMemos: true)
        app.buttons["当日の予定を閉じる"].tap()
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: fixtureDay)!
        element(app, "calendar-month-day-\(dayID(nextDay))").tap()
        selectMonthPreset("配達のメモ", in: app)
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8))
        openMonthPresets(app, kind: "day")
        XCTAssertTrue(app.buttons["丸ごと追加"].waitForExistence(timeout: 5))
        app.buttons["丸ごと追加"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8), app.debugDescription)
        for name in ["配達のメモ", "持ち物確認", "午前の仕事"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(row.exists, app.debugDescription)
            XCTAssertEqual(row.label.contains("予定メモ"), name != "午前の仕事")
        }
        keepScreenshot(app, name: "月間で予定メモと混在する一日プリセットを適用")
    }

    func testWeeklyHidesMemosAndDayViewKeepsThemEditable() {
        let app = launch(planMemos: true)
        _ = openFixtureWeek(app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '荷物の受け取り、'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '電話する、'")).firstMatch.exists)
        keepScreenshot(app, name: "週間にはメモも印も表示しない")
        app.buttons["week-day-\(dayID(fixtureDay))"].tap()
        XCTAssertTrue(element(app, "calendar-day-summary-date").waitForExistence(timeout: 5))
        app.buttons["calendar-expanded-day-back"].tap()
        switchCalendarMode(app, "月間")
        element(app, "calendar-month-day-\(dayID(fixtureDay))").tap()
        app.buttons["calendar-drawer-open-timeline"].tap()
        let memo = app.buttons["day-plan-00000000-0000-0000-0000-000000000102"]
        XCTAssertTrue(memo.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(memo.value as? String, "予定メモ")
        memo.tap()
        memo.tap()
        let kind = app.segmentedControls["plan-kind-picker"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertTrue(kind.buttons["予定メモ"].isSelected)
        keepScreenshot(app, name: "日付を開くとメモを編集できる")
    }

    private func assertMoved(_ app: XCUIApplication, to day: Date) {
        let header = app.buttons["calendar-drawer-date"]
        XCTAssertTrue(header.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(header.value as? String, dayID(day))
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMonthEndRemainsReachableWithoutDrawer() {
        let app = launch()
        app.buttons["当日の予定を閉じる"].tap()
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: presetDay)!
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: nextMonth)!
        let lastCell = element(app, "calendar-month-day-\(dayID(lastDay))")
        let bottom = app.tabBars.firstMatch.frame.minY
        XCTAssertGreaterThan(bottom, app.frame.height * 0.5)
        for _ in 0..<3 where lastCell.frame.maxY > bottom {
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            origin.press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        keepScreenshot(app, name: "ドロワーなしでも月末の日付を選べる")
        XCTAssertLessThanOrEqual(lastCell.frame.maxY, bottom, "月末の行全体が下部タブに隠れない")
        XCTAssertTrue(lastCell.isHittable, app.debugDescription)
        lastCell.tap()
        let header = app.buttons["calendar-drawer-date"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, dayID(lastDay))
    }

    func testMonthDrawerAllowsCalendarScrollAndDragIntoNextMonth() {
        let app = launch()
        let header = app.buttons["calendar-drawer-date"]
        let originalY = header.frame.minY
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: presetDay)!
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: nextMonth)!
        let lastCell = element(app, "calendar-month-day-\(dayID(lastDay))")
        // Scroll only the month above the open drawer, leaving its selected date intact.
        for _ in 0..<3 where lastCell.frame.maxY > header.frame.minY - 16 {
            let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: header.frame.minY - 24))
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.buttons["calendar-period-button"].frame.maxY + 60))
            origin.press(forDuration: 0.01, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(lastCell.isHittable, app.debugDescription)
        XCTAssertLessThanOrEqual(lastCell.frame.maxY, header.frame.minY - 16, "月末の行全体をドロワーの上へスクロールできる")
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
        XCTAssertEqual(header.value as? String, dayID(fixtureDay))
        keepScreenshot(app, name: "ドロワーを開いたまま月末までスクロール")
        let swipeY = app.buttons["calendar-period-button"].frame.maxY + 90
        let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.85, dy: swipeY))
        origin.press(forDuration: 0.01, thenDragTo: origin.withOffset(CGVector(dx: -app.frame.width * 0.7, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0.1)
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: nextMonth)!
        let target = element(app, "calendar-month-day-\(dayID(destination))")
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(target.isHittable)
        element(app, "calendar-drawer-plan-\(sourceID)").press(forDuration: 0.7, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        assertMoved(app, to: destination)
        keepScreenshot(app, name: "開いたドロワーから翌月の日付へ移動")
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

    func testTimelineModeRoundTripKeepsMonthPlans() {
        let app = launch()
        app.buttons["当日の予定を閉じる"].tap()
        for mode in ["週間", "日間", "月間"] {
            switchCalendarMode(app, mode)
        }
        let day = element(app, "calendar-month-day-\(dayID(fixtureDay))")
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").waitForExistence(timeout: 5))
    }

    private func visibleDayTimeline(_ app: XCUIApplication) -> XCUIElement {
        let timelines = app.scrollViews.matching(identifier: "day-timeline")
        XCTAssertTrue(timelines.firstMatch.waitForExistence(timeout: 5))
        // Lazy paging retains neighboring scroll containers; interact only with
        // the viewport that can actually receive a finger gesture.
        let visible = timelines.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible, app.debugDescription)
        return visible ?? timelines.firstMatch
    }

    private func assertExpandedDate(_ app: XCUIApplication, _ date: Date) {
        let isTimeline = element(app, "day-timeline").exists
        let header = element(app, isTimeline ? "calendar-expanded-day-date" : "calendar-day-summary-date")
        expectation(for: NSPredicate(format: "value == %@", dayID(date)), evaluatedWith: header)
        waitForExpectations(timeout: 8)
        let contentHeaderID = isTimeline
            ? "calendar-day-timeline-date" : "calendar-day-summary-date"
        let viewport = app.frame
        let visibleHeader = app.descendants(matching: .any).matching(identifier: contentHeaderID)
            .allElementsBoundByIndex.first {
                let frame = $0.frame
                return frame.width > 0 && frame.height > 0
                    && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
            }
        XCTAssertNotNil(visibleHeader, "表示中の本文に日付があること: \(app.debugDescription)")
        XCTAssertEqual(visibleHeader?.value as? String, dayID(date))
    }

    private func planMinutes(_ label: String) -> [Int] {
        let pattern = try! NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})")
        let text = label as NSString
        let values = pattern.matches(in: label, range: NSRange(location: 0, length: text.length)).map {
            Int(text.substring(with: $0.range(at: 1)))! * 60 + Int(text.substring(with: $0.range(at: 2)))!
        }
        XCTAssertEqual(values.count, 2, label)
        return values
    }

    func testExpandedMonthDayCreatesPlanAndReturnsToSameDrawer() {
        let app = launch(templateReplacement: true)
        openPresetDay(app, offset: 1)
        let date = Calendar.current.date(byAdding: .day, value: 1, to: presetDay)!
        let drawerTop = app.buttons["calendar-drawer-open-timeline"].frame.minY
        app.buttons["calendar-drawer-open-timeline"].tap()
        XCTAssertFalse(element(app, "calendar-expanded-day-mode").exists)
        let timeline = visibleDayTimeline(app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), app.debugDescription)
        assertExpandedDate(app, date)
        app.buttons["仕事を選択"].tap()
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.2))
        start.press(forDuration: 0.5, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 57)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '仕事、'")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 8), app.debugDescription)
        let createdMinutes = planMinutes(plan.label)
        XCTAssertGreaterThanOrEqual(createdMinutes[0], 8 * 60, "拡大タイムラインは朝の時間帯から開く")
        let moveStart = plan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        moveStart.press(forDuration: 0.05, thenDragTo: moveStart.withOffset(CGVector(dx: 0, dy: 38)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let movedMinutes = planMinutes(plan.label)
        XCTAssertGreaterThan(movedMinutes[0], createdMinutes[0])
        XCTAssertEqual(movedMinutes[1] - movedMinutes[0], createdMinutes[1] - createdMinutes[0])
        // The selectable block includes 34 pt of overflow below the card. The
        // end grip sits just below the visible card, inside that overflow.
        let endGrip = plan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: -24))
        endGrip.press(forDuration: 0.05, thenDragTo: endGrip.withOffset(CGVector(dx: 0, dy: 19)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let resizedMinutes = planMinutes(plan.label)
        XCTAssertEqual(resizedMinutes[0], movedMinutes[0])
        XCTAssertGreaterThan(resizedMinutes[1], movedMinutes[1])
        keepScreenshot(app, name: "月表示から時間をなぞって予定を追加")

        let scrollStart = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75))
        scrollStart.press(forDuration: 0.01, thenDragTo: scrollStart.withOffset(CGVector(dx: 0, dy: -76)), withVelocity: .slow, thenHoldForDuration: 0.2)
        app.buttons["calendar-expanded-day-back"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '仕事'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.buttons["calendar-drawer-open-timeline"].frame.minY, drawerTop, accuracy: 2)
        XCTAssertEqual(app.buttons["calendar-drawer-date"].value as? String, dayID(date))
        keepScreenshot(app, name: "追加した予定を同じ月間ドロワーで確認")
        app.buttons["calendar-drawer-date"].tap()
        assertExpandedDate(app, date)
        XCTAssertFalse(element(app, "day-timeline").exists)
        keepScreenshot(app, name: "日付から一日のまとめを確認")
    }

    func testExpandedTimelinePagesAndAppliesPresetsToVisibleDate() {
        let app = launch(templateReplacement: true, expandedMode: "timeline")
        openPresetDay(app, offset: 1)
        app.buttons["calendar-drawer-open-timeline"].tap()
        let timeline = visibleDayTimeline(app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element(app, "calendar-expanded-day-mode").exists)
        XCTAssertFalse(app.buttons["calendar-open-presets"].isHittable)
        timeline.swipeLeft()
        let destination = Calendar.current.date(byAdding: .day, value: 2, to: presetDay)!
        assertExpandedDate(app, destination)
        openPresets(app, entry: "timeline-open-presets", kind: "plan")
        XCTAssertTrue(app.staticTexts["休憩"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["休憩"].firstMatch.tap()
        XCTAssertTrue(app.buttons["休憩、10:00から11:00"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["休憩、10:00から11:00"].isHittable)
        openPresets(app, entry: "timeline-open-presets", kind: "day")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-preset-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.buttons["丸ごと追加"].waitForExistence(timeout: 5))
        app.buttons["丸ごと追加"].tap()
        XCTAssertTrue(app.navigationBars["予定を入れ替える"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["replacement-apply"].tap()
        XCTAssertTrue(app.buttons["勉強、10:00から11:00"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["勉強、10:00から11:00"].isHittable)
        assertExpandedDate(app, destination)
        keepScreenshot(app, name: "日付移動後のタイムラインへ一日プリセットを適用")
        app.buttons["calendar-expanded-day-back"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-open-timeline"].waitForExistence(timeout: 5))
        openPresetDay(app, offset: 2)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch.waitForExistence(timeout: 5))
        openPresetDay(app, offset: 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch.exists)
    }

    private func applyDayPresetFromUnifiedDrawer(_ app: XCUIApplication, entry: String, replaces: Bool) {
        openPresets(app, entry: entry, kind: "day")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-preset-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.buttons["丸ごと追加"].waitForExistence(timeout: 5))
        app.buttons["丸ごと追加"].tap()
        if replaces {
            XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons["replacement-apply"].tap()
        }
        XCTAssertTrue(app.buttons["preset-kind-day"].waitForNonExistence(timeout: 8), app.debugDescription)
    }

    func testDayPresetFromDayViewReplacesAndClosesDrawer() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "日間")
        XCTAssertTrue(visibleDayTimeline(app).waitForExistence(timeout: 5))
        applyDayPresetFromUnifiedDrawer(app, entry: "calendar-open-presets", replaces: true)
        XCTAssertTrue(app.buttons["勉強、10:00から11:00"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["作業、09:00から12:00"].exists)
        keepScreenshot(app, name: "日間から一日プリセットを置換して反映")
    }

    func testDayPresetFromTomorrowReplacesAndClosesDrawer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogMonthDrawerUITests", "-LiminalogUITestTemplateReplacement",
            "-LiminalogInitialRootTab", "today", "-home.tomorrowPlanMode", "timeline",
            "-calendar.filter.usesCustomCategories", "NO", "-timeline.day.hourScale", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["明日の予定"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["明日の予定"].firstMatch.tap()
        XCTAssertTrue(visibleDayTimeline(app).waitForExistence(timeout: 5))
        openPresets(app, entry: "timeline-open-presets", kind: "plan")
        app.staticTexts["休憩"].firstMatch.tap()
        XCTAssertTrue(app.buttons["休憩、10:00から11:00"].waitForExistence(timeout: 8))
        applyDayPresetFromUnifiedDrawer(app, entry: "timeline-open-presets", replaces: true)
        XCTAssertTrue(app.buttons["勉強、10:00から11:00"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["休憩、10:00から11:00"].exists)
        keepScreenshot(app, name: "ホーム明日の一日プリセットを置換して反映")
    }

    func testWeeklyDayPresetUsesSelectedDateForReplacement() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "週間")
        for dayIndex in [1, 0] {
            openPresets(app, entry: "calendar-open-presets", kind: "day")
            selectPresetDate(app, identifier: "day-preset-drawer-date", dayIndex: dayIndex)
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-preset-card-'")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(app.buttons["丸ごと追加"].waitForExistence(timeout: 5))
            app.buttons["丸ごと追加"].tap()
            if dayIndex == 0 {
                XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertTrue(app.staticTexts["作業"].firstMatch.exists, "選んだ日の既存予定を置換対象にする")
                app.buttons["replacement-apply"].tap()
            }
            XCTAssertTrue(app.buttons["preset-kind-day"].waitForNonExistence(timeout: 8), app.debugDescription)
        }
        let study = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'week-plan-' AND label BEGINSWITH '勉強、'"))
        XCTAssertEqual(study.count, 2, app.debugDescription)
        keepScreenshot(app, name: "週間の追加する日を変更して置換と通常追加")
        switchCalendarMode(app, "月間")
        for offset in [0, 1] {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: presetDay)!
            element(app, "calendar-month-day-\(dayID(date))").tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch.waitForExistence(timeout: 5))
            let work = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '作業'"))
            if offset == 0 {
                // Default replacement keeps the non-overlapping parts of 09:00–12:00.
                XCTAssertEqual(work.count, 2)
                let intervals = work.allElementsBoundByIndex.map { planMinutes($0.label) }.sorted { $0[0] < $1[0] }
                XCTAssertEqual(intervals, [[540, 600], [660, 720]])
            } else {
                XCTAssertEqual(work.count, 0)
            }
            app.buttons["当日の予定を閉じる"].tap()
        }
        element(app, "calendar-month-day-\(dayID(fixtureDay))").tap()
        XCTAssertTrue(element(app, "calendar-drawer-plan-\(sourceID)").waitForExistence(timeout: 5))
    }

    func testPresetAndCreateButtonsRespondAtTargetEdges() {
        let app = launch(planMemos: true)
        for id in ["calendar-open-presets", "この日に予定を追加", "calendar-drawer-open-timeline", "当日の予定を閉じる"] {
            print("HEADER_TARGET \(id): \(app.buttons[id].frame)")
        }
        keepScreenshot(app, name: "ヘッダーのタップ範囲確認")
        let preset = app.buttons["calendar-open-presets"]
        let presetEdge = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: preset.frame.midX, dy: preset.frame.midY + 18))
        presetEdge.tap()
        XCTAssertTrue(app.buttons["preset-kind-plan"].waitForExistence(timeout: 5), "プリセットの44pt領域の下端が反応する")
        app.buttons["閉じる"].firstMatch.tap()
        let create = app.buttons["この日に予定を追加"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(create.frame.height, 40, create.debugDescription)
        create.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.segmentedControls["plan-kind-picker"].waitForExistence(timeout: 5), "予定追加の44pt領域の下端が反応する")
    }

    func testDrawerHeaderOpensExplicitDestinationsRegardlessOfLegacyPreference() {
        for legacyMode in ["summary", "timeline"] {
            let app = launch(expandedMode: legacyMode, planMemos: true)
            let date = app.buttons["calendar-drawer-date"]
            let timeline = app.buttons["calendar-drawer-open-timeline"]
            let originalY = date.frame.minY
            let controls = [date, app.buttons["calendar-open-presets"], app.buttons["この日に予定を追加"],
                            timeline, app.buttons["当日の予定を閉じる"]]
            for (index, control) in controls.enumerated() {
                XCTAssertTrue(control.isHittable, control.debugDescription)
                // The system's inset sheet presentation scales 44 pt targets on screen.
                XCTAssertGreaterThanOrEqual(control.frame.height, 40, control.debugDescription)
                XCTAssertTrue(app.frame.contains(control.frame), control.debugDescription)
                for other in controls.dropFirst(index + 1) {
                    assertHeaderControlsDoNotOverlap(control, other)
                }
            }
            XCTAssertEqual(date.frame.midY, timeline.frame.midY, accuracy: 2)
            let presets = app.buttons["calendar-open-presets"]
            XCTAssertLessThan(presets.frame.maxY, date.frame.minY)
            XCTAssertGreaterThan(app.buttons["この日に予定を追加"].frame.minX, timeline.frame.minX)
            XCTAssertGreaterThanOrEqual(app.buttons["当日の予定を閉じる"].frame.minX,
                                        app.buttons["この日に予定を追加"].frame.maxX - 1)
            keepScreenshot(app, name: "元の上部配置とプラス右側の閉じるボタン")
            date.tap()
            XCTAssertTrue(element(app, "calendar-day-summary-date").waitForExistence(timeout: 8))
            assertExpandedDate(app, fixtureDay)
            XCTAssertFalse(element(app, "day-timeline").exists)
            XCTAssertFalse(element(app, "calendar-expanded-day-mode").exists)
            keepScreenshot(app, name: "日付から一日のまとめ")
            app.buttons["calendar-expanded-day-back"].tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            XCTAssertEqual(date.frame.minY, originalY, accuracy: 2)
            timeline.tap()
            XCTAssertTrue(visibleDayTimeline(app).waitForExistence(timeout: 8))
            assertExpandedDate(app, fixtureDay)
            XCTAssertFalse(element(app, "calendar-expanded-day-mode").exists)
            keepScreenshot(app, name: "時間軸アイコンからタイムライン")
            app.buttons["calendar-expanded-day-back"].tap()
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            XCTAssertEqual(date.frame.minY, originalY, accuracy: 2)
        }
    }

    func testDrawerHeaderAdaptsToAccessibilityTextSize() {
        let app = launch(planMemos: true, contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let controls = [app.buttons["calendar-drawer-date"], app.buttons["calendar-open-presets"],
                        app.buttons["この日に予定を追加"],
                        app.buttons["calendar-drawer-open-timeline"], app.buttons["当日の予定を閉じる"]]
        for (index, control) in controls.enumerated() {
            XCTAssertTrue(control.isHittable, control.debugDescription)
            XCTAssertTrue(app.frame.contains(control.frame), control.debugDescription)
            for other in controls.dropFirst(index + 1) {
                assertHeaderControlsDoNotOverlap(control, other)
            }
        }
        keepScreenshot(app, name: "文字拡大時のドロワー見出し")
        app.buttons["calendar-drawer-open-timeline"].tap()
        XCTAssertTrue(visibleDayTimeline(app).waitForExistence(timeout: 8))
        app.buttons["calendar-expanded-day-back"].tap()
        XCTAssertTrue(app.buttons["calendar-drawer-date"].waitForExistence(timeout: 5))
    }

    private func assertHeaderControlsDoNotOverlap(_ control: XCUIElement, _ other: XCUIElement) {
        let intersection = control.frame.intersection(other.frame)
        // Adjacent targets share an edge; the system sheet transform can round it differently.
        XCTAssertTrue(intersection.width < 1 || intersection.height < 1,
                      "Header controls overlap: \(control.frame), \(other.frame); intersection: \(intersection)")
    }

    func testMonthPresetDateCanChangeBeforeApplying() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        selectMonthPreset("休日", in: app)
        selectPresetDate(app, identifier: "month-preset-target-date", dayIndex: 1)
        keepScreenshot(app, name: "予定プリセットの適用日を変更")
        app.buttons["month-preset-apply"].tap()
        let date = app.buttons["calendar-drawer-date"]
        XCTAssertTrue(date.waitForExistence(timeout: 8))
        let planDay = Calendar.current.date(byAdding: .day, value: 1, to: presetDay)!
        XCTAssertEqual(date.value as? String, dayID(planDay))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '休日'")).firstMatch.exists)

        app.buttons["当日の予定を閉じる"].tap()
        openMonthPresets(app, kind: "day")
        XCTAssertTrue(element(app, "day-preset-target-date").waitForExistence(timeout: 5))
        selectPresetDate(app, identifier: "day-preset-target-date", dayIndex: 2)
        keepScreenshot(app, name: "一日プリセットの日付変更で重なりも再判定")
        app.buttons["丸ごと追加"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        let dayPresetDay = Calendar.current.date(byAdding: .day, value: 2, to: presetDay)!
        XCTAssertEqual(date.value as? String, dayID(dayPresetDay))
        XCTAssertFalse(app.buttons["replacement-apply"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch.exists)
        openPresetDay(app)
        XCTAssertTrue(element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000201").exists)
    }

    private func selectPresetDate(_ app: XCUIApplication, identifier: String, dayIndex: Int) {
        let dateControl = element(app, identifier)
        dateControl.tap()
        let days = app.datePickers.collectionViews.buttons
        XCTAssertTrue(days.element(boundBy: dayIndex).waitForExistence(timeout: 5), app.debugDescription)
        days.element(boundBy: dayIndex).tap()
        let dismiss = app.buttons["PopoverDismissRegion"]
        if dismiss.exists {
            // Use the current date row: native date selection can expand its
            // sheet. A generic outside tap can hit the underlying preset tabs.
            let controlFrame = dateControl.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: controlFrame.midX, dy: controlFrame.midY)).tap()
        }
    }

    func testMonthPresetDragBeforeSelectingADayUsesDroppedDay() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: presetDay)!
        let targetFrame = element(app, "calendar-month-day-\(dayID(destination))").frame
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        openMonthPresets(app, kind: "plan")
        let tile = app.buttons.matching(NSPredicate(format: "label == '休憩' AND identifier BEGINSWITH 'month-preset-'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        let date = app.buttons["calendar-drawer-date"]
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(date.value as? String, dayID(destination))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '休憩'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["month-preset-apply"].exists)
        keepScreenshot(app, name: "日付選択前から直接ドラッグして追加")
    }

    func testMonthPresetBarWorksBeforeSelectingADay() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        let date = app.buttons["calendar-drawer-date"]
        XCTAssertFalse(date.exists)
        XCTAssertTrue(app.buttons["calendar-open-presets"].isHittable)
        keepScreenshot(app, name: "日付選択前のカレンダーとプリセット入口")
        selectMonthPreset("休日", in: app)
        XCTAssertTrue(element(app, "month-preset-target-date").exists)
        keepScreenshot(app, name: "予定プリセットの適用先を確認")
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(date.value as? String, dayID(presetDay))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '休日'")).firstMatch.exists)

        app.buttons["当日の予定を閉じる"].tap()
        openMonthPresets(app, kind: "day")
        XCTAssertTrue(element(app, "day-preset-target-date").waitForExistence(timeout: 5))
        keepScreenshot(app, name: "一日プリセットの適用先を確認")
        app.buttons["丸ごと追加"].tap()
        XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 5))
        app.buttons["replacement-apply"].tap()
        XCTAssertTrue(date.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(date.value as? String, dayID(presetDay))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch.exists)
    }

    func testReplacementChoicesShowResultsInCompactSheet() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "日間")
        func openConfirmation() {
            openPresets(app, entry: "calendar-open-presets", kind: "plan")
            let preset = app.staticTexts["休憩"].firstMatch
            XCTAssertTrue(preset.waitForExistence(timeout: 5))
            preset.tap()
            XCTAssertTrue(app.navigationBars["予定を入れ替える"].waitForExistence(timeout: 8), app.debugDescription)
        }
        openConfirmation()
        let navigation = app.navigationBars["予定を入れ替える"]
        XCTAssertGreaterThan(navigation.frame.minY, app.frame.height * 0.15)
        let partial = app.buttons["replacement-option-keepRemainders"]
        let whole = app.buttons["replacement-option-replaceWholePlans"]
        XCTAssertTrue(partial.exists)
        XCTAssertTrue(whole.exists)
        XCTAssertTrue(partial.isSelected)
        whole.tap()
        XCTAssertTrue(whole.isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["キャンセル"].tap()
        openConfirmation()
        XCTAssertTrue(app.buttons["replacement-option-keepRemainders"].isSelected)
        navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: navigation)
        waitForExpectations(timeout: 5)
        openConfirmation()
        app.buttons["replacement-apply"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: navigation)
        waitForExpectations(timeout: 5)
    }

    private var presetDay: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: fixtureDay))!
    }

    /// 表示切替は年月を押して出るシートのタブ。押すと切り替わって閉じる。
    private func switchCalendarMode(_ app: XCUIApplication, _ mode: String) {
        let period = app.buttons["calendar-period-button"]
        XCTAssertTrue(period.waitForExistence(timeout: 5), app.debugDescription)
        period.tap()
        let tab = app.buttons[mode]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), app.debugDescription)
        tab.tap()
    }

    /// プリセットの入口は1つ。開いた先で「予定／一日」を選ぶ（前回のタブを覚えているので毎回選ぶ）。
    private func openPresets(_ app: XCUIApplication, entry: String, kind: String) {
        let button = app.buttons[entry]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
        let tab = app.buttons["preset-kind-\(kind)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), app.debugDescription)
        tab.tap()
    }

    private func openMonthPresets(_ app: XCUIApplication, kind: String) {
        openPresets(app, entry: "calendar-open-presets", kind: kind)
    }

    private func openPresetDay(_ app: XCUIApplication, offset: Int = 0) {
        app.buttons["当日の予定を閉じる"].tap()
        let date = Calendar.current.date(byAdding: .day, value: offset, to: presetDay)!
        element(app, "calendar-month-day-\(dayID(date))").tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 5))
    }

    private func selectMonthPreset(_ name: String, in app: XCUIApplication) {
        openMonthPresets(app, kind: "plan")
        let preset = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'month-preset-'", name)).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), app.debugDescription)
        if !preset.isHittable { app.scrollViews.firstMatch.swipeUp() }
        preset.tap()
        XCTAssertTrue(app.buttons["month-preset-apply"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Opt-in evidence capture for docs/37 §7. Set LIMINALOG_CAPTURE_UI=1 in
    // the xctestrun EnvironmentVariables; set Simulator appearance externally.
    private func requirePolishCapture() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Developer sample capture is restricted to Simulator.")
        #endif
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIMINALOG_CAPTURE_UI"] == "1")
        continueAfterFailure = false
    }

    func testSummaryPresetDurationUsesVisibleDateAndPlusOpensEditorDirectly() {
        let app = launch(templateReplacement: true)
        openPresetDay(app, offset: 1)
        app.buttons["calendar-drawer-date"].tap()
        XCTAssertTrue(app.buttons["summary-open-presets"].waitForExistence(timeout: 5))
        app.buttons["予定を追加"].tap()
        XCTAssertTrue(app.segmentedControls["plan-kind-picker"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        // Move to the following day before opening the sheet: the preset must
        // use the visible page, not CalendarDayPagerSheet.initialDate.
        app.swipeLeft()
        assertExpandedDate(app, Calendar.current.date(byAdding: .day, value: 2, to: presetDay)!)
        openPresets(app, entry: "summary-open-presets", kind: "plan")
        XCTAssertFalse(app.staticTexts["長押ししてカレンダーの日付へ置く"].exists)
        let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'month-preset-' AND label == '読書'")).firstMatch
        for _ in 0..<3 where !tile.isHittable { app.scrollViews.firstMatch.swipeUp() }
        tile.tap()
        XCTAssertFalse(element(app, "month-preset-target-date").exists)
        XCTAssertEqual(app.pickerWheels.count, 2)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "18")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30")
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.buttons["summary-open-presets"].waitForExistence(timeout: 5))
        app.buttons["calendar-expanded-day-back"].tap()
        openPresetDay(app, offset: 2)
        let reading = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '読書'")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(reading.label.contains("18:30") && reading.label.contains("19:30"), reading.label)
        openPresetDay(app, offset: 1)
        XCTAssertFalse(reading.exists)
    }

    func testSummaryDayPresetReplacesOnItsFixedDate() {
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        app.buttons["calendar-drawer-date"].tap()
        openPresets(app, entry: "summary-open-presets", kind: "day")
        XCTAssertFalse(element(app, "day-preset-target-date").exists)
        let apply = app.buttons["丸ごと追加"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5), app.debugDescription)
        apply.tap()
        XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 5))
        app.buttons["replacement-apply"].tap()
        XCTAssertTrue(app.buttons["summary-open-presets"].waitForExistence(timeout: 5))
        app.buttons["calendar-expanded-day-back"].tap()
        let study = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '勉強'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 5), app.debugDescription)
        openPresetDay(app, offset: 1)
        XCTAssertFalse(study.exists)
    }

    func testCapturePolishSummaryPresets() throws {
        try requirePolishCapture()
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        app.buttons["calendar-drawer-date"].tap()
        openPresets(app, entry: "summary-open-presets", kind: "plan")
        keepScreenshot(app, name: "14-summary-plan-presets")
        app.buttons["preset-kind-day"].tap()
        keepScreenshot(app, name: "14-summary-day-presets")
    }

    private func launchSeededCapture(tab: String = "calendar", page: String = "today") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LiminalogSeedDevData", "YES", "-LiminalogSeedDevFriends", "YES",
            "-LiminalogInitialRootTab", tab, "-LiminalogInitialCalendarMode", "month",
            "-LiminalogInitialTodayPage", page, "-calendar.filter.usesCustomCategories", "NO"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        return app
    }

    func testCapturePolishSeededCalendar() throws {
        try requirePolishCapture()
        let app = launchSeededCapture()
        let period = app.buttons["calendar-period-button"]
        XCTAssertTrue(period.waitForExistence(timeout: 30))
        keepScreenshot(app, name: "01-month")
        period.tap()
        XCTAssertTrue(app.buttons["週間"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "02-period")
        app.buttons["月間"].tap()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let day = element(app, "calendar-month-day-\(dayID(tomorrow))")
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        app.buttons["calendar-drawer-date"].tap()
        XCTAssertTrue(app.buttons["calendar-expanded-day-back"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "10-future-summary")
    }

    func testCapturePolishHomeAndChapter() throws {
        try requirePolishCapture()
        let app = launchSeededCapture(tab: "today", page: "tomorrow")
        // Capture the requested screen through its normal entry as well. A
        // fresh Xcode test session can open Today before debug launch routing.
        app.buttons["明日の予定"].tap()
        XCTAssertTrue(app.buttons["timeline-open-presets"].waitForExistence(timeout: 20), app.debugDescription)
        keepScreenshot(app, name: "06-home-tomorrow")
        app.terminate()
        let today = launchSeededCapture(tab: "today")
        today.buttons["今日の記録"].tap()
        let actual = today.buttons["実績"]
        for _ in 0..<6 where !actual.isHittable { today.swipeUp() }
        XCTAssertTrue(actual.isHittable, today.debugDescription)
        actual.tap()
        let row = today.buttons.matching(NSPredicate(format: "label BEGINSWITH '睡眠、'")).firstMatch
        for _ in 0..<6 where !row.isHittable { today.swipeUp() }
        XCTAssertTrue(row.isHittable, today.debugDescription)
        row.tap()
        XCTAssertTrue(today.navigationBars["チャプターを編集"].waitForExistence(timeout: 5), today.debugDescription)
        let category = today.buttons["plan-category-picker"]
        if category.exists && category.images["chevron.down"].exists { category.tap() }
        keepScreenshot(today, name: "12-chapter-category")
    }

    func testCapturePolishPresets() throws {
        try requirePolishCapture()
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        openMonthPresets(app, kind: "plan")
        keepScreenshot(app, name: "03-month-plan-presets")
        app.buttons["preset-kind-day"].tap()
        keepScreenshot(app, name: "03-month-day-presets")
        app.buttons["キャンセル"].tap()
        switchCalendarMode(app, "週間")
        openPresets(app, entry: "calendar-open-presets", kind: "plan")
        keepScreenshot(app, name: "04-week-plan-presets")
        app.buttons["preset-kind-day"].tap()
        keepScreenshot(app, name: "04-week-day-presets")
    }

    func testCapturePolishPresetEditor() throws {
        try requirePolishCapture()
        let settingsApp = launch(templateReplacement: true)
        openFixturePresetEditor(settingsApp)
        let category = settingsApp.buttons["plan-category-picker"]
        if category.exists {
            if category.images["chevron.down"].exists { category.tap() }
            let other = settingsApp.buttons["その他の並び順"]
            let scroll = settingsApp.scrollViews.containing(.button, identifier: "plan-category-picker").firstMatch
            for _ in 0..<3 where !other.isHittable || other.frame.maxY > settingsApp.frame.maxY - 120 {
                scroll.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(category.isHittable && other.isHittable)
        }
        keepScreenshot(settingsApp, name: "13-preset-category")
    }

    private func openFixturePresetEditor(_ settingsApp: XCUIApplication) {
        settingsApp.buttons["当日の予定を閉じる"].tap()
        settingsApp.buttons["カレンダー表示設定"].tap()
        let presets = settingsApp.buttons["予定プリセット"]
        for _ in 0..<5 where !presets.isHittable { settingsApp.swipeUp() }
        XCTAssertTrue(presets.isHittable, settingsApp.debugDescription)
        presets.tap()
        let preset = settingsApp.staticTexts["休憩を編集"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), settingsApp.debugDescription)
        preset.tap()
        XCTAssertTrue(settingsApp.navigationBars["プリセットを編集"].waitForExistence(timeout: 5), settingsApp.debugDescription)
    }

    func testPresetInlineCategorySavesChoiceAndSharesExpansionPreference() {
        let app = launch(templateReplacement: true)
        openFixturePresetEditor(app)
        let category = app.buttons["plan-category-picker"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        if !app.buttons["その他の並び順"].exists { category.tap() }
        let scroll = app.scrollViews.containing(.button, identifier: "plan-category-picker").firstMatch
        let work = scroll.buttons.matching(NSPredicate(format: "label BEGINSWITH '仕事'")).firstMatch
        for _ in 0..<3 where !work.isHittable { scroll.swipeUp() }
        work.tap()
        XCTAssertEqual(category.value as? String, "仕事")
        category.tap()
        XCTAssertFalse(app.buttons["その他の並び順"].exists)
        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["予定プリセット"].waitForExistence(timeout: 5))
        app.staticTexts["休憩を編集"].firstMatch.tap()
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? String, "仕事")
        XCTAssertFalse(app.buttons["その他の並び順"].exists)
        let editor = launch(planMemos: true)
        openEditor(editor, planID: sourceID)
        XCTAssertTrue(editor.buttons["plan-category-picker"].exists)
        XCTAssertFalse(editor.buttons["その他の並び順"].exists)
    }

    func testCapturePolishEditorAndTimeline() throws {
        try requirePolishCapture()
        let app = launch(planMemos: true)
        app.buttons["calendar-drawer-open-timeline"].tap()
        XCTAssertTrue(app.buttons["timeline-open-presets"].waitForExistence(timeout: 10))
        keepScreenshot(app, name: "05-expanded-timeline")
        app.buttons["calendar-expanded-day-back"].tap()
        openEditor(app, planID: sourceID)
        let category = app.buttons["plan-category-picker"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["plan-editor-scroll"]
        if !app.buttons["その他の並び順"].exists { category.tap() }
        let otherOrder = app.buttons["その他の並び順"]
        for _ in 0..<4 where !otherOrder.isHittable || otherOrder.frame.maxY > app.frame.maxY - 120 {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(category.isHittable && otherOrder.isHittable)
        keepScreenshot(app, name: "07-category-open")
        category.tap()
        keepScreenshot(app, name: "07-category-closed")
        let visible = app.switches["友達に見せる"]
        for _ in 0..<6 where !visible.isHittable || visible.frame.maxY > app.frame.maxY - 180 { scroll.swipeUp() }
        if visible.value as? String == "0" { visible.tap() }
        let audience = app.buttons["公開相手"]
        for _ in 0..<3 where !audience.isHittable { scroll.swipeUp() }
        keepScreenshot(app, name: "08-public-audience-row")
        audience.tap()
        XCTAssertTrue(app.segmentedControls.buttons["カテゴリの既定"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "08-public-audience-sheet")
    }

    func testCapturePolishMonthlyRecurrence() throws {
        try requirePolishCapture()
        let app = launch(planMemos: true)
        openEditor(app, planID: sourceID)
        let scroll = app.scrollViews["plan-editor-scroll"]
        let toggle = app.switches["plan-recurrence-enabled"]
        for _ in 0..<5 where !toggle.isHittable || toggle.frame.maxY > app.frame.maxY - 120 { scroll.swipeUp() }
        toggle.tap()
        app.segmentedControls["plan-recurrence-frequency"].buttons["毎月"].tap()
        let byWeekday = app.segmentedControls["plan-recurrence-monthly-mode"].buttons["曜日で"]
        for _ in 0..<4 where !byWeekday.isHittable { scroll.swipeUp() }
        byWeekday.tap()
        let fourth = app.buttons["第4週"]
        for _ in 0..<4 where !fourth.isHittable { scroll.swipeUp() }
        app.buttons["第2週"].tap(); fourth.tap(); app.buttons["第1週"].tap()
        app.buttons["水曜日"].tap()
        keepScreenshot(app, name: "11-monthly-weekday")
    }

    func testCapturePolishFriendVisibility() throws {
        try requirePolishCapture()
        let app = launchSeededCapture(tab: "friends")
        let friend = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mika'" )).firstMatch
        XCTAssertTrue(friend.waitForExistence(timeout: 20), app.debugDescription)
        friend.tap()
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'この友達への見え方'" )).firstMatch
        for _ in 0..<7 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable, app.debugDescription)
        for _ in 0..<3 where picker.frame.minY > 300 { app.swipeUp(velocity: .slow) }
        picker.tap(); app.buttons["控えめ"].tap()
        keepScreenshot(app, name: "09-friend-limited")
        picker.tap(); app.buttons["オフ"].tap()
        keepScreenshot(app, name: "09-friend-off")
    }

    func testMonthFixedPresetShowsEveryChangedPlanAndKeepsRemainders() {
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        keepScreenshot(app, name: "月間のプリセット入口")
        selectMonthPreset("外出", in: app)
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.navigationBars["予定を入れ替える"].waitForExistence(timeout: 5), app.debugDescription)
        let original = element(app, "replacement-before-00000000-0000-0000-0000-000000000201-0")
        XCTAssertTrue(original.label.contains("作業、09:00–12:00"), app.debugDescription)
        XCTAssertTrue(element(app, "replacement-before-00000000-0000-0000-0000-000000000202-0").exists)
        XCTAssertEqual(element(app, "replacement-keepRemainders-00000000-0000-0000-0000-000000000201-0").label, "作業、09:00–11:00")
        XCTAssertEqual(element(app, "replacement-keepRemainders-00000000-0000-0000-0000-000000000202-0").label, "打ち合わせ、14:00–16:00")
        XCTAssertEqual(element(app, "replacement-replaceWholePlans-new-0").label, "外出、11:00–14:00")
        XCTAssertFalse(element(app, "replacement-replaceWholePlans-00000000-0000-0000-0000-000000000201-0").exists)
        keepScreenshot(app, name: "実際の予定で二つの置換結果を比較")
        app.buttons["replacement-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8), app.debugDescription)
        let morning = element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000201")
        XCTAssertTrue(morning.waitForExistence(timeout: 5))
        XCTAssertTrue(morning.label.contains("9:00") && morning.label.contains("11:00"), morning.label)
        let afternoon = element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000202")
        if !afternoon.isHittable { element(app, "calendar-drawer-scroll").swipeUp() }
        XCTAssertTrue(afternoon.label.contains("14:00") && afternoon.label.contains("16:00"), afternoon.label)
        keepScreenshot(app, name: "月間へ戻った部分置換の保存結果")
    }

    func testMonthDayPresetReplacesWholePlansAndIncludesAllDayItem() {
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        openMonthPresets(app, kind: "day")
        XCTAssertTrue(app.buttons["丸ごと追加"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["丸ごと追加"].tap()
        XCTAssertTrue(app.navigationBars["予定を入れ替える"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element(app, "replacement-replaceWholePlans-new-2").label, "学習日、終日")
        XCTAssertEqual(element(app, "replacement-replaceWholePlans-new-0").label, "勉強、10:00–11:00")
        XCTAssertEqual(element(app, "replacement-replaceWholePlans-new-1").label, "運動、14:00–15:00")
        app.buttons["replacement-option-replaceWholePlans"].tap()
        keepScreenshot(app, name: "一日プリセットの置換結果と終日予定")
        app.buttons["replacement-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000201").exists)
        XCTAssertFalse(element(app, "calendar-drawer-plan-00000000-0000-0000-0000-000000000202").exists)
        for name in ["学習日", "勉強", "運動"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS %@", name)).firstMatch
            if !row.isHittable { element(app, "calendar-drawer-scroll").swipeUp() }
            XCTAssertTrue(row.exists, app.debugDescription)
        }
        keepScreenshot(app, name: "月間から一日プリセットを保存")
    }

    func testMonthDurationAndAllDayPresetsCanBeAppliedWithoutTimeline() {
        let app = launch(templateReplacement: true)
        openPresetDay(app, offset: 1)
        selectMonthPreset("読書", in: app)
        let wheels = app.pickerWheels
        XCTAssertEqual(wheels.count, 2, app.debugDescription)
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "18")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "30")
        XCTAssertEqual(element(app, "month-preset-placement-preview").label, "読書、18:30–19:30")
        keepScreenshot(app, name: "月間から長さプリセットの開始時刻を指定")
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8), app.debugDescription)
        let reading = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '読書'")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertTrue(reading.label.contains("18:30") && reading.label.contains("19:30"), reading.label)
        selectMonthPreset("休日", in: app)
        XCTAssertEqual(element(app, "month-preset-placement-preview").label, "休日、終日")
        XCTAssertEqual(app.pickerWheels.count, 0)
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8))
        let allDay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '休日'")).firstMatch
        XCTAssertTrue(allDay.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(allDay.label.contains("終日"), allDay.label)
        keepScreenshot(app, name: "月間で時刻指定と終日プリセットを保存")
    }

    func testMonthPresetDragUsesDroppedDayAndAsksTimeOnlyForDuration() {
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        let destination = Calendar.current.date(byAdding: .day, value: 1, to: presetDay)!
        let targetFrame = element(app, "calendar-month-day-\(dayID(destination))").frame
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: targetFrame.midX, dy: targetFrame.midY))
        func drag(_ name: String) {
            openMonthPresets(app, kind: "plan")
            let tile = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH 'month-preset-'", name)).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 5), app.debugDescription)
            for _ in 0..<4 where !tile.isHittable { app.scrollViews.firstMatch.swipeUp() }
            tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        drag("休憩")
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["month-preset-apply"].exists)
        openPresetDay(app, offset: 1)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '休憩'")).firstMatch.waitForExistence(timeout: 5))
        drag("読書")
        XCTAssertTrue(app.buttons["month-preset-apply"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.pickerWheels.count, 2)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "18")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30")
        keepScreenshot(app, name: "月間ドロップ後の開始時刻")
        app.buttons["month-preset-apply"].tap()
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-drawer-plan-' AND label CONTAINS '読書' AND label CONTAINS '18:30'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "月間へドラッグで二種類のプリセットを追加")
    }

    func testPlanEditorRegistersRecurrenceAndReminderAndKeepsMasterSeparate() {
        let app = launch()
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        let edit = element(app, "calendar-drawer-edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let toggle = app.switches["plan-recurrence-enabled"]
        let scroll = app.scrollViews["plan-editor-scroll"]
        for _ in 0..<5 where !toggle.isHittable { scroll.swipeUp() }
        XCTAssertTrue(toggle.isHittable, app.debugDescription)
        let reminder = app.buttons["plan-reminder-picker"]
        XCTAssertTrue(reminder.exists, app.debugDescription)
        reminder.tap()
        app.buttons["10分前"].tap()
        toggle.tap()
        keepScreenshot(app, name: "予定編集から繰り返しと通知を登録")
        app.navigationBars["予定を編集"].buttons["保存"].tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        element(app, "calendar-drawer-edit").tap()
        let master = app.buttons["繰り返しの元を編集"]
        for _ in 0..<5 where !master.isHittable { app.scrollViews["plan-editor-scroll"].swipeUp() }
        XCTAssertTrue(master.isHittable, app.debugDescription)
        master.tap()
        XCTAssertTrue(app.navigationBars["プリセットを編集"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "その日の編集と周期の元を分離")
        app.buttons["キャンセル"].firstMatch.tap()
        app.buttons["キャンセル"].firstMatch.tap()
        app.buttons["当日の予定を閉じる"].tap()
        app.buttons["カレンダー表示設定"].tap()
        app.buttons["予定プリセット"].tap()
        XCTAssertTrue(app.staticTexts["繰り返しの予定"].waitForExistence(timeout: 5), app.debugDescription)
        keepScreenshot(app, name: "自動登録された周期設定の一覧")
    }

    func testDayPresetCanSaveAutomaticRecurrence() {
        let app = launch(templateReplacement: true)
        app.buttons["当日の予定を閉じる"].tap()
        app.buttons["カレンダー表示設定"].tap()
        app.buttons["一日プリセット"].tap()
        XCTAssertTrue(app.staticTexts["学習の日"].waitForExistence(timeout: 5), app.debugDescription)
        app.staticTexts["学習の日"].tap()
        let recurrence = app.buttons["day-preset-recurrence"]
        XCTAssertTrue(recurrence.waitForExistence(timeout: 5), app.debugDescription)
        recurrence.tap()
        let toggle = app.switches["plan-recurrence-enabled"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["毎日"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["毎日"].tap()
        keepScreenshot(app, name: "一日プリセットの自動適用設定")
        app.buttons["完了"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["学習の日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["毎日"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func testMonthPresetOutsideDropCancelsAndOverlapUsesReplacement() {
        let app = launch(templateReplacement: true)
        openPresetDay(app)
        let frame = element(app, "calendar-month-day-\(dayID(presetDay))").frame
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        openMonthPresets(app, kind: "plan")
        let tile = app.buttons.matching(NSPredicate(format: "label == '外出' AND identifier BEGINSWITH 'month-preset-'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.navigationBars["予定プリセット"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replacement-apply"].exists)
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5,
            thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["replacement-apply"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["replacement-option-keepRemainders"].exists)
        keepScreenshot(app, name: "月間ドロップで重なった予定を比較")
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
    }

    func testPlanEditorCategoryOpenRoundTrips() {
        let app = launch(planMemos: true)
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        for sample in 1...3 {
            let edit = app.buttons["calendar-drawer-edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            // This includes XCTest event delivery and AX queries, so it is an
            // end-to-end readiness observation, not a first-frame benchmark.
            let startedAt = ProcessInfo.processInfo.systemUptime
            edit.tap()
            let category = app.buttons["plan-category-picker"]
            XCTAssertTrue(category.waitForExistence(timeout: 5))
            XCTAssertTrue(category.isHittable)
            let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            print("PLAN_EDITOR_READY_SAMPLE \(sample) \(milliseconds)")
            XCTAssertEqual(category.value as? String, "仕事")
            if sample == 1 { keepScreenshot(app, name: "実機検証用・カテゴリ付き予定編集") }
            app.buttons["キャンセル"].tap()
        }
        XCTAssertTrue(app.buttons["calendar-drawer-edit"].waitForExistence(timeout: 5))
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

    func testExpandedDayPresentationLatency() throws {
        for mode in ["summary", "timeline"] {
            let app = launch(expandedMode: mode, measureExpansion: true)
            for sample in 1...3 {
                app.buttons[mode == "summary" ? "calendar-drawer-date" : "calendar-drawer-open-timeline"].tap()
                let metric = element(app, "calendar-expanded-day-metric")
                XCTAssertTrue(metric.waitForExistence(timeout: 30))
                let completed = NSPredicate(format: "value CONTAINS %@", "presented:")
                expectation(for: completed, evaluatedWith: metric)
                waitForExpectations(timeout: 30)
                let value = metric.value as? String ?? "missing"
                print("DAY_EXPANSION_SAMPLE \(mode) \(sample) \(value)")
                let attachment = XCTAttachment(string: "\(mode) \(sample) \(value)")
                attachment.lifetime = .keepAlways
                add(attachment)
                let dayCount = value.split(separator: "|").first { $0.hasPrefix("days:") }
                    .flatMap { Int($0.dropFirst("days:".count)) }
                XCTAssertLessThanOrEqual(try XCTUnwrap(dayCount), 5,
                    "Opening one day must not build the intervening months: \(value)")
                assertExpandedDate(app, fixtureDay)
                element(app, "calendar-expanded-day-back").tap()
                XCTAssertTrue(app.buttons["calendar-drawer-open-timeline"].waitForExistence(timeout: 5))
            }
        }
    }

    func testRecentPlanCanBeRegisteredAndLeavesRecentShelf() {
        let app = launch()
        app.buttons["当日の予定を閉じる"].tap()
        app.buttons["カレンダー表示設定"].tap()
        app.buttons["予定プリセット"].tap()
        let candidate = app.buttons["UITest 予定 12をプリセットに登録"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5), app.debugDescription)
        candidate.tap()
        XCTAssertTrue(app.navigationBars["プリセットを追加"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: candidate)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["すべてのプリセット"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["予定プリセットを編集"].tap()
        app.buttons["UITest 予定 12を削除"].tap()
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        XCTAssertTrue(app.navigationBars["プリセットを追加"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
    }

    func testRecentPlansAccessibleWithoutRegisteredPresets() {
        let app = launch()
        app.buttons["当日の予定を閉じる"].tap()
        switchCalendarMode(app, "日間")
        openPresets(app, entry: "calendar-open-presets", kind: "plan")
        XCTAssertTrue(app.staticTexts["最近作った予定"].waitForExistence(timeout: 5))
        let candidate = element(app, "UITest 予定 12、30分、長押しして配置")
        XCTAssertTrue(candidate.waitForExistence(timeout: 5), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let header = app.buttons["calendar-drawer-date"]
        let originalY = header.frame.minY
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
        app.buttons["当日の予定一覧に戻る"].tap()
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
    }

    func testRightSwipeOnDetailPlanReturnsToList() {
        assertDetailSwipeReturnsToList(from: "plan")
    }

    func testRightSwipeOnDetailContentReturnsToList() {
        assertDetailSwipeReturnsToList(from: "content")
    }

    func testRightSwipeOnDetailHeaderReturnsToList() {
        assertDetailSwipeReturnsToList(from: "header")
    }

    func testRightSwipeOnDetailBottomBlankReturnsToList() {
        assertDetailSwipeReturnsToList(from: "bottom")
    }

    func testExpandedDaySwipeDoesNotNavigateUnderlyingDrawer() {
        let app = launch(expandedMode: "timeline")
        element(app, "calendar-drawer-plan-\(sourceID)").tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        app.buttons["calendar-drawer-open-timeline"].tap()
        visibleDayTimeline(app).swipeRight()
        assertExpandedDate(app, Calendar.current.date(byAdding: .day, value: -1, to: fixtureDay)!)
        element(app, "calendar-expanded-day-back").tap()
        XCTAssertTrue(element(app, "calendar-drawer-edit").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["当日の予定一覧に戻る"].exists)
    }

    private func assertDetailSwipeReturnsToList(from region: String) {
        let app = launch()
        let header = app.buttons["calendar-drawer-date"]
        let originalY = header.frame.minY
        let plan = element(app, "calendar-drawer-plan-\(sourceID)")
        plan.tap()
        let editor = element(app, "calendar-drawer-edit")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let frame: CGRect
        switch region {
        case "plan": frame = plan.frame
        case "header": frame = header.frame
        case "bottom":
            let scroll = app.scrollViews.matching(identifier: "calendar-drawer-scroll").firstMatch
            let bottomOfButtons = max(element(app, "calendar-drawer-copy").frame.maxY,
                                      element(app, "calendar-drawer-move").frame.maxY)
            let blankY = min(scroll.frame.maxY - 32, app.frame.maxY - 38)
            XCTAssertGreaterThan(blankY, bottomOfButtons + 4, "Start in blank space below the controls")
            frame = CGRect(x: 30, y: blankY, width: 250, height: 0)
        default: frame = editor.frame
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: max(frame.minX + 20, 50), dy: frame.midY))
        origin.press(forDuration: 0.01, thenDragTo: origin.withOffset(CGVector(dx: 180, dy: 0)),
            withVelocity: XCUIGestureVelocity(rawValue: 700), thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["calendar-open-presets"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(editor.exists)
        XCTAssertFalse(app.buttons["当日の予定一覧に戻る"].exists)
        XCTAssertEqual(header.frame.minY, originalY, accuracy: 2)
        XCTAssertTrue(plan.exists)
        keepScreenshot(app, name: "詳細の\(region)から右スワイプで一覧へ戻る")
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
        let scroll = app.scrollViews.matching(identifier: "calendar-drawer-scroll").firstMatch
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

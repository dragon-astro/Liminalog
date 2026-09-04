import CoreGraphics
import Testing
@testable import Liminalog

@Suite("Timeline drag policy")
struct TimelineDragPolicyTests {
    @Test("日間・週間の時刻ガターは省幅の整数ラベルを共有する")
    func timelineHourAxisUsesCompactWholeHourLabels() {
        #expect(TimelineHourAxisMetrics.columnWidth == 32)
        #expect(TimelineHourAxisMetrics.label(for: 0) == "0")
        #expect(TimelineHourAxisMetrics.label(for: 9) == "9")
        #expect(TimelineHourAxisMetrics.label(for: 23) == "23")
    }

    @MainActor
    @Test("プリセットのUIWindow座標は日間・週間共通で表示中タイムライン座標へ変換する")
    func presetDrawerMapsToActiveTimelineCoordinates() throws {
        let frame = CGRect(x: 24, y: 180, width: 360, height: 620)
        let location = try #require(TimelinePlanPresetInteractionCoordinator.localLocation(
            CGPoint(x: 204, y: 490),
            in: frame
        ))
        let rightLocation = try #require(TimelinePlanPresetInteractionCoordinator.localLocation(
            CGPoint(x: 374, y: 490),
            in: frame
        ))

        #expect(location == CGPoint(x: 180, y: 310))
        #expect(rightLocation == CGPoint(x: 350, y: 310))
        #expect(TimelinePlanPresetInteractionCoordinator.localLocation(nil, in: frame) == nil)
        #expect(TimelinePlanPresetInteractionCoordinator.localLocation(
            CGPoint(x: 204, y: 490),
            in: nil
        ) == nil)
    }

    @Test("プリセット配置は各zoomの実表示content位置から同じ指位置を時刻へ戻す")
    func presetPlacementUsesLiveContentFrameAtEveryZoomTier() {
        let viewportMinY: CGFloat = 180
        let timelineTopInset: CGFloat = 30
        let targetMinute = 10 * 60 + 15

        for scale in DayTimelineZoomPolicy.supportedScales {
            let axisMap = TimelineAxisMap(
                hourHeight: DayTimelineZoomPolicy.hourHeight(for: scale),
                intervals: [TimelineAxisInterval(startMinute: 600, endMinute: 610)],
                minimumIntervalHeight: 18
            )
            let scrollY = max(0, axisMap.y(forMinute: targetMinute) - 220)
            let contentFrameMinY = viewportMinY - scrollY
            let windowFingerY = contentFrameMinY
                + timelineTopInset
                + axisMap.y(forMinute: targetMinute)
            let contentY = TimelinePlanPresetPlacementGeometry.axisY(
                windowFingerY: windowFingerY,
                contentFrameMinY: contentFrameMinY,
                timelineTopInset: timelineTopInset
            )

            #expect(abs(axisMap.minute(atY: contentY) - CGFloat(targetMinute)) < 0.001)
        }
    }

    @Test("同じsnap区間でもプレビューカードは指と同じpoint量だけ連続移動する")
    func presetPreviewMovesContinuouslyInsideOneSnapStep() {
        let first = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: 300,
            cardHeight: 120,
            viewportHeight: 800
        )
        let second = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: 301,
            cardHeight: 120,
            viewportHeight: 800
        )

        #expect(second - first == 1)
    }

    @Test("プリセットカードは下端付近を指で掴む")
    func presetPreviewUsesBottomEdgeGrip() {
        let top = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: 300,
            cardHeight: 120,
            viewportHeight: 800
        )

        #expect(top == 172)
        #expect(top + 120 == 292)
    }

    @Test("プレビューカード全体を24時側の表示領域内に保つ")
    func presetPreviewNeverExtendsBelowViewport() {
        let top = TimelinePlanPresetPlacementGeometry.previewTopY(
            fingerY: 900,
            cardHeight: 180,
            viewportHeight: 800
        )

        #expect(top == 620)
        #expect(top + 180 == 800)
    }

    @Test("precisionは15分を標準に5分と1分を選べる")
    func supportedPrecisions() {
        #expect(TimelineSnapPrecision.allCases.map(\.minutes) == [15, 5, 1])
        #expect(TimelineSnapPrecision.sliderOptions.map(\.minutes) == [1, 5, 15])
        #expect(TimelineSnapPrecision.quarterHour.minutes == 15)
        #expect(TimelineSnapPrecision.normalized(minutes: 5) == .fiveMinutes)
        #expect(TimelineSnapPrecision.normalized(minutes: 7) == .quarterHour)
    }

    @Test("刻み幅を大きくした後は差分ではなく時刻をきりのよい値へ揃える")
    func alignsOffGridOriginalMinuteToClockGridAfterMovement() {
        #expect(TimelineSnapPolicy.alignedMinute(
            originalMinute: 29,
            relativeDelta: 5,
            precision: .fiveMinutes
        ) == 35)
        #expect(TimelineSnapPolicy.alignedMinute(
            originalMinute: 29,
            relativeDelta: -5,
            precision: .fiveMinutes
        ) == 25)
        #expect(TimelineSnapPolicy.alignedMinute(
            originalMinute: 29,
            relativeDelta: 15,
            precision: .quarterHour
        ) == 45)
    }

    @Test("未操作時は刻み外の元時刻を勝手に移動しない")
    func zeroMovementPreservesOffGridOriginalMinute() {
        #expect(TimelineSnapPolicy.alignedMinute(
            originalMinute: 29,
            relativeDelta: 0,
            precision: .fiveMinutes
        ) == 29)
    }

    @Test("固定global座標anchorから未丸め差分を計算して最後に一度だけ量子化する")
    func derivesEveryFrameFromFixedGlobalAnchor() {
        var session = TimelineDragSession(startGlobalY: 200, hourHeight: 60)

        #expect(session.update(currentGlobalY: 207, precision: .quarterHour) == 0)
        #expect(session.update(currentGlobalY: 210, precision: .quarterHour) == 15)
        #expect(session.update(currentGlobalY: 230, precision: .quarterHour) == 30)
        #expect(session.rawMinuteDelta == 30)
    }

    @Test("15・5・1分は同じ指位置を元anchorから各刻みへ量子化する")
    func everyPrecisionUsesTheSameAnchor() {
        var session = TimelineDragSession(startGlobalY: 100, hourHeight: 60)

        #expect(session.update(currentGlobalY: 112, precision: .quarterHour) == 15)
        #expect(session.update(currentGlobalY: 112, precision: .fiveMinutes) == 10)
        #expect(session.update(currentGlobalY: 112, precision: .oneMinute) == 12)
    }

    @Test("全zoom tierで同じ分数に必要なpointだけが変わり遠距離へ飛ばない")
    func respectsEveryZoomTier() {
        for scale in DayTimelineZoomPolicy.supportedScales {
            let hourHeight = DayTimelineZoomPolicy.hourHeight(for: scale)
            var session = TimelineDragSession(startGlobalY: 400, hourHeight: hourHeight)
            let twelveMinutesInPoints = hourHeight * 12 / 60

            #expect(session.update(
                currentGlobalY: 400 + twelveMinutesInPoints,
                precision: .oneMinute
            ) == 12)
        }
    }

    @Test("同方向の入力では量子化後の時刻が逆行しない")
    func monotonicInputNeverMovesBackward() {
        var session = TimelineDragSession(startGlobalY: 0, hourHeight: 38)
        var previous = Int.min

        for point in stride(from: CGFloat(0), through: 80, by: 0.25) {
            let current = session.update(currentGlobalY: point, precision: .fiveMinutes)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test("境界付近の微小な指ぶれでは隣接snapを往復しない")
    func hysteresisPreventsBoundaryJitter() {
        var session = TimelineDragSession(startGlobalY: 0, hourHeight: 60)

        #expect(session.update(currentGlobalY: 10, precision: .quarterHour) == 15)
        #expect(session.update(currentGlobalY: 7.4, precision: .quarterHour) == 15)
        #expect(session.update(currentGlobalY: 7.6, precision: .quarterHour) == 15)
        #expect(session.update(currentGlobalY: 4.9, precision: .quarterHour) == 0)
    }

    @Test("数pointの移動は現在zoomに比例し15分刻みで遠距離snapしない")
    func aFewPointsCannotJumpFarAway() {
        let hourHeight = DayTimelineZoomPolicy.hourHeight(for: 0.75)
        var session = TimelineDragSession(startGlobalY: 500, hourHeight: hourHeight)

        let result = session.update(currentGlobalY: 503, precision: .quarterHour)

        #expect(abs(result) <= 15)
        #expect(abs(session.rawMinuteDelta) < 7)
    }

    @Test("到達限界で飽和すると超過量を溜めず逆方向の次snapから戻る")
    func saturationDiscardsUnreachableOvershoot() {
        var session = TimelineDragSession(startGlobalY: 200, hourHeight: 60)

        #expect(session.update(currentGlobalY: 80, precision: .quarterHour) == -120)
        session.saturate(currentGlobalY: 80, appliedMinuteDelta: -60)

        #expect(session.rawMinuteDelta == -60)
        #expect(session.update(currentGlobalY: 90, precision: .quarterHour) == -45)
    }

    @Test("resize hit領域は見えるgrip幅かblock幅の小さい方で隣へ侵入しない")
    func resizeHitRegionNeverIntrudesIntoNeighboringBody() {
        let regular = TimelineResizeHitPolicy.horizontalRegion(
            blockMinX: 100,
            blockWidth: 180,
            timelineMinX: 50,
            timelineMaxX: 390,
            preferredGripWidth: 70
        )
        #expect(regular.minX == 155)
        #expect(regular.width == 70)
        #expect(!regular.contains(x: 154.9))
        #expect(!regular.contains(x: 225.1))

        let narrow = TimelineResizeHitPolicy.horizontalRegion(
            blockMinX: 280,
            blockWidth: 42,
            timelineMinX: 50,
            timelineMaxX: 390,
            preferredGripWidth: 70
        )
        #expect(narrow.minX == 280)
        #expect(narrow.width == 42)
        #expect(!narrow.contains(x: 279.9))
        #expect(!narrow.contains(x: 322.1))
    }
}

import CoreGraphics
import Testing
@testable import Liminalog

@Suite("Timeline drag policy")
struct TimelineDragPolicyTests {
    @Test("precisionは15分を標準に5分と1分を選べる")
    func supportedPrecisions() {
        #expect(TimelineSnapPrecision.allCases.map(\.minutes) == [15, 5, 1])
        #expect(TimelineSnapPrecision.quarterHour.minutes == 15)
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

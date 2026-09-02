import CoreGraphics
import Testing
@testable import Liminalog

@Suite
struct TimelineAxisMapTests {
    @Test
    func linearAxisMatchesTheBaseHourHeightWithoutIntervals() {
        let axis = TimelineAxisMap(
            hourHeight: 60,
            intervals: [],
            minimumIntervalHeight: 18
        )

        #expect(abs(axis.y(forMinute: 60) - 60) < 0.0001)
        #expect(abs(axis.y(forMinute: 24 * 60) - 24 * 60) < 0.0001)
        #expect(abs(axis.minute(atY: 90) - 90) < 0.0001)
    }

    @Test
    func consecutiveShortIntervalsEachReceiveTheMinimumHeight() {
        let axis = TimelineAxisMap(
            hourHeight: 30,
            intervals: [
                .init(startMinute: 60, endMinute: 65),
                .init(startMinute: 65, endMinute: 70),
                .init(startMinute: 70, endMinute: 75)
            ],
            minimumIntervalHeight: 18
        )

        #expect(abs(axis.height(startMinute: 60, endMinute: 65) - 18) < 0.0001)
        #expect(abs(axis.height(startMinute: 65, endMinute: 70) - 18) < 0.0001)
        #expect(abs(axis.height(startMinute: 70, endMinute: 75) - 18) < 0.0001)
    }

    @Test
    func overlappingIntervalsShareExpandedAxisSpace() {
        let axis = TimelineAxisMap(
            hourHeight: 60,
            intervals: [
                .init(startMinute: 0, endMinute: 10),
                .init(startMinute: 5, endMinute: 15)
            ],
            minimumIntervalHeight: 18
        )

        #expect(abs(axis.height(startMinute: 0, endMinute: 10) - 18) < 0.0001)
        #expect(abs(axis.height(startMinute: 5, endMinute: 15) - 18) < 0.0001)
        #expect(abs(axis.y(forMinute: 15) - 27) < 0.0001)
    }

    @Test
    func integerMinutesRoundTripAcrossExpandedRanges() {
        let axis = TimelineAxisMap(
            hourHeight: 38,
            intervals: [
                .init(startMinute: 120, endMinute: 121),
                .init(startMinute: 121, endMinute: 126),
                .init(startMinute: 600, endMinute: 660)
            ],
            minimumIntervalHeight: 18
        )

        for minute in 0...TimelineAxisMap.minutesPerDay {
            let restored = axis.minute(atY: axis.y(forMinute: minute))
            #expect(abs(restored - CGFloat(minute)) < 0.0001)
        }
    }

    @Test
    func mappedDragUsesTheLocalAxisSlopeAndCanReverseAfterSaturation() {
        let axis = TimelineAxisMap(
            hourHeight: 60,
            intervals: [.init(startMinute: 100, endMinute: 105)],
            minimumIntervalHeight: 20
        )
        var session = TimelineAxisDragSession(
            startGlobalY: 200,
            originalMinute: 100,
            axisMap: axis
        )

        #expect(session.update(currentGlobalY: 220, precision: .oneMinute) == 5)
        session.saturate(currentGlobalY: 220, appliedMinuteDelta: 3)
        #expect(session.update(currentGlobalY: 216, precision: .oneMinute) == 2)
    }
}

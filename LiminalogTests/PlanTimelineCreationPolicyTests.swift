import Foundation
import Testing
@testable import Liminalog

@Suite("PlanTimelineCreationPolicy")
struct PlanTimelineCreationPolicyTests {
    private func interval(_ start: Int, _ end: Int) -> PlanTimelineInterval {
        PlanTimelineInterval(id: UUID(), startMinute: start, endMinute: end)
    }

    @Test("長押し直後は現在の最短時間を確保する", arguments: [1, 5, 15])
    func minimumRange(step: Int) {
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 540,
                                               minimumDuration: step, intervals: []) == .init(start: 540, end: 540 + step))
    }

    @Test("上下へ引っ張り、既存の予定の手前で止まる")
    func bothDirectionsStopAtNeighbors() {
        let occupied = [interval(420, 480), interval(660, 720)]
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 800,
                                               minimumDuration: 15, intervals: occupied) == .init(start: 540, end: 660))
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 200,
                                               minimumDuration: 15, intervals: occupied) == .init(start: 480, end: 540))
    }

    @Test("0時と24時の外へはみ出さない")
    func dayEdges() {
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 30, currentMinute: -60,
                                               minimumDuration: 15, intervals: []) == .init(start: 0, end: 30))
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 1410, currentMinute: 1500,
                                               minimumDuration: 15, intervals: []) == .init(start: 1410, end: 1440))
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 1440, currentMinute: 1440,
                                               minimumDuration: 15, intervals: []) == nil)
    }

    @Test("既存予定の内部や最短時間未満の空きには作成しない")
    func rejectsBlockedAnchors() {
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 720,
                                               minimumDuration: 15, intervals: [interval(530, 600)]) == nil)
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 720,
                                               minimumDuration: 15, intervals: [interval(545, 600)]) == nil)
    }

    @Test("隣接境界では空いている方向にだけ作成する")
    func adjacentBoundary() {
        let occupied = [interval(540, 600)]
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 500,
                                               minimumDuration: 15, intervals: occupied) == .init(start: 500, end: 540))
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 540, currentMinute: 620,
                                               minimumDuration: 15, intervals: occupied) == nil)
        #expect(PlanTimelineCreationPolicy.range(anchorMinute: 600, currentMinute: 650,
                                               minimumDuration: 15, intervals: occupied) == .init(start: 600, end: 650))
    }
}

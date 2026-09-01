import Foundation
import SwiftData
import Testing
@testable import Liminalog

@Suite("PlanTimelineRescheduler")
struct PlanTimelineReschedulerTests {
    @Test("週間予定の差分は提案値ではなく保存済み位置との比較で抽出する")
    func changedIntervalsKeepsEditingPlanAndPushedNeighbours() {
        let upperID = UUID()
        let editingID = UUID()
        let originals = [
            upperID: PlanTimelineInterval(id: upperID, startMinute: 0, endMinute: 60),
            editingID: PlanTimelineInterval(id: editingID, startMinute: 60, endMinute: 120)
        ]

        let normalMove = PlanTimelineRescheduler.changedIntervals(
            in: [
                originals[upperID]!,
                PlanTimelineInterval(id: editingID, startMinute: 75, endMinute: 135)
            ],
            comparedTo: originals
        )
        #expect(normalMove.map(\.id) == [editingID])

        let pushedMove = PlanTimelineRescheduler.changedIntervals(
            in: [
                PlanTimelineInterval(id: upperID, startMinute: 15, endMinute: 75),
                PlanTimelineInterval(id: editingID, startMinute: 75, endMinute: 135)
            ],
            comparedTo: originals
        )
        #expect(Set(pushedMove.map(\.id)) == Set([upperID, editingID]))
    }

    @Test("開始ハンドルは終了時刻を越えず最小幅で止まる")
    func startHandleStopsAtMinimumDuration() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .start,
            delta: 90
        )

        #expect(result.startMinute == 10 * 60 + 45)
        #expect(result.endMinute == 11 * 60)
        #expect(result.pushDirection == .later)
        #expect(result.feedbackMinute == 10 * 60 + 45)
    }

    @Test("終了ハンドルは開始時刻を越えず最小幅で止まる")
    func endHandleStopsAtMinimumDuration() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -90
        )

        #expect(result.startMinute == 10 * 60)
        #expect(result.endMinute == 10 * 60 + 15)
        #expect(result.pushDirection == .earlier)
        #expect(result.feedbackMinute == 10 * 60 + 15)
    }

    @Test("ハンドルの超過移動量を保持し指が境界へ戻るまで逆方向へ動かない")
    func resizeHandlePreservesOvershootUntilFingerReturnsToBoundary() {
        let overshot = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -2 * 60
        )
        let partiallyReturned = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -90
        )
        let returnedInsideRange = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -30
        )

        #expect(overshot.endMinute == 10 * 60 + 15)
        #expect(partiallyReturned.endMinute == 10 * 60 + 15)
        #expect(returnedInsideRange.endMinute == 10 * 60 + 30)
    }

    @Test("ハンドルの最小長は選択した移動幅に一致する")
    func resizeMinimumDurationMatchesSnapPrecision() {
        let oneMinute = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -2 * 60,
            minimumDuration: 1
        )
        let fiveMinutes = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .start,
            delta: 2 * 60,
            minimumDuration: 5
        )

        #expect(oneMinute.startMinute == 10 * 60)
        #expect(oneMinute.endMinute == 10 * 60 + 1)
        #expect(fiveMinutes.startMinute == 10 * 60 + 55)
        #expect(fiveMinutes.endMinute == 11 * 60)
    }

    @Test("開始ハンドルは日付終端を越えず最小幅を保つ")
    func startHandleNearDayEndKeepsMinimumBlockInsideDay() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 23 * 60 + 20,
            originalEndMinute: 23 * 60 + 50,
            edge: .start,
            delta: 60
        )

        #expect(result.startMinute == 23 * 60 + 35)
        #expect(result.endMinute == 23 * 60 + 50)
        #expect(result.pushDirection == .later)
        #expect(result.feedbackMinute == 23 * 60 + 35)
    }

    @Test("終了ハンドルは日付始端を越えず最小幅を保つ")
    func endHandleNearDayStartKeepsMinimumBlockInsideDay() {
        let result = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10,
            originalEndMinute: 40,
            edge: .end,
            delta: -60
        )

        #expect(result.startMinute == 10)
        #expect(result.endMinute == 25)
        #expect(result.pushDirection == .earlier)
        #expect(result.feedbackMinute == 25)
    }

    @Test("予定がない方向へ終了ハンドルを伸ばすと日付終端まで伸ばせる")
    func endHandleCanExpandToDayEndWhenSpaceIsAvailable() {
        let planID = UUID()
        let resize = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 21 * 60,
            originalEndMinute: 22 * 60,
            edge: .end,
            delta: 3 * 60
        )
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: planID, startMinute: 21 * 60, endMinute: 22 * 60)
            ],
            editingID: planID,
            proposedStartMinute: resize.startMinute,
            proposedEndMinute: resize.endMinute,
            pushDirection: resize.pushDirection
        )

        let item = resolved?.first
        #expect(item?.startMinute == 21 * 60)
        #expect(item?.endMinute == 24 * 60)
    }

    @Test("予定がない方向へ開始ハンドルを伸ばすと日付始端まで伸ばせる")
    func startHandleCanExpandToDayStartWhenSpaceIsAvailable() {
        let planID = UUID()
        let resize = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 2 * 60,
            originalEndMinute: 3 * 60,
            edge: .start,
            delta: -3 * 60
        )
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: planID, startMinute: 2 * 60, endMinute: 3 * 60)
            ],
            editingID: planID,
            proposedStartMinute: resize.startMinute,
            proposedEndMinute: resize.endMinute,
            pushDirection: resize.pushDirection
        )

        let item = resolved?.first
        #expect(item?.startMinute == 0)
        #expect(item?.endMinute == 3 * 60)
    }

    @Test("終了ハンドルで次の予定にぶつかると後続予定を押す")
    func pushesLaterPlansWhenEndHandleExpands() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 30,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 9 * 60)
        #expect(items[firstID]?.endMinute == 10 * 60 + 30)
        #expect(items[secondID]?.startMinute == 10 * 60 + 30)
        #expect(items[secondID]?.endMinute == 11 * 60 + 30)
    }

    @Test("後方への玉突きは密集した複数予定へ連鎖する")
    func pushingLaterCascadesThroughMultiplePlans() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 10 * 60 + 30),
                PlanTimelineInterval(id: thirdID, startMinute: 10 * 60 + 30, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 15,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 9 * 60)
        #expect(items[firstID]?.endMinute == 10 * 60 + 15)
        #expect(items[secondID]?.startMinute == 10 * 60 + 15)
        #expect(items[secondID]?.endMinute == 10 * 60 + 45)
        #expect(items[thirdID]?.startMinute == 10 * 60 + 45)
        #expect(items[thirdID]?.endMinute == 11 * 60 + 15)
    }

    @Test("開始ハンドルで前の予定にぶつかると前方予定を押し上げる")
    func pushesEarlierPlansWhenStartHandleExpands() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 9 * 60 + 30,
            proposedEndMinute: 11 * 60,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 8 * 60 + 30)
        #expect(items[firstID]?.endMinute == 9 * 60 + 30)
        #expect(items[secondID]?.startMinute == 9 * 60 + 30)
        #expect(items[secondID]?.endMinute == 11 * 60)
    }

    @Test("前方への玉突きは密集した複数予定へ連鎖する")
    func pushingEarlierCascadesThroughMultiplePlans() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 9 * 60 + 30),
                PlanTimelineInterval(id: secondID, startMinute: 9 * 60 + 30, endMinute: 10 * 60),
                PlanTimelineInterval(id: thirdID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: thirdID,
            proposedStartMinute: 9 * 60 + 45,
            proposedEndMinute: 11 * 60,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 8 * 60 + 45)
        #expect(items[firstID]?.endMinute == 9 * 60 + 15)
        #expect(items[secondID]?.startMinute == 9 * 60 + 15)
        #expect(items[secondID]?.endMinute == 9 * 60 + 45)
        #expect(items[thirdID]?.startMinute == 9 * 60 + 45)
        #expect(items[thirdID]?.endMinute == 11 * 60)
    }

    @Test("玉突き後に重ならない位置へ戻すと押された予定も元の位置へ戻る")
    func pushedPlanReturnsWhenEditingPlanMovesBackToNonCollision() {
        let firstID = UUID()
        let secondID = UUID()
        let baseline = [
            PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
            PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
        ]
        let pushed = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 30,
            pushDirection: .later
        )
        let restored = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: firstID,
            proposedStartMinute: 8 * 60,
            proposedEndMinute: 9 * 60,
            pushDirection: .earlier
        )

        let pushedItems = Dictionary(uniqueKeysWithValues: (pushed ?? []).map { ($0.id, $0) })
        let restoredItems = Dictionary(uniqueKeysWithValues: (restored ?? []).map { ($0.id, $0) })
        #expect(pushedItems[secondID]?.startMinute == 10 * 60 + 30)
        #expect(restoredItems[firstID]?.startMinute == 8 * 60)
        #expect(restoredItems[firstID]?.endMinute == 9 * 60)
        #expect(restoredItems[secondID]?.startMinute == 10 * 60)
        #expect(restoredItems[secondID]?.endMinute == 11 * 60)
    }

    @Test("予定を後ろへ移動して次の予定をまたいでも玉突きで押す")
    func movingPlanLaterAcrossNextPlanPushesCollision() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 10 * 60 + 30,
            proposedEndMinute: 11 * 60 + 30,
            pushDirection: .later
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 10 * 60 + 30)
        #expect(items[firstID]?.endMinute == 11 * 60 + 30)
        #expect(items[secondID]?.startMinute == 11 * 60 + 30)
        #expect(items[secondID]?.endMinute == 12 * 60 + 30)
    }

    @Test("予定を前へ移動して前の予定をまたいでも玉突きで押し上げる")
    func movingPlanEarlierAcrossPreviousPlanPushesCollision() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 8 * 60 + 30,
            proposedEndMinute: 9 * 60 + 30,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 7 * 60 + 30)
        #expect(items[firstID]?.endMinute == 8 * 60 + 30)
        #expect(items[secondID]?.startMinute == 8 * 60 + 30)
        #expect(items[secondID]?.endMinute == 9 * 60 + 30)
    }

    @Test("後方への玉突きが日付終端を超える配置は拒否する")
    func pushingLaterPastDayEndFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 22 * 60 + 30, endMinute: 23 * 60 + 30),
                PlanTimelineInterval(id: secondID, startMinute: 23 * 60 + 30, endMinute: 24 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 22 * 60 + 30,
            proposedEndMinute: 23 * 60 + 45,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }

    @Test("前方への玉突きが日付始端を超える配置は拒否する")
    func pushingEarlierPastDayStartFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 0, endMinute: 30),
                PlanTimelineInterval(id: secondID, startMinute: 30, endMinute: 90)
            ],
            editingID: secondID,
            proposedStartMinute: 15,
            proposedEndMinute: 75,
            pushDirection: .earlier
        )

        #expect(resolved == nil)
    }

    @Test("移動先でロック済み予定を押す必要がある配置は拒否する")
    func movingAcrossLockedPlanFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60, isLocked: true)
            ],
            editingID: firstID,
            proposedStartMinute: 10 * 60 + 30,
            proposedEndMinute: 11 * 60 + 30,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }

    @Test("一度拒否された後でも元の基準から有効な位置へ戻せる")
    func canRecoverFromFailedResolveUsingOriginalBaseline() {
        let firstID = UUID()
        let secondID = UUID()
        let baseline = [
            PlanTimelineInterval(id: firstID, startMinute: 22 * 60, endMinute: 23 * 60),
            PlanTimelineInterval(id: secondID, startMinute: 23 * 60, endMinute: 24 * 60)
        ]
        let rejected = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: firstID,
            proposedStartMinute: 22 * 60,
            proposedEndMinute: 23 * 60 + 30,
            pushDirection: .later
        )
        let recovered = PlanTimelineRescheduler.resolve(
            items: baseline,
            editingID: firstID,
            proposedStartMinute: 21 * 60,
            proposedEndMinute: 22 * 60,
            pushDirection: .earlier
        )

        let items = Dictionary(uniqueKeysWithValues: (recovered ?? []).map { ($0.id, $0) })
        #expect(rejected == nil)
        #expect(items[firstID]?.startMinute == 21 * 60)
        #expect(items[firstID]?.endMinute == 22 * 60)
        #expect(items[secondID]?.startMinute == 23 * 60)
        #expect(items[secondID]?.endMinute == 24 * 60)
    }

    @Test("速い終了ハンドル操作で到達限界を越えても一回の補正で有効位置へ収める")
    func clampedEndResizeStopsAtReachableCollisionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 18 * 60, endMinute: 19 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 23 * 60, endMinute: 24 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 18 * 60,
            proposedEndMinute: 24 * 60,
            pushDirection: .later,
            adjustment: .resizeEnd
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 18 * 60)
        #expect(items[firstID]?.endMinute == 23 * 60)
        #expect(items[secondID]?.startMinute == 23 * 60)
        #expect(items[secondID]?.endMinute == 24 * 60)
    }

    @Test("速い開始ハンドル操作で到達限界を越えても一回の補正で有効位置へ収める")
    func clampedStartResizeStopsAtReachableCollisionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 0, endMinute: 60),
                PlanTimelineInterval(id: secondID, startMinute: 5 * 60, endMinute: 6 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 0,
            proposedEndMinute: 6 * 60,
            pushDirection: .earlier,
            adjustment: .resizeStart
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 0)
        #expect(items[firstID]?.endMinute == 60)
        #expect(items[secondID]?.startMinute == 60)
        #expect(items[secondID]?.endMinute == 6 * 60)
    }

    @Test("終了ハンドルを上へ越境しても上側予定を判定せず最小長で止まる")
    func crossedEndResizeStopsBeforeEarlierPlan() {
        let upperID = UUID()
        let editingID = UUID()
        let resize = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 60,
            originalEndMinute: 120,
            edge: .end,
            delta: -120
        )
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: upperID, startMinute: 0, endMinute: 60),
                PlanTimelineInterval(id: editingID, startMinute: 60, endMinute: 120)
            ],
            editingID: editingID,
            proposedStartMinute: resize.startMinute,
            proposedEndMinute: resize.endMinute,
            pushDirection: resize.pushDirection,
            adjustment: .resizeEnd
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[upperID]?.startMinute == 0)
        #expect(items[upperID]?.endMinute == 60)
        #expect(items[editingID]?.startMinute == 60)
        #expect(items[editingID]?.endMinute == 75)
    }

    @Test("速い後方移動で到達限界を越えても一回の補正で有効位置へ収める")
    func clampedMoveLaterStopsAtReachableCollisionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 18 * 60, endMinute: 19 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 23 * 60, endMinute: 24 * 60)
            ],
            editingID: firstID,
            proposedStartMinute: 23 * 60,
            proposedEndMinute: 24 * 60,
            pushDirection: .later,
            adjustment: .move
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 22 * 60)
        #expect(items[firstID]?.endMinute == 23 * 60)
        #expect(items[secondID]?.startMinute == 23 * 60)
        #expect(items[secondID]?.endMinute == 24 * 60)
    }

    @Test("速い前方移動で到達限界を越えても一回の補正で有効位置へ収める")
    func clampedMoveEarlierStopsAtReachableCollisionLimit() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 0, endMinute: 60),
                PlanTimelineInterval(id: secondID, startMinute: 5 * 60, endMinute: 6 * 60)
            ],
            editingID: secondID,
            proposedStartMinute: 0,
            proposedEndMinute: 60,
            pushDirection: .earlier,
            adjustment: .move
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[firstID]?.startMinute == 0)
        #expect(items[firstID]?.endMinute == 60)
        #expect(items[secondID]?.startMinute == 60)
        #expect(items[secondID]?.endMinute == 2 * 60)
    }

    @Test("終了ハンドルを上側予定へ越えて動かしても最小長で止まり入れ替わらない")
    func endHandleCannotCrossIntoEarlierPlan() {
        let upperID = UUID()
        let editingID = UUID()
        let resize = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 10 * 60,
            originalEndMinute: 11 * 60,
            edge: .end,
            delta: -2 * 60
        )
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: upperID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: editingID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: editingID,
            proposedStartMinute: resize.startMinute,
            proposedEndMinute: resize.endMinute,
            pushDirection: resize.pushDirection,
            adjustment: .resizeEnd
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[upperID]?.startMinute == 9 * 60)
        #expect(items[upperID]?.endMinute == 10 * 60)
        #expect(items[editingID]?.startMinute == 10 * 60)
        #expect(items[editingID]?.endMinute == 10 * 60 + 15)
    }

    @Test("開始ハンドルを下側予定へ越えて動かしても最小長で止まり入れ替わらない")
    func startHandleCannotCrossIntoLaterPlan() {
        let editingID = UUID()
        let lowerID = UUID()
        let resize = PlanTimelineRescheduler.resizedBounds(
            originalStartMinute: 9 * 60,
            originalEndMinute: 10 * 60,
            edge: .start,
            delta: 2 * 60
        )
        let resolved = PlanTimelineRescheduler.resolveClamped(
            items: [
                PlanTimelineInterval(id: editingID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: lowerID, startMinute: 10 * 60, endMinute: 11 * 60)
            ],
            editingID: editingID,
            proposedStartMinute: resize.startMinute,
            proposedEndMinute: resize.endMinute,
            pushDirection: resize.pushDirection,
            adjustment: .resizeStart
        )

        let items = Dictionary(uniqueKeysWithValues: (resolved ?? []).map { ($0.id, $0) })
        #expect(items[editingID]?.startMinute == 9 * 60 + 45)
        #expect(items[editingID]?.endMinute == 10 * 60)
        #expect(items[lowerID]?.startMinute == 10 * 60)
        #expect(items[lowerID]?.endMinute == 11 * 60)
    }

    @Test("ロック済み予定を押す必要がある配置は拒否する")
    func lockedCollisionFails() {
        let firstID = UUID()
        let secondID = UUID()
        let resolved = PlanTimelineRescheduler.resolve(
            items: [
                PlanTimelineInterval(id: firstID, startMinute: 9 * 60, endMinute: 10 * 60),
                PlanTimelineInterval(id: secondID, startMinute: 10 * 60, endMinute: 11 * 60, isLocked: true)
            ],
            editingID: firstID,
            proposedStartMinute: 9 * 60,
            proposedEndMinute: 10 * 60 + 15,
            pushDirection: .later
        )

        #expect(resolved == nil)
    }
}

@MainActor
@Suite("PlanStore timeline scheduling")
struct PlanStoreTimelineSchedulingTests {
    @Test("未来日の複数予定を一括で重ならない配置へ保存できる")
    func batchScheduleChangesCanMoveMultipleFuturePlans() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))
        let firstStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 9)))
        let firstEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let secondStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10)))
        let secondEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11)))

        #expect(store.addPlanBlock(category: nil, title: "前半", startTime: firstStart, endTime: firstEnd))
        #expect(store.addPlanBlock(category: nil, title: "後半", startTime: secondStart, endTime: secondEnd))
        let plans = store.allPlannedBlocks().sorted { $0.startTime < $1.startTime }
        let first = try #require(plans.first)
        let second = try #require(plans.dropFirst().first)
        let movedFirstEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 10, minute: 30)))
        let movedSecondStart = movedFirstEnd
        let movedSecondEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 11, minute: 30)))

        #expect(store.savePlanScheduleChanges([
            .init(plan: first, startTime: firstStart, endTime: movedFirstEnd),
            .init(plan: second, startTime: movedSecondStart, endTime: movedSecondEnd)
        ]))

        #expect(first.endTime == movedFirstEnd)
        #expect(second.startTime == movedSecondStart)
        #expect(second.endTime == movedSecondEnd)
    }

    @Test("当日の時刻指定予定は一括移動できない")
    func batchScheduleChangesRejectsLockedPlans() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 10)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 11)))
        let plan = PlanBlock(category: nil, title: "今日", startTime: start, endTime: end)
        context.insert(plan)
        try context.save()
        let store = PlanStore(modelContext: context, clock: MutableTestClock(now: now))
        let movedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 11)))
        let movedEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 12)))

        #expect(!store.savePlanScheduleChanges([
            .init(plan: plan, startTime: movedStart, endTime: movedEnd)
        ]))
        #expect(plan.startTime == start)
        #expect(plan.endTime == end)
    }
}

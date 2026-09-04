import Foundation
import Testing
@testable import Liminalog

@Suite("Month drawer motion")
struct CalendarMonthDrawerMotionTests {
    @Test("上へドラッグ中は指の移動量だけ高さが増える")
    func followsUpwardDrag() {
        #expect(CalendarMonthDrawerMotion.height(base: 320, translation: -100, compact: 320, expanded: 640) == 420)
        #expect(CalendarMonthDrawerMotion.offset(base: 320, translation: -100, compact: 320) == 0)
    }

    @Test("拡大上限を超えず、下ドラッグは通常高になってから引っ込む")
    func boundsAndDownwardOffset() {
        #expect(CalendarMonthDrawerMotion.height(base: 640, translation: -500, compact: 320, expanded: 640) == 640)
        #expect(CalendarMonthDrawerMotion.height(base: 640, translation: 400, compact: 320, expanded: 640) == 320)
        #expect(CalendarMonthDrawerMotion.offset(base: 640, translation: 400, compact: 320) == 80)
    }

    @Test("小さな動きは元の段階へ戻り、上フリックは拡大する")
    func snapDestinations() {
        #expect(destination(base: 320, translation: -10, predicted: -20) == .compact)
        #expect(destination(base: 640, translation: 10, predicted: 20) == .expanded)
        #expect(destination(base: 320, translation: -60, predicted: -240) == .expanded)
        #expect(destination(base: 640, translation: 200, predicted: 250) == .compact)
    }

    @Test("通常高から十分に下げたときだけ閉じる")
    func dismissalThreshold() {
        #expect(destination(base: 320, translation: 60, predicted: 80) == .compact)
        #expect(destination(base: 320, translation: 81, predicted: 81) == .dismissed)
        #expect(destination(base: 320, translation: 20, predicted: 180) == .dismissed)
        #expect(destination(base: 640, translation: 200, predicted: 300) == .compact)
    }

    private func destination(base: CGFloat, translation: CGFloat, predicted: CGFloat) -> CalendarMonthDrawerMotion.Destination {
        CalendarMonthDrawerMotion.destination(base: base, translation: translation, predicted: predicted, compact: 320, expanded: 640)
    }
}

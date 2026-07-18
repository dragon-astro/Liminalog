import CoreGraphics
import Testing
@testable import Liminalog

@Suite("Current chapter card compact layout")
struct CurrentChapterCardLayoutTests {
    @Test("予定なしはItem F以前の48pt高を維持する")
    func noPlanHeightRemainsCompact() {
        #expect(CurrentChapterCardLayout.cardHeight(hasCurrentPlan: false) == 48)
    }

    @Test("予定同居時も76pt高に収める")
    func planContextHeightRemainsCompact() {
        #expect(CurrentChapterCardLayout.cardHeight(hasCurrentPlan: true) == 76)
    }

    @Test("操作の見た目は28ptでもhit領域は44pt確保する")
    func compactActionsKeepAccessibleHitSize() {
        #expect(CurrentChapterCardLayout.actionVisualSize == 28)
        #expect(CurrentChapterCardLayout.actionHitSize == 44)
    }
}

import Testing
@testable import Liminalog

@Suite("LiminalogShortcutRoute")
struct LiminalogShortcutRouteTests {
    @Test("予約したルートは1回だけ消費される")
    func pendingRouteIsConsumedOnce() {
        _ = LiminalogShortcutRoute.consumePendingRoute()

        LiminalogShortcutRoute.request(.dashboard)

        #expect(LiminalogShortcutRoute.consumePendingRoute() == .dashboard)
        #expect(LiminalogShortcutRoute.consumePendingRoute() == nil)
    }
}

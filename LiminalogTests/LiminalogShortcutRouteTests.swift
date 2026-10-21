import Foundation
import Testing
@testable import Liminalog

@Suite("LiminalogShortcutRoute")
struct LiminalogShortcutRouteTests {
    @Test("予約したルートは1回だけ消費される")
    func pendingRouteIsConsumedOnce() {
        let suiteName = "LiminalogShortcutRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        LiminalogShortcutRoute.request(.dashboard, defaults: defaults)

        #expect(LiminalogShortcutRoute.consumePendingRoute(defaults: defaults, isRunningUITests: false) == .dashboard)
        #expect(LiminalogShortcutRoute.consumePendingRoute(defaults: defaults, isRunningUITests: false) == nil)
    }

    @Test("UI fixture は実データの起動先を消費しない")
    func fixtureDoesNotConsumePendingRoute() {
        let suiteName = "LiminalogShortcutRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        LiminalogShortcutRoute.request(.today, defaults: defaults)

        #expect(LiminalogShortcutRoute.consumePendingRoute(defaults: defaults, isRunningUITests: true) == nil)
        #expect(LiminalogShortcutRoute.consumePendingRoute(defaults: defaults, isRunningUITests: false) == .today)
        #expect(LiminalogShortcutRoute.consumePendingRoute(defaults: defaults, isRunningUITests: false) == nil)
    }
}

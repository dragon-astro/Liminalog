import Foundation

enum LiminalogShortcutRoute: String, CaseIterable {
    case today
    case calendar
    case dashboard
    case profile

    nonisolated private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    nonisolated private static let pendingRouteKey = "shortcut.pendingRoute"

    nonisolated static func request(
        _ route: LiminalogShortcutRoute,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        guard let defaults else {
            NSLog("Liminalog: skipped shortcut route request because app group UserDefaults was unavailable")
            return
        }
        defaults.set(route.rawValue, forKey: pendingRouteKey)
        defaults.synchronize()
    }

    nonisolated static func consumePendingRoute(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        isRunningUITests: Bool = LiminalogRuntime.isRunningUITests
    ) -> LiminalogShortcutRoute? {
        // Fixtures use an isolated model container; real shortcut requests must
        // neither redirect that launch nor be removed from the user's queue.
        guard !isRunningUITests else { return nil }
        guard let defaults else {
            NSLog("Liminalog: skipped shortcut route consumption because app group UserDefaults was unavailable")
            return nil
        }
        guard let rawValue = defaults.string(forKey: pendingRouteKey),
              let route = LiminalogShortcutRoute(rawValue: rawValue)
        else { return nil }

        defaults.removeObject(forKey: pendingRouteKey)
        return route
    }
}

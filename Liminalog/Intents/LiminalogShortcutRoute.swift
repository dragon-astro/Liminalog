import Foundation

enum LiminalogShortcutRoute: String, CaseIterable {
    case today
    case calendar
    case dashboard
    case profile

    nonisolated private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    nonisolated private static let pendingRouteKey = "shortcut.pendingRoute"

    nonisolated static func request(_ route: LiminalogShortcutRoute) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            NSLog("Liminalog: skipped shortcut route request because app group UserDefaults was unavailable")
            return
        }
        defaults.set(route.rawValue, forKey: pendingRouteKey)
        defaults.synchronize()
    }

    nonisolated static func consumePendingRoute() -> LiminalogShortcutRoute? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
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

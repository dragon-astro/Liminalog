import Foundation

enum LiminalogShortcutRoute: String, CaseIterable {
    case today
    case calendar
    case dashboard
    case profile

    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let pendingRouteKey = "shortcut.pendingRoute"

    static func request(_ route: LiminalogShortcutRoute) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(route.rawValue, forKey: pendingRouteKey)
        defaults.synchronize()
    }

    static func consumePendingRoute() -> LiminalogShortcutRoute? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let rawValue = defaults.string(forKey: pendingRouteKey),
              let route = LiminalogShortcutRoute(rawValue: rawValue)
        else { return nil }

        defaults.removeObject(forKey: pendingRouteKey)
        return route
    }
}

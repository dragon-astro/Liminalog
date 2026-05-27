import SwiftUI
import SwiftData

@main
struct LiminalogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [Category.self, CategorySet.self, Chapter.self, PlanBlock.self, VisibilityPreset.self, UserSettings.self, CalendarEventCache.self])
    }
}

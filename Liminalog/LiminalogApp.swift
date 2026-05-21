import SwiftUI
import SwiftData

@main
struct LiminalogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [Category.self, Chapter.self, VisibilityPreset.self])
    }
}

import SwiftUI
import SwiftData

@main
struct LiminalogApp: App {
    private let modelContainer = SharedModelContainer.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}

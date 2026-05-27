import SwiftUI
import SwiftData
import Foundation

@main
struct LiminalogApp: App {
    private let modelContainer: ModelContainer = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return (try? SharedModelContainer.inMemory()) ?? SharedModelContainer.shared
        }
        return SharedModelContainer.shared
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}

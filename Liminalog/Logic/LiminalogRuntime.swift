import Foundation

enum LiminalogRuntime {
    nonisolated static let isRunningUITests: Bool = {
        #if DEBUG || LIMINALOG_UI_TESTING
        ProcessInfo.processInfo.arguments.contains("-LiminalogMonthDrawerUITests")
        #else
        false
        #endif
    }()
    /// Process environment is immutable for the lifetime of the app process.
    /// Cache the XCTest check so hot paths do not rebuild the environment dictionary.
    nonisolated static let isRunningUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || isRunningUITests
}

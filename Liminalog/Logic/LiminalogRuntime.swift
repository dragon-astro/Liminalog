import Foundation

enum LiminalogRuntime {
    /// Process environment is immutable for the lifetime of the app process.
    /// Cache the XCTest check so hot paths do not rebuild the environment dictionary.
    nonisolated static let isRunningUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

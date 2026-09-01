import Foundation
import os.signpost

enum TabPerformanceDiagnostics {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "app.YasudaRyuga.Liminalog",
        category: "TabPerformance"
    )

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }

    @discardableResult
    static func measure<Value>(_ name: StaticString, operation: () -> Value) -> Value {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: signpostID)
        }
        return operation()
    }
}

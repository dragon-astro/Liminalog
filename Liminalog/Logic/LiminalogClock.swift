import Foundation

protocol LiminalogClock: Sendable {
    var now: Date { get }
}

struct SystemClock: LiminalogClock {
    nonisolated init() {}

    nonisolated var now: Date {
        Date()
    }
}

struct TestClock: LiminalogClock {
    var now: Date
}

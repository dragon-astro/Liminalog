import Foundation
import Observation

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

@Observable
@MainActor
final class TickClock {
    private let interval: TimeInterval
    private var timer: Timer?
    var now: Date

    init(now: Date = Date(), interval: TimeInterval = 1) {
        self.now = now
        self.interval = interval
    }

    func start() {
        guard timer == nil else { return }
        now = Date()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.now = Date()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

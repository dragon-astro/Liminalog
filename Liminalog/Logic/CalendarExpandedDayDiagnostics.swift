#if DEBUG || LIMINALOG_UI_TESTING
import SwiftUI
import UIKit

/// Isolated UI-test observation. Times the real button callback through UIKit presentation.
@MainActor
enum CalendarExpandedDayDiagnostics {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-LiminalogMeasureDayExpansion")
    }
    private static var startedAt: TimeInterval?
    private static var contentMilliseconds: Double = -1
    private static var evaluatedDates: Set<Date> = []
    private static var evaluations = 0

    static func begin() {
        guard isEnabled else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        contentMilliseconds = -1
        evaluatedDates = []
        evaluations = 0
    }

    static func evaluated(date: Date) {
        guard startedAt != nil else { return }
        evaluatedDates.insert(date)
        evaluations += 1
    }

    static func contentAppeared() {
        guard let startedAt, contentMilliseconds < 0 else { return }
        contentMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
    }

    static func finish() -> String {
        guard let startedAt else { return "" }
        let presented = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
        self.startedAt = nil
        return "content:\(contentMilliseconds)|presented:\(presented)|days:\(evaluatedDates.count)|bodies:\(evaluations)"
    }
}

struct CalendarExpandedDayPresentationProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "calendar-expanded-day-metric"
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let result = CalendarExpandedDayDiagnostics.finish()
            if !result.isEmpty { view.accessibilityValue = result }
        }
    }
}
#endif

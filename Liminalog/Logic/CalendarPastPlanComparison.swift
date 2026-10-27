#if DEBUG
import SwiftUI

/// Screenshot-only opacity comparison. Future colors and production settings stay unchanged.
enum CalendarPastPlanComparison {
    static let argument = "-LiminalogPastPlanComparison"
    static let variant: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-LiminalogMonthDrawerUITests"),
              let index = args.firstIndex(of: argument), args.indices.contains(index + 1),
              ["v0", "past-55", "past-50"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }()

    static let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
    static func isEnabled(in scheme: ColorScheme) -> Bool { variant != nil && scheme == .light }
    static var decorationOpacity: Double? {
        switch variant {
        case "past-55": 0.55
        case "past-50": 0.5
        default: nil
        }
    }
}
#endif

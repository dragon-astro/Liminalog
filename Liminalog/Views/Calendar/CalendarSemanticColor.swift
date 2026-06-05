import SwiftUI
import UIKit

enum CalendarSemanticColor {
    static var planFilled: Color {
        adaptive(dark: "#5FE0A8", light: "#198754")
    }

    static var planGap: Color {
        adaptive(dark: "#FF6B7A", light: "#C93C44")
    }

    static var importantPlan: Color {
        adaptive(dark: "#FFD66B", light: "#B7791F")
    }

    private static func adaptive(dark: String, light: String) -> Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

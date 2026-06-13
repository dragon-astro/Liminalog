import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum LiminalHaptics {
    static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    static func lightImpact(intensity: CGFloat = 0.7) {
        impact(.light, intensity: intensity)
    }

    static func primaryAction() {
        impact(.medium, intensity: 0.82)
    }

    static func commit() {
        notification(.success)
    }

    static func warning() {
        notification(.warning)
    }

    static func failure() {
        notification(.error)
    }

    static func tabSelection() {
        selection()
    }

    static func openSheet() {
        lightImpact(intensity: 0.55)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
        #endif
    }

    private static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        #endif
    }
}

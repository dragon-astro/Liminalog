import SwiftUI

enum LiminalTheme {
    static let canvas = Color(hex: "#0D0B16")
    static let surface = Color(hex: "#17132A")
    static let elevated = Color(hex: "#1F1A38")
    static let divider = Color(hex: "#2A2442")

    static let text = Color(hex: "#ECE8F5")
    static let secondaryText = Color(hex: "#9A93B5")
    static let tertiaryText = Color(hex: "#6E6890")

    static let primary = Color(hex: "#C9A7FF")
    static let reward = Color(hex: "#FFE3A3")
    static let dawn = Color(hex: "#FFB3C7")
    static let dusk = Color(hex: "#6B3FA0")

    static let cardGradient = LinearGradient(
        colors: [
            canvas,
            surface,
            elevated,
            Color(hex: "#231B36")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let canvasGradient = LinearGradient(
        colors: [
            Color(hex: "#0D0B16"),
            Color(hex: "#121026"),
            Color(hex: "#17132A")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func liminalAppChrome() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(LiminalTheme.primary)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
    }
}

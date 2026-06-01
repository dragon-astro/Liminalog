import SwiftUI
import UIKit

enum LiminalTheme {
    private static let duskPalette = LiminalThemePalette(
        canvas: "#0D0B16",
        surface: "#17132A",
        elevated: "#1F1A38",
        divider: "#2A2442",
        text: "#ECE8F5",
        secondaryText: "#9A93B5",
        tertiaryText: "#6E6890",
        primary: "#C9A7FF",
        reward: "#FFE3A3",
        dawn: "#FFB3C7",
        dusk: "#6B3FA0",
        gradientTop: "#0D0B16",
        gradientMiddle: "#121026",
        gradientBottom: "#17132A",
        cardBottom: "#231B36"
    )

    private static let daybreakPalette = LiminalThemePalette(
        canvas: "#F6F1F7",
        surface: "#FCF9FD",
        elevated: "#FEFCFE",
        divider: "#E6DEEC",
        text: "#2A2440",
        secondaryText: "#6A6388",
        tertiaryText: "#9A93B5",
        primary: "#7C4DD6",
        reward: "#C98A1E",
        dawn: "#FFE3EC",
        dusk: "#C7B0EA",
        gradientTop: "#F6F1F7",
        gradientMiddle: "#EBDCFA",
        gradientBottom: "#FFF0CE",
        cardBottom: "#F4ECF8"
    )

    static let canvas = token(\.canvas)
    static let surface = token(\.surface)
    static let elevated = token(\.elevated)
    static let divider = token(\.divider)

    static let text = token(\.text)
    static let secondaryText = token(\.secondaryText)
    static let tertiaryText = token(\.tertiaryText)

    static let primary = token(\.primary)
    static let reward = token(\.reward)
    static let dawn = token(\.dawn)
    static let dusk = token(\.dusk)

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                canvas,
                surface,
                elevated,
                token(\.cardBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                token(\.gradientTop),
                token(\.gradientMiddle),
                token(\.gradientBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func uiCanvas(for traits: UITraitCollection) -> UIColor {
        activePalette(for: traits).canvas.uiColor
    }

    private static func token(_ keyPath: KeyPath<LiminalThemePalette, LiminalThemeColor>) -> Color {
        Color(
            UIColor { traits in
                activePalette(for: traits)[keyPath: keyPath].uiColor
            }
        )
    }

    private static func activePalette(for traits: UITraitCollection) -> LiminalThemePalette {
        traits.userInterfaceStyle == .light ? daybreakPalette : duskPalette
    }
}

extension View {
    func liminalAppChrome() -> some View {
        self
            .tint(LiminalTheme.primary)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
    }
}

private struct LiminalThemePalette {
    let canvas: LiminalThemeColor
    let surface: LiminalThemeColor
    let elevated: LiminalThemeColor
    let divider: LiminalThemeColor
    let text: LiminalThemeColor
    let secondaryText: LiminalThemeColor
    let tertiaryText: LiminalThemeColor
    let primary: LiminalThemeColor
    let reward: LiminalThemeColor
    let dawn: LiminalThemeColor
    let dusk: LiminalThemeColor
    let gradientTop: LiminalThemeColor
    let gradientMiddle: LiminalThemeColor
    let gradientBottom: LiminalThemeColor
    let cardBottom: LiminalThemeColor

    init(
        canvas: String,
        surface: String,
        elevated: String,
        divider: String,
        text: String,
        secondaryText: String,
        tertiaryText: String,
        primary: String,
        reward: String,
        dawn: String,
        dusk: String,
        gradientTop: String,
        gradientMiddle: String,
        gradientBottom: String,
        cardBottom: String
    ) {
        self.canvas = LiminalThemeColor(hex: canvas)
        self.surface = LiminalThemeColor(hex: surface)
        self.elevated = LiminalThemeColor(hex: elevated)
        self.divider = LiminalThemeColor(hex: divider)
        self.text = LiminalThemeColor(hex: text)
        self.secondaryText = LiminalThemeColor(hex: secondaryText)
        self.tertiaryText = LiminalThemeColor(hex: tertiaryText)
        self.primary = LiminalThemeColor(hex: primary)
        self.reward = LiminalThemeColor(hex: reward)
        self.dawn = LiminalThemeColor(hex: dawn)
        self.dusk = LiminalThemeColor(hex: dusk)
        self.gradientTop = LiminalThemeColor(hex: gradientTop)
        self.gradientMiddle = LiminalThemeColor(hex: gradientMiddle)
        self.gradientBottom = LiminalThemeColor(hex: gradientBottom)
        self.cardBottom = LiminalThemeColor(hex: cardBottom)
    }
}

private struct LiminalThemeColor {
    let uiColor: UIColor

    init(hex: String) {
        self.uiColor = UIColor(liminalHex: hex)
    }
}

private extension UIColor {
    convenience init(liminalHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 1
            g = 1
            b = 1
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

import SwiftUI
import UIKit

struct LiminalThemeDefinition {
    let id: String
    let name: String
    let appearance: ColorScheme
    let palette: LiminalPalette
    let surface: LiminalSurfaceTreatment
    let glass: LiminalGlassTreatment
    let emphasis: LiminalTextEmphasis
    let effects: LiminalEffectTreatment
}

struct LiminalPalette {
    let canvas: UIColor
    let surface: UIColor
    let elevated: UIColor
    let divider: UIColor
    let text: UIColor
    let secondaryText: UIColor
    let tertiaryText: UIColor
    let primary: UIColor
    let reward: UIColor
    let dawn: UIColor
    let dusk: UIColor
    let gradientTop: UIColor
    let gradientMiddle: UIColor
    let gradientBottom: UIColor
    let cardBottom: UIColor

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
        self.canvas = UIColor(liminalHex: canvas)
        self.surface = UIColor(liminalHex: surface)
        self.elevated = UIColor(liminalHex: elevated)
        self.divider = UIColor(liminalHex: divider)
        self.text = UIColor(liminalHex: text)
        self.secondaryText = UIColor(liminalHex: secondaryText)
        self.tertiaryText = UIColor(liminalHex: tertiaryText)
        self.primary = UIColor(liminalHex: primary)
        self.reward = UIColor(liminalHex: reward)
        self.dawn = UIColor(liminalHex: dawn)
        self.dusk = UIColor(liminalHex: dusk)
        self.gradientTop = UIColor(liminalHex: gradientTop)
        self.gradientMiddle = UIColor(liminalHex: gradientMiddle)
        self.gradientBottom = UIColor(liminalHex: gradientBottom)
        self.cardBottom = UIColor(liminalHex: cardBottom)
    }
}

struct LiminalSurfaceTreatment {
    enum Style {
        case glass
        case solid
    }

    let style: Style
    let baseColor: UIColor?
    let tintFillOpacity: Double
    let strokeOpacity: Double
    let strokeWidth: CGFloat
}

struct LiminalGlassTreatment {
    let fillColor: UIColor
    let fillOpacity: Double
    let strokeColor: UIColor
    let strokeOpacity: Double
    let strokeWidth: CGFloat
}

struct LiminalTextEmphasis {
    let secondaryOpacity: Double
    let tertiaryOpacity: Double
}

struct LiminalEffectTreatment {
    let shadowStrength: Double
    let grainOpacity: Double
}

enum LiminalThemeCatalog {
    static let dusk = LiminalThemeDefinition(
        id: "dusk",
        name: "宵",
        appearance: .dark,
        palette: LiminalPalette(
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
        ),
        surface: LiminalSurfaceTreatment(
            style: .glass,
            baseColor: nil,
            tintFillOpacity: 0.12,
            strokeOpacity: 0,
            strokeWidth: 1
        ),
        glass: LiminalGlassTreatment(
            fillColor: UIColor.white,
            fillOpacity: 0.08,
            strokeColor: UIColor.white,
            strokeOpacity: 0.12,
            strokeWidth: 1
        ),
        emphasis: LiminalTextEmphasis(secondaryOpacity: 1, tertiaryOpacity: 1),
        effects: LiminalEffectTreatment(shadowStrength: 1, grainOpacity: 0.16)
    )

    static let daybreak = LiminalThemeDefinition(
        id: "daybreak",
        name: "曙",
        appearance: .light,
        palette: LiminalPalette(
            canvas: "#FBF8FC",
            surface: "#FFFDFE",
            elevated: "#FFFFFF",
            divider: "#E9DFEF",
            text: "#29233D",
            secondaryText: "#665E80",
            tertiaryText: "#958EA8",
            primary: "#8760D7",
            reward: "#E8B85E",
            dawn: "#FFD5E1",
            dusk: "#D7C8F2",
            gradientTop: "#FCF9FD",
            gradientMiddle: "#F8F1FB",
            gradientBottom: "#FFF5EF",
            cardBottom: "#FFF7F1"
        ),
        surface: LiminalSurfaceTreatment(
            style: .solid,
            baseColor: nil,
            tintFillOpacity: 0.1,
            strokeOpacity: 0.28,
            strokeWidth: 1
        ),
        glass: LiminalGlassTreatment(
            fillColor: UIColor(liminalHex: "#FFFDFE"),
            fillOpacity: 0.94,
            strokeColor: UIColor(liminalHex: "#E9DFEF"),
            strokeOpacity: 0.48,
            strokeWidth: 1
        ),
        emphasis: LiminalTextEmphasis(secondaryOpacity: 1, tertiaryOpacity: 1),
        effects: LiminalEffectTreatment(shadowStrength: 0.72, grainOpacity: 0.1)
    )

    static func definition(for scheme: ColorScheme) -> LiminalThemeDefinition {
        scheme == .light ? daybreak : dusk
    }

    static func definition(for traits: UITraitCollection) -> LiminalThemeDefinition {
        traits.userInterfaceStyle == .light ? daybreak : dusk
    }
}

extension UIColor {
    convenience init(liminalHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red, green, blue: CGFloat
        switch hex.count {
        case 6:
            red = CGFloat((int >> 16) & 0xFF) / 255
            green = CGFloat((int >> 8) & 0xFF) / 255
            blue = CGFloat(int & 0xFF) / 255
        default:
            red = 1
            green = 1
            blue = 1
        }
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

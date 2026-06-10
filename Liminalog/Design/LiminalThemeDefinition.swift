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
    let accent: UIColor
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
        accent: String,
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
        self.accent = UIColor(liminalHex: accent)
        self.reward = UIColor(liminalHex: reward)
        self.dawn = UIColor(liminalHex: dawn)
        self.dusk = UIColor(liminalHex: dusk)
        self.gradientTop = UIColor(liminalHex: gradientTop)
        self.gradientMiddle = UIColor(liminalHex: gradientMiddle)
        self.gradientBottom = UIColor(liminalHex: gradientBottom)
        self.cardBottom = UIColor(liminalHex: cardBottom)
    }

    init(
        canvas: UIColor,
        surface: UIColor,
        elevated: UIColor,
        divider: UIColor,
        text: UIColor,
        secondaryText: UIColor,
        tertiaryText: UIColor,
        primary: UIColor,
        accent: UIColor,
        reward: UIColor,
        dawn: UIColor,
        dusk: UIColor,
        gradientTop: UIColor,
        gradientMiddle: UIColor,
        gradientBottom: UIColor,
        cardBottom: UIColor
    ) {
        self.canvas = canvas
        self.surface = surface
        self.elevated = elevated
        self.divider = divider
        self.text = text
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.primary = primary
        self.accent = accent
        self.reward = reward
        self.dawn = dawn
        self.dusk = dusk
        self.gradientTop = gradientTop
        self.gradientMiddle = gradientMiddle
        self.gradientBottom = gradientBottom
        self.cardBottom = cardBottom
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
    static let systemThemeID = "default"

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
            accent: "#C9A7FF",
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
            canvas: "#FAF5EE",
            surface: "#FFFDF9",
            elevated: "#FFFFFF",
            divider: "#ECE0D6",
            text: "#2F2A30",
            secondaryText: "#6B6166",
            tertiaryText: "#9A8F92",
            primary: "#A8673D",
            accent: "#A8673D",
            reward: "#E0A94E",
            dawn: "#F9D2AE",
            dusk: "#CBB8E8",
            gradientTop: "#ECE7EE",
            gradientMiddle: "#F7ECDD",
            gradientBottom: "#FBE0C4",
            cardBottom: "#FFF6EC"
        ),
        surface: LiminalSurfaceTreatment(
            style: .solid,
            baseColor: nil,
            tintFillOpacity: 0.1,
            strokeOpacity: 0.28,
            strokeWidth: 1
        ),
        glass: LiminalGlassTreatment(
            fillColor: UIColor(liminalHex: "#FFFDF9"),
            fillOpacity: 0.94,
            strokeColor: UIColor(liminalHex: "#ECE0D6"),
            strokeOpacity: 0.48,
            strokeWidth: 1
        ),
        emphasis: LiminalTextEmphasis(secondaryOpacity: 1, tertiaryOpacity: 1),
        effects: LiminalEffectTreatment(shadowStrength: 0.9, grainOpacity: 0.12)
    )

    // MARK: - 解放テーマ（1テーマ＝1つの空・モード無視）

    /// 解放テーマ共通の暗い大気トリートメント（宵に準拠）。
    private static func skyTreatments() -> (LiminalSurfaceTreatment, LiminalGlassTreatment, LiminalTextEmphasis, LiminalEffectTreatment) {
        (
            LiminalSurfaceTreatment(style: .glass, baseColor: nil, tintFillOpacity: 0.12, strokeOpacity: 0, strokeWidth: 1),
            LiminalGlassTreatment(fillColor: .white, fillOpacity: 0.08, strokeColor: .white, strokeOpacity: 0.12, strokeWidth: 1),
            LiminalTextEmphasis(secondaryOpacity: 1, tertiaryOpacity: 1),
            LiminalEffectTreatment(shadowStrength: 1, grainOpacity: 0.16)
        )
    }

    // 極光は「幻想的なオーロラの薄明」＝ライトベースのテーマ。地もカードも明るく、文字は暗色。
    static let aurora = LiminalThemeDefinition(
        id: "aurora", name: "極光", appearance: .light,
        palette: LiminalPalette(
            canvas: "#E3F2EB",
            surface: "#F4FBF8",
            elevated: "#FFFFFF",
            divider: "#D2E7DE",
            text: "#24242B",
            secondaryText: "#585862",
            tertiaryText: "#8C8C96",
            primary: "#179C73",
            accent: "#179C73",
            reward: "#C98A2E",
            dawn: "#BDEBD6",
            dusk: "#CDB9E8",
            gradientTop: "#D4EEE1",
            gradientMiddle: "#A6DCCD",
            gradientBottom: "#C2B4E6",
            cardBottom: "#EAF7F1"
        ),
        surface: LiminalSurfaceTreatment(
            style: .solid,
            baseColor: nil,
            tintFillOpacity: 0.1,
            strokeOpacity: 0.28,
            strokeWidth: 1
        ),
        glass: LiminalGlassTreatment(
            fillColor: UIColor(liminalHex: "#F4FBF8"),
            fillOpacity: 0.94,
            strokeColor: UIColor(liminalHex: "#D2E7DE"),
            strokeOpacity: 0.5,
            strokeWidth: 1
        ),
        emphasis: LiminalTextEmphasis(secondaryOpacity: 1, tertiaryOpacity: 1),
        effects: LiminalEffectTreatment(shadowStrength: 0.9, grainOpacity: 0.12)
    )

    static let akatsuki: LiminalThemeDefinition = {
        let t = skyTreatments()
        return LiminalThemeDefinition(
            id: "akatsuki", name: "暁", appearance: .dark,
            palette: LiminalPalette(
                canvas: "#08061A", surface: "#16122C", elevated: "#1E1940", divider: "#2C2756",
                text: "#ECE8FA", secondaryText: "#B4ACD8", tertiaryText: "#7E76A6",
                primary: "#9B8CFF", accent: "#9B8CFF", reward: "#FFCFA0",
                dawn: "#C9A0E8", dusk: "#6E5AB0",
                gradientTop: "#0F0C30", gradientMiddle: "#2A1E58", gradientBottom: "#C98A6E",
                cardBottom: "#18142F"
            ),
            surface: t.0, glass: t.1, emphasis: t.2, effects: t.3
        )
    }()

    static let oboro: LiminalThemeDefinition = {
        let t = skyTreatments()
        return LiminalThemeDefinition(
            id: "oboro", name: "朧", appearance: .dark,
            palette: LiminalPalette(
                canvas: "#16161F", surface: "#2A2A3D", elevated: "#363650", divider: "#45455F",
                text: "#EFEDF6", secondaryText: "#B8B4CE", tertiaryText: "#85819C",
                primary: "#C7CBEC", accent: "#AEB4DD", reward: "#E8E0C8",
                dawn: "#D6D2EC", dusk: "#9A96B8",
                gradientTop: "#2E3046", gradientMiddle: "#4A4C68", gradientBottom: "#8A86A8",
                cardBottom: "#2E2E42"
            ),
            surface: t.0, glass: t.1, emphasis: t.2, effects: t.3
        )
    }()

    /// 解放テーマ（targetID をキーに UnlockCatalog と一致）。順次追加可能。
    static let unlockedThemesByID: [String: LiminalThemeDefinition] = [
        aurora.id: aurora,
        akatsuki.id: akatsuki,
        oboro.id: oboro
    ]

    /// テーマ選択UIに並べる解放テーマ（パレット実装済みのもの）。
    static let selectableThemes: [LiminalThemeDefinition] = [aurora, akatsuki, oboro]

    /// 初期から使える標準テーマ。systemThemeID はシステム追従として別扱いする。
    static let fixedDefaultThemes: [LiminalThemeDefinition] = [dusk, daybreak]

    /// 現在選択中のテーマID（"default" はシステム追従）。MainActor で更新する軽量キャッシュ。
    nonisolated(unsafe) static var activeThemeID: String = systemThemeID
    nonisolated(unsafe) static var transitionSourceThemeID: String?
    nonisolated(unsafe) static var transitionProgress: CGFloat = 1

    static func definition(for scheme: ColorScheme) -> LiminalThemeDefinition {
        scheme == .light ? daybreak : dusk
    }

    static func definition(for traits: UITraitCollection) -> LiminalThemeDefinition {
        traits.userInterfaceStyle == .light ? daybreak : dusk
    }

    /// 選択テーマを考慮した解決。"default" は追従、解放テーマは固定、未知IDは安全に追従へ。
    static func resolvedDefinition(for traits: UITraitCollection) -> LiminalThemeDefinition {
        let target = definition(themeID: activeThemeID, traits: traits)
        return transitionedDefinition(target: target) { sourceID in
            definition(themeID: sourceID, traits: traits)
        }
    }

    static func resolvedDefinition(for scheme: ColorScheme) -> LiminalThemeDefinition {
        let target = definition(themeID: activeThemeID, scheme: scheme)
        return transitionedDefinition(target: target) { sourceID in
            definition(themeID: sourceID, scheme: scheme)
        }
    }

    static func preferredColorScheme(for themeID: String) -> ColorScheme? {
        if themeID == systemThemeID { return nil }
        if themeID == dusk.id { return dusk.appearance }
        if themeID == daybreak.id { return daybreak.appearance }
        return unlockedThemesByID[themeID]?.appearance
    }

    private static func definition(themeID: String, traits: UITraitCollection) -> LiminalThemeDefinition {
        if themeID == systemThemeID { return definition(for: traits) }
        if themeID == dusk.id { return dusk }
        if themeID == daybreak.id { return daybreak }
        return unlockedThemesByID[themeID] ?? definition(for: traits)
    }

    private static func definition(themeID: String, scheme: ColorScheme) -> LiminalThemeDefinition {
        if themeID == systemThemeID { return definition(for: scheme) }
        if themeID == dusk.id { return dusk }
        if themeID == daybreak.id { return daybreak }
        return unlockedThemesByID[themeID] ?? definition(for: scheme)
    }

    private static func transitionedDefinition(
        target: LiminalThemeDefinition,
        sourceDefinition: (String) -> LiminalThemeDefinition
    ) -> LiminalThemeDefinition {
        let progress = min(max(transitionProgress, 0), 1)
        guard
            progress < 1,
            let sourceID = transitionSourceThemeID
        else {
            return target
        }

        let source = sourceDefinition(sourceID)
        guard source.id != target.id else { return target }
        return interpolatedDefinition(from: source, to: target, progress: progress)
    }

    private static func interpolatedDefinition(
        from source: LiminalThemeDefinition,
        to target: LiminalThemeDefinition,
        progress: CGFloat
    ) -> LiminalThemeDefinition {
        LiminalThemeDefinition(
            id: target.id,
            name: target.name,
            appearance: progress < 0.5 ? source.appearance : target.appearance,
            palette: LiminalPalette(
                canvas: mixed(source.palette.canvas, target.palette.canvas, progress: progress),
                surface: mixed(source.palette.surface, target.palette.surface, progress: progress),
                elevated: mixed(source.palette.elevated, target.palette.elevated, progress: progress),
                divider: mixed(source.palette.divider, target.palette.divider, progress: progress),
                text: mixed(source.palette.text, target.palette.text, progress: progress),
                secondaryText: mixed(source.palette.secondaryText, target.palette.secondaryText, progress: progress),
                tertiaryText: mixed(source.palette.tertiaryText, target.palette.tertiaryText, progress: progress),
                primary: mixed(source.palette.primary, target.palette.primary, progress: progress),
                accent: mixed(source.palette.accent, target.palette.accent, progress: progress),
                reward: mixed(source.palette.reward, target.palette.reward, progress: progress),
                dawn: mixed(source.palette.dawn, target.palette.dawn, progress: progress),
                dusk: mixed(source.palette.dusk, target.palette.dusk, progress: progress),
                gradientTop: mixed(source.palette.gradientTop, target.palette.gradientTop, progress: progress),
                gradientMiddle: mixed(source.palette.gradientMiddle, target.palette.gradientMiddle, progress: progress),
                gradientBottom: mixed(source.palette.gradientBottom, target.palette.gradientBottom, progress: progress),
                cardBottom: mixed(source.palette.cardBottom, target.palette.cardBottom, progress: progress)
            ),
            surface: interpolatedSurface(from: source.surface, to: target.surface, progress: progress),
            glass: interpolatedGlass(from: source.glass, to: target.glass, progress: progress),
            emphasis: LiminalTextEmphasis(
                secondaryOpacity: mixed(source.emphasis.secondaryOpacity, target.emphasis.secondaryOpacity, progress: progress),
                tertiaryOpacity: mixed(source.emphasis.tertiaryOpacity, target.emphasis.tertiaryOpacity, progress: progress)
            ),
            effects: LiminalEffectTreatment(
                shadowStrength: mixed(source.effects.shadowStrength, target.effects.shadowStrength, progress: progress),
                grainOpacity: mixed(source.effects.grainOpacity, target.effects.grainOpacity, progress: progress)
            )
        )
    }

    private static func interpolatedSurface(
        from source: LiminalSurfaceTreatment,
        to target: LiminalSurfaceTreatment,
        progress: CGFloat
    ) -> LiminalSurfaceTreatment {
        LiminalSurfaceTreatment(
            style: progress < 0.5 ? source.style : target.style,
            baseColor: mixed(source.baseColor, target.baseColor, progress: progress),
            tintFillOpacity: mixed(source.tintFillOpacity, target.tintFillOpacity, progress: progress),
            strokeOpacity: mixed(source.strokeOpacity, target.strokeOpacity, progress: progress),
            strokeWidth: mixed(source.strokeWidth, target.strokeWidth, progress: progress)
        )
    }

    private static func interpolatedGlass(
        from source: LiminalGlassTreatment,
        to target: LiminalGlassTreatment,
        progress: CGFloat
    ) -> LiminalGlassTreatment {
        LiminalGlassTreatment(
            fillColor: mixed(source.fillColor, target.fillColor, progress: progress),
            fillOpacity: mixed(source.fillOpacity, target.fillOpacity, progress: progress),
            strokeColor: mixed(source.strokeColor, target.strokeColor, progress: progress),
            strokeOpacity: mixed(source.strokeOpacity, target.strokeOpacity, progress: progress),
            strokeWidth: mixed(source.strokeWidth, target.strokeWidth, progress: progress)
        )
    }

    private static func mixed(_ source: UIColor?, _ target: UIColor?, progress: CGFloat) -> UIColor? {
        switch (source, target) {
        case let (source?, target?):
            mixed(source, target, progress: progress)
        case let (source?, nil):
            source
        case let (nil, target?):
            target
        case (nil, nil):
            nil
        }
    }

    private static func mixed(_ source: UIColor, _ target: UIColor, progress: CGFloat) -> UIColor {
        let sourceComponents = rgba(source)
        let targetComponents = rgba(target)
        return UIColor(
            red: mixed(sourceComponents.red, targetComponents.red, progress: progress),
            green: mixed(sourceComponents.green, targetComponents.green, progress: progress),
            blue: mixed(sourceComponents.blue, targetComponents.blue, progress: progress),
            alpha: mixed(sourceComponents.alpha, targetComponents.alpha, progress: progress)
        )
    }

    private static func rgba(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0, 0, 0, 1)
        }
        return (red, green, blue, alpha)
    }

    private static func mixed(_ source: Double, _ target: Double, progress: CGFloat) -> Double {
        source + (target - source) * Double(progress)
    }

    private static func mixed(_ source: CGFloat, _ target: CGFloat, progress: CGFloat) -> CGFloat {
        source + (target - source) * progress
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

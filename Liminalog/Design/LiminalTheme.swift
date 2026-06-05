import SwiftUI
import UIKit

struct LiminalThemeTransitionProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

struct LiminalThemeIDKey: EnvironmentKey {
    static let defaultValue = LiminalThemeCatalog.systemThemeID
}

extension EnvironmentValues {
    var liminalThemeTransitionProgress: CGFloat {
        get { self[LiminalThemeTransitionProgressKey.self] }
        set { self[LiminalThemeTransitionProgressKey.self] = newValue }
    }

    var liminalThemeID: String {
        get { self[LiminalThemeIDKey.self] }
        set { self[LiminalThemeIDKey.self] = newValue }
    }
}

enum LiminalTheme {
    static let themeTransitionAnimation = Animation.easeInOut(duration: 0.42)

    // computed（static let にしない）: アクセスごとに新しい UIColor 動的プロバイダを生成する。
    // UIColor 動的色は trait 単位でキャッシュされ activeThemeID 変化を検知しにくいため、
    // themeName 変更で再描画される body 内から都度参照して新インスタンスを渡す。
    static var canvas: Color { token(\.canvas) }
    static var surface: Color { token(\.surface) }
    static var elevated: Color { token(\.elevated) }
    static var divider: Color { token(\.divider) }

    static var text: Color { token(\.text) }
    static var secondaryText: Color { token(\.secondaryText) }
    static var tertiaryText: Color { token(\.tertiaryText) }

    static var primary: Color { token(\.primary) }
    static var accent: Color { token(\.accent) }
    static var reward: Color { token(\.reward) }
    static var dawn: Color { token(\.dawn) }
    static var dusk: Color { token(\.dusk) }

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
        LiminalThemeCatalog.resolvedDefinition(for: traits).palette.canvas
    }

    private static func token(_ keyPath: KeyPath<LiminalPalette, UIColor>) -> Color {
        Color(
            UIColor { traits in
                LiminalThemeCatalog.resolvedDefinition(for: traits).palette[keyPath: keyPath]
            }
        )
    }
}

extension View {
    func liminalAppChrome() -> some View {
        self
            .tint(LiminalTheme.accent)
            .accentColor(LiminalTheme.accent)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
    }

    /// canvasGradient に直接乗るチップ/リボンの下地。
    /// ダーク: 色を薄く敷くだけのガラス（黒地で光って見えるので従来通り）。
    /// ライト: 不透明な surface 面＋淡い色＋色の細枠で「輪郭」を立てる。
    /// 淡い半透明をグラデ地に直接置くと、背後の色温度差で濁って溶けるのを防ぐ。
    func liminalCanvasChip<S: Shape>(
        tint: Color,
        in shape: S,
        darkFillOpacity: Double? = nil
    ) -> some View {
        modifier(LiminalCanvasChip(tint: tint, shape: shape, darkFillOpacity: darkFillOpacity))
    }

    /// canvasGradient に直接乗る「セクション」を包む共通カード。
    /// 不透明な surface 面＋細枠＋柔らかい影で輪郭を立て、暖グラデ地に溶けるのを防ぐ。
    /// ライト: 暖色の柔らかい影（golden hour の長い影）。ダーク: dusk寄りの影。
    func liminalSectionCard(cornerRadius: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(LiminalSectionCard(cornerRadius: cornerRadius, padding: padding))
    }

    func liminalGlassFill<S: Shape>(in shape: S) -> some View {
        modifier(LiminalGlassFill(shape: shape))
    }

    func liminalAccentLight<S: Shape>(
        in shape: S,
        intensity: Double = 1
    ) -> some View {
        modifier(LiminalAccentLight(shape: shape, intensity: intensity))
    }
}

private struct LiminalCanvasChip<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let tint: Color
    let shape: S
    let darkFillOpacity: Double?

    func body(content: Content) -> some View {
        let transitionProgress = themeTransitionProgress
        let treatment = LiminalThemeCatalog.resolvedDefinition(for: scheme).surface
        content.background {
            switch treatment.style {
            case .glass:
                shape.fill(tint.opacity((darkFillOpacity ?? treatment.tintFillOpacity) + Double(transitionProgress * 0)))
            case .solid:
                shape.fill(Color(treatment.baseColor ?? LiminalThemeCatalog.resolvedDefinition(for: scheme).palette.surface))
                    .overlay(shape.fill(tint.opacity(treatment.tintFillOpacity)))
                    .overlay {
                        if treatment.strokeOpacity > 0 && treatment.strokeWidth > 0 {
                            shape.stroke(tint.opacity(treatment.strokeOpacity), lineWidth: treatment.strokeWidth)
                        }
                    }
            }
        }
    }
}

private struct LiminalSectionCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        let transitionProgress = themeTransitionProgress
        let def = LiminalThemeCatalog.resolvedDefinition(for: scheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isLight = scheme == .light
        let fill = Color(def.palette.surface)
        return content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.stroke(Color(def.palette.divider).opacity(isLight ? 0.7 : 0.45), lineWidth: 1))
            .shadow(
                color: Color(isLight ? def.palette.text : def.palette.dusk)
                    .opacity((isLight ? 0.1 : 0.2) * def.effects.shadowStrength),
                radius: isLight ? 16 : 18,
                y: (isLight ? 6 : 8) + transitionProgress * 0
            )
    }
}

private struct LiminalGlassFill<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    let shape: S

    func body(content: Content) -> some View {
        let transitionProgress = themeTransitionProgress
        let treatment = LiminalThemeCatalog.resolvedDefinition(for: scheme).glass
        content.background {
            shape.fill(Color(treatment.fillColor).opacity(treatment.fillOpacity + Double(transitionProgress * 0)))
                .overlay {
                    if treatment.strokeOpacity > 0 && treatment.strokeWidth > 0 {
                        shape.stroke(
                            Color(treatment.strokeColor).opacity(treatment.strokeOpacity),
                            lineWidth: treatment.strokeWidth
                        )
                    }
                }
        }
    }
}

private struct LiminalAccentLight<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let shape: S
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .background {
                if scheme == .light {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    LiminalTheme.reward.opacity(0.22 * intensity),
                                    LiminalTheme.dawn.opacity(0.11 * intensity),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            shape.stroke(LiminalTheme.reward.opacity(0.18 * intensity), lineWidth: 1)
                        )
                        .shadow(color: LiminalTheme.reward.opacity(0.18 * intensity), radius: 18 * intensity, y: 8)
                }
            }
    }
}

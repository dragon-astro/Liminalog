import SwiftUI
import UIKit

enum LiminalTheme {
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
        LiminalThemeCatalog.definition(for: traits).palette.canvas
    }

    private static func token(_ keyPath: KeyPath<LiminalPalette, UIColor>) -> Color {
        Color(
            UIColor { traits in
                LiminalThemeCatalog.definition(for: traits).palette[keyPath: keyPath]
            }
        )
    }
}

extension View {
    func liminalAppChrome() -> some View {
        self
            .tint(LiminalTheme.primary)
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

    func liminalGlassFill<S: Shape>(in shape: S) -> some View {
        modifier(LiminalGlassFill(shape: shape))
    }
}

private struct LiminalCanvasChip<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let tint: Color
    let shape: S
    let darkFillOpacity: Double?

    func body(content: Content) -> some View {
        let treatment = LiminalThemeCatalog.definition(for: scheme).surface
        content.background {
            switch treatment.style {
            case .glass:
                shape.fill(tint.opacity(darkFillOpacity ?? treatment.tintFillOpacity))
            case .solid:
                shape.fill(Color(treatment.baseColor ?? LiminalThemeCatalog.definition(for: scheme).palette.surface))
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

private struct LiminalGlassFill<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let shape: S

    func body(content: Content) -> some View {
        let treatment = LiminalThemeCatalog.definition(for: scheme).glass
        content.background {
            shape.fill(Color(treatment.fillColor).opacity(treatment.fillOpacity))
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

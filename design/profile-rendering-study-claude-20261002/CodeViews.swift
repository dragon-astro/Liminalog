// 公開ビュー（本体の画像表示と差し替え比較できる形）とカード共通処理。
import SwiftUI

// MARK: - Public views

enum Motif: String, CaseIterable, Identifiable {
    case leaf, star
    var id: String { rawValue }
    var title: String { self == .leaf ? "葉隅" : "星図線" }
}

/// 本体 `ProfileIconFrameView(size:)` と同じ size を受け取る差し替え候補。
struct CodeFrameView: View {
    let motif: Motif
    let size: CGFloat
    var pixelScale: CGFloat? = nil
    @Environment(\.displayScale) private var envScale

    static let contentScale: CGFloat = 1.12
    /// 1024px マスターでのアバター半径 383px に相当。
    static let unitRatio: CGFloat = 383.0 / 1024.0

    var body: some View {
        CodeFrameCanvas(motif: motif, side: size * Self.contentScale, pixelScale: pixelScale ?? envScale)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

/// フレームの実体。side は 1024px マスター1枚に相当する正方形の一辺。
struct CodeFrameCanvas: View {
    let motif: Motif
    let side: CGFloat
    let pixelScale: CGFloat

    var body: some View {
        let unit = side * CodeFrameView.unitRatio
        let detail = Detail(pxPerUnit: unit * pixelScale)
        let ops = (motif == .leaf ? LeafFrameBuilder.build(detail: detail) : StarFrameBuilder.build(detail: detail)).sorted { $0.z < $1.z }
        // 半透明の煙を何層も重ねてぼかすため、8bit の量子化で等高線が出ないよう浮動小数で合成する
        Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: false) { ctx, sz in
            var c = ctx
            c.translateBy(x: sz.width / 2, y: sz.height / 2)
            c.scaleBy(x: unit, y: unit)
            for op in ops { op.draw(c) }
        }
        .frame(width: side, height: side)
    }
}

/// カード背景（パネル＋装飾）。渡された矩形に描き、葉や光芒は縁から少しだけはみ出せる（本体の画像も
/// scaleEffect 1.08 で枠外へはみ出しているため、同程度のにじみ代 `bleed` を持たせる）。
struct CodeCardView: View {
    let motif: Motif
    var pixelScale: CGFloat? = nil
    @Environment(\.displayScale) private var envScale

    var body: some View {
        let scale = pixelScale ?? envScale
        GeometryReader { proxy in
            let size = proxy.size
            let bleed = (CardGeometry.k(size) * 12).rounded(.up)
            Canvas { ctx, _ in
                var c = ctx
                c.translateBy(x: bleed, y: bleed)
                switch motif {
                case .leaf: LeafCard.draw(c, size: size, scale: scale, bleed: bleed)
                case .star: StarCard.draw(c, size: size, scale: scale, bleed: bleed)
                }
            }
            .frame(width: size.width + bleed * 2, height: size.height + bleed * 2)
            .offset(x: -bleed, y: -bleed)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Card common

enum CardGeometry {
    /// 350×226 を基準(k=1)とした縮尺。
    static func k(_ size: CGSize) -> CGFloat { min(size.width / 342, size.height / 222) }
    static func panel(_ size: CGSize) -> (rect: CGRect, radius: CGFloat) {
        let k = k(size)
        let inset = max(2, 6 * k)
        let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        return (rect, max(4, 17 * k))
    }

    /// 不規則な輪郭の閉曲線（水彩のしみ・雲）。完全な円は「コードで描いた」感が出るので使わない。
    static func organicBlob(radius R: CGFloat, rng: inout SeededRNG, points n: Int = 11, roughness: CGFloat = 0.22) -> Path {
        let ph1 = rng.range(0, 6), ph2 = rng.range(0, 6)
        var pts: [CGPoint] = []
        for i in 0..<n {
            let a = 2 * .pi * (CGFloat(i) + rng.range(-0.2, 0.2)) / CGFloat(n)
            let wobble = 0.6 * sin(2 * a + ph1) + 0.4 * sin(3 * a + ph2)
            let r = R * (1 + roughness * wobble + rng.range(-roughness, roughness) * 0.45)
            pts.append(CGPoint.polar(r, a))
        }
        return smoothPath(pts, closed: true)
    }

    /// 水彩のにじみ：不規則な形の淡い色面を重ね、乾き際（縁の濃い線）を残してから軽くぼかす。
    static func wash(_ ctx: GraphicsContext, in rect: CGRect, colors: [RGB], count: Int, k: CGFloat, alpha: ClosedRange<CGFloat>, seed: UInt64, avoidCenter: Bool,
                     driedEdges: Bool = true, blur: CGFloat = 0.9) {
        var rng = SeededRNG(seed)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(0.5, blur * k)))
            for _ in 0..<count {
                var p = CGPoint(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height)
                if avoidCenter {
                    // 中央（文字の下）は淡く保つ：中心付近のにじみを外へ押し出す
                    let cx = (p.x - rect.midX) / (rect.width / 2), cy = (p.y - rect.midY) / (rect.height / 2)
                    let r = sqrt(cx * cx + cy * cy)
                    if r < 0.75 && rng.chance(0.6) {
                        let push = 0.75 / max(r, 0.2)
                        p = CGPoint(x: rect.midX + cx * push * rect.width / 2, y: rect.midY + cy * push * rect.height / 2)
                    }
                }
                let rad = rng.range(22, 75) * k
                let col = rng.pick(colors)
                let a = Double(rng.range(alpha.lowerBound, alpha.upperBound))
                let sx = rng.range(0.7, 1.4)
                var c = layer
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: .radians(rng.range(0, 3.14)))
                c.scaleBy(x: sx, y: 1 / sx)
                let blob = organicBlob(radius: rad, rng: &rng, points: 12, roughness: rng.range(0.14, 0.3))
                c.fill(blob, with: .radialGradient(Gradient(stops: [
                    .init(color: col.c(a), location: 0),
                    .init(color: col.c(a * 0.7), location: 0.6),
                    .init(color: col.c(a * 0.95), location: 1),
                ]), center: CGPoint(x: rng.range(-0.3, 0.3) * rad, y: rng.range(-0.3, 0.3) * rad), startRadius: 0, endRadius: rad * 1.2))
                if driedEdges && rng.chance(0.55) {
                    // 乾き際の顔料の溜まり
                    c.stroke(blob, with: .color(col.mix(RGB(0x2A4A5A), 0.25).c(a * 0.55)), lineWidth: max(0.4, 1.1 * k))
                }
            }
        }
    }

    /// 紙の繊維感：極小の明暗の点。
    static func grain(_ ctx: GraphicsContext, in rect: CGRect, count: Int, dark: RGB, light: RGB, seed: UInt64, scale: CGFloat) {
        var rng = SeededRNG(seed)
        let px = 1 / scale
        for _ in 0..<count {
            let p = CGPoint(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height)
            let r = px * rng.range(0.5, 1.2)
            let isDark = rng.chance(0.5)
            ctx.fill(Celestial.disc(p, r), with: .color((isDark ? dark : light).c(Double(rng.range(0.05, 0.14)))))
        }
    }
}

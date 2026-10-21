// 星図の部品（光芒・星・星座形）。フレームとカードで共有する。
import SwiftUI

// MARK: - Celestial primitives

enum StarPalette {
    static let indigo = RGB(0x34358A)
    static let violet = RGB(0x6A55C6)
    static let periwinkle = RGB(0x8C93E8)
    static let lagoon = RGB(0x2D6D90)
    static let orchid = RGB(0xB487DC)
    static let gold = RGB(0xF2CC7A)
    static let cream = RGB(0xFFF4DA)
    static let cyan = RGB(0xA7E6F6)
    static let line = RGB(0xFFF0CC)
}

/// 手で設計した星座形（カードとフレームで共有）。点と結線。
struct Constellation {
    var points: [CGPoint]
    var edges: [(Int, Int)]
    var magnitudes: [Int]  // 0=一等星 … 3=微光

    static let dipper = Constellation(
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.9, y: 0.25), CGPoint(x: 1.75, y: 0.1), CGPoint(x: 2.45, y: 0.55), CGPoint(x: 2.6, y: 1.35), CGPoint(x: 3.45, y: 1.5), CGPoint(x: 3.3, y: 0.62)],
        edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 3)], magnitudes: [2, 1, 2, 0, 2, 1, 3])
    static let cassiopeia = Constellation(
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.7, y: 0.95), CGPoint(x: 1.5, y: 0.35), CGPoint(x: 2.25, y: 1.15), CGPoint(x: 3.05, y: 0.4)],
        edges: [(0, 1), (1, 2), (2, 3), (3, 4)], magnitudes: [1, 2, 0, 2, 1])
    static let swan = Constellation(
        points: [CGPoint(x: 1.1, y: 0), CGPoint(x: 1.1, y: 1.0), CGPoint(x: 1.15, y: 2.2), CGPoint(x: 0, y: 1.15), CGPoint(x: 2.15, y: 0.85), CGPoint(x: 1.25, y: 3.0)],
        edges: [(0, 1), (1, 2), (3, 1), (1, 4), (2, 5)], magnitudes: [0, 1, 2, 2, 2, 3])
    static let kite = Constellation(
        points: [CGPoint(x: 0, y: 0), CGPoint(x: 1.0, y: 0.6), CGPoint(x: 0.4, y: 1.4), CGPoint(x: 1.6, y: 1.65), CGPoint(x: 2.4, y: 1.0)],
        edges: [(0, 1), (1, 2), (2, 0), (2, 3), (3, 4), (4, 1)], magnitudes: [2, 0, 2, 1, 3])
    static let arc = Constellation(
        points: [CGPoint(x: 0, y: 0.4), CGPoint(x: 0.8, y: 0), CGPoint(x: 1.7, y: 0.15), CGPoint(x: 2.3, y: 0.8), CGPoint(x: 2.5, y: 1.7)],
        edges: [(0, 1), (1, 2), (2, 3), (3, 4)], magnitudes: [2, 1, 3, 1, 0])
}

enum Celestial {
    /// 4方向の光芒（凹辺の十字星）。
    static func sparklePath(long: CGFloat, waist: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: long, y: 0))
        p.addQuadCurve(to: CGPoint(x: 0, y: -long), control: CGPoint(x: waist, y: -waist))
        p.addQuadCurve(to: CGPoint(x: -long, y: 0), control: CGPoint(x: -waist, y: -waist))
        p.addQuadCurve(to: CGPoint(x: 0, y: long), control: CGPoint(x: -waist, y: waist))
        p.addQuadCurve(to: CGPoint(x: long, y: 0), control: CGPoint(x: waist, y: waist))
        p.closeSubpath()
        return p
    }

    static func disc(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }

    static func coreRadius(_ m: Int, _ s: CGFloat, _ d: Detail) -> CGFloat {
        d.w(s * [0.36, 0.3, 0.24, 0.17][min(m, 3)], minPx: [1.15, 0.95, 0.8, 0.62][min(m, 3)])
    }

    /// 星の節点。小さな白い核＋細く長い光芒＋核の数倍に留めた暈。円盤を大きくしない（ボタンに見えるため）。
    static func drawStar(_ ctx: GraphicsContext, at p: CGPoint, magnitude m: Int, size s: CGFloat, tint: RGB, detail d: Detail,
                         circled: Bool = false, spin: CGFloat = 0, additive: Bool = true) {
        let core = coreRadius(m, s, d)
        var c = ctx
        if additive { c.blendMode = .plusLighter }
        let haloR = core * [3.8, 3.0, 2.2, 0][min(m, 3)]
        if haloR > 0 {
            let a = [0.38, 0.28, 0.18, 0][min(m, 3)]
            c.fill(disc(p, haloR), with: .radialGradient(Gradient(stops: [
                .init(color: StarPalette.cream.c(a), location: 0),
                .init(color: tint.c(a * 0.45), location: 0.35),
                .init(color: tint.c(0), location: 1),
            ]), center: p, startRadius: 0, endRadius: haloR))
        }
        var sc = ctx
        sc.translateBy(x: p.x, y: p.y)
        sc.rotate(by: .radians(spin))
        if m == 0 {
            sc.fill(sparklePath(long: max(core * 6.5, d.minWidth(5)), waist: d.w(core * 0.17, minPx: 0.3)), with: .color(StarPalette.cream.c(0.95)))
            sc.rotate(by: .radians(.pi / 4))
            sc.fill(sparklePath(long: core * 3, waist: d.w(core * 0.15, minPx: 0.26)), with: .color(StarPalette.cream.c(0.5)))
        } else if m == 1 && d.px(core) > 1.0 {
            sc.fill(sparklePath(long: core * 4.2, waist: d.w(core * 0.17, minPx: 0.28)), with: .color(StarPalette.cream.c(0.75)))
        }
        ctx.fill(disc(p, core), with: .radialGradient(
            Gradient(colors: [.white, StarPalette.cream.c(), tint.c()]), center: p, startRadius: 0, endRadius: core * 1.05))
        if circled {
            ctx.stroke(disc(p, core * (m == 0 ? 3.4 : 4.2)), with: .color(StarPalette.gold.c(0.85)), lineWidth: d.w(core * 0.2, minPx: 0.45))
        }
    }

    static func drawConstellation(_ ctx: GraphicsContext, _ con: Constellation, map: (CGPoint) -> CGPoint, starSize: CGFloat,
                                  lineWidth: CGFloat, detail d: Detail, tints: [RGB], lineColor: RGB = StarPalette.line, lineAlpha: Double = 0.8,
                                  dashed: Bool = false, circledIndex: Int? = nil, spin: CGFloat = 0, additive: Bool = true) {
        let pts = con.points.map(map)
        var lines = Path()
        for (a, b) in con.edges {
            // 星の核ぶん端を詰め、線が星に突き刺さらないようにする
            let pa = pts[a], pb = pts[b]
            let v = pb - pa
            let len = max(v.length, 0.0001)
            func gap(_ i: Int) -> CGFloat {
                let core = coreRadius(con.magnitudes[i], starSize, d)
                return core * (i == circledIndex ? 4.8 : (con.magnitudes[i] == 0 ? 2.4 : 1.8))
            }
            let ga = gap(a), gb = gap(b)
            guard len > ga + gb else { continue }
            lines.move(to: pa + v * (ga / len))
            lines.addLine(to: pb - v * (gb / len))
        }
        let w = d.w(lineWidth, minPx: 0.5)
        ctx.stroke(lines, with: .color(lineColor.c(lineAlpha)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, dash: dashed ? [w * 3, w * 3] : []))
        for (i, p) in pts.enumerated() {
            drawStar(ctx, at: p, magnitude: con.magnitudes[i], size: starSize, tint: tints[i % tints.count], detail: d,
                     circled: i == circledIndex, spin: spin, additive: additive)
        }
    }
}

// 星図の部品（光芒・星・星座形）。宵では発光、曙では墨と金で描く。
import SwiftUI

struct StarStyle {
    var line: RGB, lineAlpha: Double
    var core: RGB, rim: RGB, halo: RGB
    var tints: [RGB]
    var additive: Bool

    static func make(_ s: DecoScheme, _ pal: ItemPalette) -> StarStyle {
        if s.isDark {
            return StarStyle(line: RGB(0xFFF0CC).mix(pal.primary, 0.25), lineAlpha: 0.82, core: RGB(0xFFFFFF), rim: RGB(0xF2CC7A), halo: RGB(0xFFF4DA),
                             tints: [RGB(0xF2CC7A), RGB(0xFFF4DA), pal.primary.mix(.white, 0.3), RGB(0xF2CC7A)], additive: true)
        } else {
            return StarStyle(line: pal.line(s), lineAlpha: 0.72, core: RGB(0xFFFDF6), rim: RGB(0xB8862F), halo: RGB(0xE0A94E),
                             tints: [RGB(0xC9962E), pal.line(s), RGB(0xC9962E), pal.line2(s)], additive: false)
        }
    }
}

/// 手で設計した星座形（カードとフレームで共有）。
struct Constellation {
    var points: [CGPoint]
    var edges: [(Int, Int)]
    var magnitudes: [Int]

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

    static func coreRadius(_ m: Int, _ s: CGFloat, _ d: Detail) -> CGFloat {
        d.w(s * [0.36, 0.3, 0.24, 0.17][min(m, 3)], minPx: [1.15, 0.95, 0.8, 0.62][min(m, 3)])
    }

    /// 星：小さな核＋細く長い光芒＋核の数倍に留めた暈。
    static func star(_ ctx: GraphicsContext, at p: CGPoint, magnitude m: Int, size s: CGFloat, tint: RGB, style st: StarStyle, d: Detail,
                     circled: Bool = false, spin: CGFloat = 0) {
        let core = coreRadius(m, s, d)
        var c = ctx
        if st.additive { c.blendMode = .plusLighter }
        let haloR = core * [3.8, 3.0, 2.2, 0][min(m, 3)]
        if haloR > 0 {
            let a = [0.38, 0.28, 0.18, 0][min(m, 3)] * (st.additive ? 1 : 0.55)
            c.fill(disc(p, haloR), with: .radialGradient(Gradient(stops: [
                .init(color: st.halo.c(a), location: 0), .init(color: tint.c(a * 0.45), location: 0.35), .init(color: tint.c(0), location: 1),
            ]), center: p, startRadius: 0, endRadius: haloR))
        }
        var sc = ctx
        sc.translateBy(x: p.x, y: p.y)
        sc.rotate(by: .radians(spin))
        let spike = st.additive ? st.halo : st.rim
        if m == 0 {
            sc.fill(sparklePath(long: max(core * 6.5, d.minWidth(5)), waist: d.w(core * 0.17, minPx: 0.3)), with: .color(spike.c(0.95)))
            sc.rotate(by: .radians(.pi / 4))
            sc.fill(sparklePath(long: core * 3, waist: d.w(core * 0.15, minPx: 0.26)), with: .color(spike.c(0.5)))
        } else if m == 1 && d.px(core) > 1.0 {
            sc.fill(sparklePath(long: core * 4.2, waist: d.w(core * 0.17, minPx: 0.28)), with: .color(spike.c(0.75)))
        }
        ctx.fill(disc(p, core), with: .radialGradient(Gradient(colors: [st.core.c(), st.core.mix(tint, 0.3).c(), tint.c()]), center: p, startRadius: 0, endRadius: core * 1.05))
        if !st.additive {
            ctx.stroke(disc(p, core), with: .color(st.rim.c(0.6)), lineWidth: d.w(core * 0.2, minPx: 0.35))
        }
        if circled {
            ctx.stroke(disc(p, core * (m == 0 ? 3.4 : 4.2)), with: .color(st.rim.c(0.85)), lineWidth: d.w(core * 0.2, minPx: 0.45))
        }
    }

    static func constellation(_ ctx: GraphicsContext, _ con: Constellation, map: (CGPoint) -> CGPoint, starSize: CGFloat,
                              lineWidth: CGFloat, style st: StarStyle, d: Detail, dashed: Bool = false, circledIndex: Int? = nil, spin: CGFloat = 0) {
        let pts = con.points.map(map)
        var lines = Path()
        for (a, b) in con.edges {
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
        ctx.stroke(lines, with: .color(st.line.c(st.lineAlpha)), style: StrokeStyle(lineWidth: w, lineCap: .round, dash: dashed ? [w * 3, w * 3] : []))
        for (i, p) in pts.enumerated() {
            star(ctx, at: p, magnitude: con.magnitudes[i], size: starSize, tint: st.tints[i % st.tints.count], style: st, d: d, circled: i == circledIndex, spin: spin)
        }
    }
}

// 霜：六方晶の樹枝状結晶（60°で枝分かれ）と雪華。
import SwiftUI

enum Frost {
    struct Seg { var a: CGPoint; var b: CGPoint; var w: CGFloat; var depth: Int }

    /// 樹枝状の霜（羊歯のような氷）。60°の側枝を互い違いに出し、先端は二又。
    static func dendrite(from p: CGPoint, angle: CGFloat, length L: CGFloat, width w: CGFloat, depth: Int,
                         rng: inout SeededRNG, accept: (CGPoint) -> Bool, out: inout [Seg]) {
        let end = p + CGPoint.polar(L, angle)
        guard accept(end) else {
            // 範囲外へ伸びる枝は短くして終える
            let half = p + CGPoint.polar(L * 0.5, angle)
            if accept(half) { out.append(Seg(a: p, b: half, w: w, depth: depth)) }
            return
        }
        out.append(Seg(a: p, b: end, w: w, depth: depth))
        guard depth > 0 else { return }
        let sides = Int(2 + rng.range(0, 2.6))
        for i in 0..<sides {
            let t = 0.22 + 0.62 * CGFloat(i) / CGFloat(max(1, sides - 1)) + rng.range(-0.05, 0.05)
            let q = p + CGPoint.polar(L * t, angle)
            let sideL = L * (0.5 - 0.28 * t) * rng.range(0.8, 1.15)
            for sign in [CGFloat(-1), 1] where rng.chance(depth >= 2 ? 0.95 : 0.8) {
                dendrite(from: q, angle: angle + sign * deg(60) + rng.range(-0.05, 0.05), length: sideL, width: w * 0.62,
                         depth: depth - 1, rng: &rng, accept: accept, out: &out)
            }
        }
        // 先端の小さな二又
        if depth >= 1 {
            for sign in [CGFloat(-1), 1] {
                let tip = end + CGPoint.polar(L * 0.16, angle + sign * deg(30))
                if accept(tip) { out.append(Seg(a: end, b: tip, w: w * 0.5, depth: 0)) }
            }
        }
    }

    /// 氷の線：外側に淡い光（宵）／白い縁取り（曙）を置いてから芯を描く
    static func drawSegs(_ ctx: GraphicsContext, _ segs: [Seg], s: DecoScheme, pal: ItemPalette, d: Detail, minPx: CGFloat = 0.45) {
        let core = s.isDark ? pal.secondary.mix(.white, 0.35) : pal.line(s)
        let edge = s.isDark ? pal.primary : RGB.white
        var halo = Path(), lines: [(Path, CGFloat)] = []
        for sg in segs {
            var p = Path(); p.move(to: sg.a); p.addLine(to: sg.b)
            halo.addPath(p)
            lines.append((p, d.w(sg.w, minPx: minPx)))
        }
        let maxW = segs.map(\.w).max() ?? 0.01
        ctx.stroke(halo, with: .color(edge.c(s.isDark ? 0.22 : 0.9)), style: StrokeStyle(lineWidth: d.w(maxW * 1.9, minPx: minPx * 2), lineCap: .round))
        for (p, w) in lines {
            ctx.stroke(p, with: .color(core.c(s.isDark ? 0.92 : 0.85)), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
    }

    /// 六花（雪の結晶）
    static func snowflake(_ ctx: GraphicsContext, at p: CGPoint, radius R: CGFloat, rotation: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        var segs: [Seg] = []
        let w = R * 0.07
        for i in 0..<6 {
            let a = rotation + CGFloat(i) * .pi / 3
            segs.append(Seg(a: p, b: p + CGPoint.polar(R, a), w: w, depth: 2))
            for (t, l) in [(CGFloat(0.38), CGFloat(0.34)), (0.62, 0.26), (0.82, 0.16)] {
                let q = p + CGPoint.polar(R * t, a)
                for sign in [CGFloat(-1), 1] {
                    segs.append(Seg(a: q, b: q + CGPoint.polar(R * l, a + sign * .pi / 3), w: w * 0.7, depth: 1))
                }
            }
        }
        drawSegs(ctx, segs, s: s, pal: pal, d: d, minPx: 0.4)
        // 中心の六角板
        var hex = Path()
        for i in 0..<6 {
            let q = p + CGPoint.polar(R * 0.17, rotation + CGFloat(i) * .pi / 3 + .pi / 6)
            if i == 0 { hex.move(to: q) } else { hex.addLine(to: q) }
        }
        hex.closeSubpath()
        ctx.fill(hex, with: .color((s.isDark ? pal.highlight(s) : pal.line(s)).c(0.55)))
        ctx.stroke(hex, with: .color((s.isDark ? RGB.white : pal.line(s)).c(0.85)), lineWidth: d.w(w * 0.6, minPx: 0.35))
    }

    static func glint(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, s: DecoScheme, pal: ItemPalette) {
        var c = ctx
        if s.isDark { c.blendMode = .plusLighter }
        c.translateBy(x: p.x, y: p.y)
        c.fill(Celestial.sparklePath(long: r, waist: r * 0.12), with: .color((s.isDark ? RGB.white : pal.line(s)).c(0.95)))
        c.rotate(by: .radians(.pi / 4))
        c.fill(Celestial.sparklePath(long: r * 0.45, waist: r * 0.1), with: .color((s.isDark ? RGB.white : pal.line(s)).c(0.6)))
    }
}

// MARK: - 霜縁

enum FrostMotif: DecoMotif {
    static func density(_ a: CGFloat) -> CGFloat { 0.3 + 0.8 * angularBump(a, 214, 34) + 0.7 * angularBump(a, 38, 30) }

    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0xF205)
        let q = d.quality, boost = d.boost
        let accept: (CGPoint) -> Bool = { p in let r = p.length; return r > 0.9 && r < 1.28 }

        // 1) 氷の縁：細い二重線と、その間に凍った面の薄い板
        ops.append(DrawOp(z: 0) { c in
            var band = Path()
            band.addPath(disc(.zero, 1.03)); band.addPath(disc(.zero, 0.97))
            c.fill(band, with: .color((s.isDark ? pal.primary : pal.line(s)).c(s.isDark ? 0.14 : 0.08)), style: FillStyle(eoFill: true))
            c.stroke(disc(.zero, 0.97), with: .color(pal.line(s).c(0.75)), lineWidth: d.w(0.004 * boost, minPx: 0.7))
            c.stroke(disc(.zero, 1.03), with: .color((s.isDark ? pal.secondary : pal.line2(s)).c(0.8)), lineWidth: d.w(0.003 * boost, minPx: 0.6))
        })
        // 縁の上の小さな氷の刻み（結晶の面）
        if q > 0.3 {
            var ticks = Path()
            for i in 0..<120 {
                let a = CGFloat(i) / 120 * 2 * .pi
                guard rng.chance(0.55) else { continue }
                let p = CGPoint.polar(1.0, a)
                let ang = a + (rng.chance(0.5) ? deg(60) : -deg(60))
                ticks.move(to: p - CGPoint.polar(0.018, ang))
                ticks.addLine(to: p + CGPoint.polar(0.018, ang))
            }
            ops.append(DrawOp(z: 0.05) { c in
                c.stroke(ticks, with: .color((s.isDark ? pal.highlight(s) : pal.line(s)).c(0.45)), lineWidth: d.w(0.0025, minPx: 0.4))
            })
        }

        // 2) 樹枝状の霜：縁から外へ・縁に沿って伸びる。対角で濃い
        var segs: [Frost.Seg] = []
        var a: CGFloat = 0
        while a < 360 {
            let ang = deg(a + rng.range(-3, 3))
            let dens = density(ang)
            if rng.unit() < min(1, dens) * d.keep + 0.12 {
                let base = CGPoint.polar(rng.range(0.99, 1.03), ang)
                let tangentSign: CGFloat = rng.sign()
                // 外向き（法線から±40°）と、縁に沿って寝る枝を混ぜる
                let along = rng.chance(0.35)
                let dir = along ? ang + tangentSign * deg(rng.range(62, 80)) : ang + rng.range(-0.6, 0.6)
                let L = (along ? rng.range(0.1, 0.17) : rng.range(0.09, 0.2)) * (0.7 + 0.45 * min(1, dens)) * sqrt(boost)
                Frost.dendrite(from: base, angle: dir, length: L, width: 0.0075 * boost, depth: q < 0.4 ? 1 : 2,
                               rng: &rng, accept: accept, out: &segs)
            }
            a += rng.range(6, 10) / max(0.4, dens) * (q < 0.4 ? 1.8 : 1)
        }
        // 縁の内側へ少しだけ入る短い霜（アバターに霜が降りた感じ。顔は隠さない）
        if q > 0.4 {
            for _ in 0..<10 {
                let ang = deg(rng.range(0, 360))
                guard rng.unit() < density(ang) * 0.8 else { continue }
                let base = CGPoint.polar(0.97, ang)
                Frost.dendrite(from: base, angle: ang + .pi + rng.range(-0.5, 0.5), length: rng.range(0.035, 0.06), width: 0.005,
                               depth: 1, rng: &rng, accept: { p in p.length > 0.89 && p.length < 1.0 }, out: &segs)
            }
        }
        let frost = segs
        ops.append(DrawOp(z: 0.3) { c in Frost.drawSegs(c, frost, s: s, pal: pal, d: d, minPx: q < 0.4 ? 0.7 : 0.45) })

        // 3) 雪華：対角に大小、ほかに小さく
        let flakes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(214, 1.17, 0.1, 0.1), (40, 1.16, 0.085, 0.4), (128, 1.13, 0.05, 0.2), (300, 1.14, 0.045, 0.0)]
        for (i, f) in flakes.enumerated() where CGFloat(i) < 2 + 2 * q {
            let p = CGPoint.polar(f.1, deg(f.0))
            ops.append(DrawOp(z: 0.6 + Double(i) * 0.01) { c in
                if s.isDark {
                    c.drawLayer { l in
                        l.addFilter(.blur(radius: f.2 * 0.35))
                        l.fill(disc(p, f.2 * 0.9), with: .color(pal.primary.c(0.3)))
                    }
                }
                Frost.snowflake(c, at: p, radius: f.2 * boost, rotation: f.3, s: s, pal: pal, d: d)
            })
        }
        // 4) きらめき
        if q > 0.4 {
            for _ in 0..<9 {
                let ang = deg(rng.range(0, 360))
                let p = CGPoint.polar(rng.range(0.98, 1.2), ang)
                let r = rng.range(0.012, 0.024)
                ops.append(DrawOp(z: 1) { c in Frost.glint(c, p, r, s: s, pal: pal) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0xF2)
        var inner = ctx
        inner.clip(to: cc.shape)

        // すりガラスの霜（縁ほど濃い細かな粒）
        if !cc.tiny {
            var g = SeededRNG(77)
            for _ in 0..<1400 {
                let p = CGPoint(x: cc.rect.minX + g.unit() * cc.rect.width, y: cc.rect.minY + g.unit() * cc.rect.height)
                let ex = min(p.x - cc.rect.minX, cc.rect.maxX - p.x) / (cc.rect.width / 2)
                let ey = min(p.y - cc.rect.minY, cc.rect.maxY - p.y) / (cc.rect.height / 2)
                let edge = 1 - min(ex, ey)
                guard g.unit() < pow(edge, 4) * 1.4 else { continue }
                inner.fill(disc(p, g.range(0.25, 0.7) * k), with: .color((s.isDark ? pal.highlight(s) : RGB.white).c(Double(g.range(0.25, 0.6)))))
            }
        }

        // 角から忍び込む霜の羊歯（左上は控えめ、右下を主役に）。本文列は避ける
        var segs: [Frost.Seg] = []
        var rng = SeededRNG(0xF3)
        let zone = cc.textZone.insetBy(dx: -6 * k, dy: -6 * k)
        let accept: (CGPoint) -> Bool = { p in cc.rect.insetBy(dx: 3 * k, dy: 3 * k).contains(p) && !zone.contains(p) }
        let corners: [(CGPoint, CGFloat, Int, CGFloat)] = [(cc.br, deg(-135), cc.tiny ? 4 : 9, 1.0), (cc.tl, deg(45), cc.tiny ? 3 : 6, 0.75),
                                                          (cc.tr, deg(135), cc.tiny ? 0 : 3, 0.5), (cc.bl, deg(-45), cc.tiny ? 0 : 4, 0.6)]
        for (corner, dirA, count, scale) in corners {
            for i in 0..<count {
                let spread = (CGFloat(i) / CGFloat(max(1, count - 1)) - 0.5) * deg(100)
                let origin = corner + CGPoint.polar(rng.range(2, 8) * k, dirA + spread)
                let L = rng.range(22, 42) * k * scale * (abs(spread) > deg(30) ? 1.25 : 0.9) * (cc.tiny ? 1.6 : 1)
                Frost.dendrite(from: origin, angle: dirA + spread, length: L, width: 0.85 * k * scale * (cc.tiny ? 1.6 : 1), depth: cc.tiny ? 1 : 2,
                               rng: &rng, accept: accept, out: &segs)
            }
        }
        Frost.drawSegs(inner, segs, s: s, pal: pal, d: d)

        // 雪華
        let flakes: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 34 * k), 9, 0.2), (CGPoint(x: cc.rect.maxX - 70 * k, y: cc.rect.maxY - 18 * k), 5, 0.5),
            (CGPoint(x: cc.rect.minX + 18 * k, y: cc.rect.maxY - 22 * k), 6, 0.1), (CGPoint(x: cc.rect.maxX - 18 * k, y: cc.rect.minY + 22 * k), 5, 0.3),
        ]
        for (i, f) in flakes.enumerated() where !cc.tiny || i == 0 {
            Frost.snowflake(ctx, at: f.0, radius: f.1 * k * (cc.tiny ? 1.4 : 1), rotation: f.2, s: s, pal: pal, d: d)
        }
        if !cc.tiny {
            for _ in 0..<10 {
                let p = CGPoint(x: cc.rect.maxX - rng.range(8, 120) * k, y: cc.rect.maxY - rng.range(8, 60) * k)
                if zone.contains(p) { continue }
                Frost.glint(ctx, p, rng.range(2, 4) * k, s: s, pal: pal)
            }
        }

        CardBase.drawRule(ctx, cc, gap: 26) { c, p, flip in
            Frost.snowflake(c, at: CGPoint(x: p.x, y: p.y + (flip ? -1.2 : 1.2) * k), radius: 5.6 * k, rotation: 0, s: s, pal: pal, d: d)
        }
    }
}

// 炎の部品と「灯影」。炎は輪から立ち上がる細い舌（火焔光背の様式化）で、全面の火の輪にはしない。
import SwiftUI

enum Flame {
    struct Colors { var core: RGB; var mid: RGB; var outer: RGB; var tip: RGB; var base: RGB }

    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> Colors {
        if s.isDark {
            return Colors(core: RGB(0xFFF4DC), mid: RGB(0xFFC98A), outer: pal.primary, tip: pal.secondary, base: RGB(0x8E8CFF))
        }
        return Colors(core: RGB(0xFFE3B0), mid: RGB(0xF09A4A), outer: pal.line(s), tip: pal.line2(s), base: RGB(0x6C63D9))
    }

    /// 輪から立ち上がる炎の舌。中心線は法線方向へ伸びつつ流れの向きへ寝る。先端はわずかに巻く。
    static func tongue(_ ctx: GraphicsContext, base p0: CGPoint, normal n: CGPoint, flow t: CGPoint, height h: CGFloat, width w0: CGFloat,
                       curl: CGFloat, lean: CGFloat = 0.55, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var pts: [CGPoint] = [], ws: [CGFloat] = []
        let steps = 28
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let bend = h * (lean * u * u + curl * pow(u, 4))
            let sway = h * 0.1 * sin(.pi * u * 1.6)
            pts.append(p0 + n * (h * u) + t * (bend + sway))
            ws.append(w0 * pow(1 - u, 0.75) * (0.75 + 0.25 * sin(.pi * min(1, u * 1.4))))
        }
        let outer = ribbonPath(pts, widths: ws)
        let tip = pts.last!
        var c = ctx
        if s.isDark { c.blendMode = .plusLighter }
        c.fill(outer, with: .linearGradient(Gradient(stops: [
            .init(color: col.outer.c(s.isDark ? 0.75 : 0.85), location: 0),
            .init(color: col.outer.mix(col.tip, 0.5).c(s.isDark ? 0.6 : 0.7), location: 0.55),
            .init(color: col.tip.c(0), location: 1),
        ]), startPoint: p0, endPoint: tip))
        // 芯（明るい内炎）
        let coreN = Int(Double(steps) * 0.62)
        let corePts = Array(pts.prefix(coreN))
        let coreWs = ws.prefix(coreN).enumerated().map { (i, w) in w * 0.45 * (1 - CGFloat(i) / CGFloat(coreN)) + 0.0001 }
        c.fill(ribbonPath(corePts, widths: coreWs), with: .linearGradient(Gradient(colors: [col.core.c(0.95), col.mid.c(0.7), col.mid.c(0)]),
                                                                          startPoint: p0, endPoint: corePts.last!))
        if !s.isDark {
            ctx.stroke(outer, with: .color(col.outer.c(0.35)), lineWidth: d.w(w0 * 0.05, minPx: 0.35))
        }
    }

    /// 蝋燭の一本（カード用）：蝋の胴・溶けた縁と垂れ・芯・炎・胴に映る光
    static func candle(_ ctx: GraphicsContext, base: CGPoint, width W: CGFloat, height H: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let col = colors(s, pal)
        let wax = s.isDark ? RGB(0xF7E6DA) : RGB(0xFFF4EA)
        let waxShade = s.isDark ? RGB(0xC9A6B4) : RGB(0xE8C9B8)
        let left = base.x - W / 2, top = base.y - H
        // 胴
        var body = Path()
        body.move(to: CGPoint(x: left, y: base.y))
        body.addLine(to: CGPoint(x: left, y: top + W * 0.12))
        // 溶けた上縁（波打つ）
        for i in 0...8 {
            let x = left + W * CGFloat(i) / 8
            body.addLine(to: CGPoint(x: x, y: top + W * 0.12 + sin(CGFloat(i) * 1.7 + rng.range(0, 1)) * W * 0.05))
        }
        body.addLine(to: CGPoint(x: left + W, y: base.y))
        body.closeSubpath()
        ctx.fill(body, with: .linearGradient(Gradient(colors: [waxShade.c(), wax.c(), wax.mix(col.mid, 0.12).c(), waxShade.c()]),
                                             startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + W, y: 0)))
        // 垂れ
        for _ in 0..<3 {
            let x = left + W * rng.range(0.12, 0.88)
            let len = H * rng.range(0.12, 0.35)
            var drip = Path()
            drip.addRoundedRect(in: CGRect(x: x - W * 0.07, y: top + W * 0.1, width: W * 0.14, height: len), cornerSize: CGSize(width: W * 0.07, height: W * 0.07))
            ctx.fill(drip, with: .color(wax.mix(.white, 0.4).c(0.9)))
        }
        // 上端の光（炎に照らされる）
        ctx.fill(Path(CGRect(x: left, y: top + W * 0.05, width: W, height: H * 0.4)), with: .linearGradient(Gradient(colors: [col.mid.c(0.35), col.mid.c(0)]),
                                                                                                             startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + H * 0.4)))
        ctx.stroke(body, with: .color(waxShade.mix(.black, 0.25).c(0.45)), lineWidth: d.w(W * 0.025, minPx: 0.4))
        // 芯
        var wick = Path()
        wick.move(to: CGPoint(x: base.x, y: top + W * 0.1))
        wick.addQuadCurve(to: CGPoint(x: base.x + W * 0.04, y: top - W * 0.16), control: CGPoint(x: base.x - W * 0.04, y: top - W * 0.02))
        ctx.stroke(wick, with: .color(RGB(0x2A1C24).c(0.85)), style: StrokeStyle(lineWidth: d.w(W * 0.05, minPx: 0.5), lineCap: .round))
        // 炎
        let fb = CGPoint(x: base.x + W * 0.03, y: top - W * 0.12)
        if s.isDark {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: W * 0.55))
                l.fill(disc(CGPoint(x: fb.x, y: fb.y - W * 0.5), W * 0.9), with: .color(col.mid.c(0.45)))
            }
        }
        tongue(ctx, base: CGPoint(x: fb.x, y: fb.y + W * 0.05), normal: CGPoint(x: 0, y: -1), flow: CGPoint(x: 1, y: 0), height: W * 1.25, width: W * 0.42,
               curl: 0.05, s: s, pal: pal, d: d)
        // 炎の根元の青
        ctx.fill(Path(ellipseIn: CGRect(x: fb.x - W * 0.08, y: fb.y - W * 0.12, width: W * 0.16, height: W * 0.16)), with: .color(col.base.c(0.55)))
    }

    static func ember(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var c = ctx
        if s.isDark {
            c.blendMode = .plusLighter
            c.fill(disc(p, r * 3), with: .radialGradient(Gradient(colors: [col.outer.c(0.35), col.outer.c(0)]), center: p, startRadius: 0, endRadius: r * 3))
        }
        c.fill(disc(p, d.w(r, minPx: 0.6)), with: .color((s.isDark ? col.core : col.outer).c(0.95)))
    }
}

// MARK: - 灯影

enum CandleMotif: DecoMotif {
    static func density(_ a: CGFloat) -> CGFloat { 0.35 + 0.75 * angularBump(a, 214, 36) + 0.6 * angularBump(a, 36, 32) }

    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0xCA4D)
        let q = d.quality, boost = d.boost
        let col = Flame.colors(s, pal)

        // 1) 灯の輪：暖色の細い輪。炎の近くほど明るく照らされ、離れると陰る（灯と影）
        ops.append(DrawOp(z: 0) { c in
            if s.isDark {
                c.drawLayer { l in
                    l.addFilter(.blur(radius: 0.03))
                    var band = Path(); band.addPath(disc(.zero, 1.04)); band.addPath(disc(.zero, 0.96))
                    l.fill(band, with: .color(col.outer.c(0.28)), style: FillStyle(eoFill: true))
                }
            }
            var pts: [CGPoint] = [], ws: [CGFloat] = [], als: [Double] = []
            for i in 0...360 {
                let a = CGFloat(i) / 360 * 2 * .pi
                let lit = min(1, density(a) * 0.85)
                pts.append(CGPoint.polar(1.0 + 0.004 * sin(6 * a), a))
                ws.append(d.w((0.007 + 0.006 * lit) * boost, minPx: q < 0.4 ? 0.9 : 0.6))
                als.append(Double(0.35 + 0.65 * lit))
            }
            drawVaryingStroke(c, points: pts, widths: ws, alphas: als, color: col.outer)
            drawVaryingStroke(c, points: pts.map { $0 * 0.996 }, widths: ws.map { $0 * 0.35 }, alphas: als.map { $0 * 0.9 }, color: col.core)
            c.stroke(disc(.zero, 0.955), with: .color(col.tip.c(0.35)), lineWidth: d.w(0.0025, minPx: 0.4))
        })

        // 2) 炎の舌：対角から湧き、輪に沿って長く寝て流れる（放射状の棘にしない）。上下は間を空ける
        for (ci, cluster) in [(CGFloat(214), CGFloat(1)), (CGFloat(36), CGFloat(1))].enumerated() {
            let count = q < 0.4 ? 4 : 8
            for j in 0..<count {
                let spread = (CGFloat(j) / CGFloat(count - 1) - 0.45) * deg(ci == 0 ? 96 : 80)
                let ang = deg(cluster.0) + spread + rng.range(-0.04, 0.04)
                let falloff = 1 - abs(spread) / deg(60)
                let n = CGPoint(x: cos(ang), y: sin(ang))
                let t = CGPoint(x: -sin(ang), y: cos(ang))
                let h = (0.1 + 0.16 * max(0.15, falloff) * rng.range(0.8, 1.1)) * (ci == 0 ? 1 : 0.88) * (q < 0.4 ? 1.1 : 1)
                let w = (0.035 + 0.03 * max(0.2, falloff)) * boost
                let p0 = CGPoint.polar(1.0, ang)
                let curl = rng.range(0.1, 0.6), lean = rng.range(0.9, 1.35)
                let z = 0.5 + Double(ci) * 0.1 + Double(j) * 0.001 + (j % 2 == 0 ? 0 : -0.05)
                ops.append(DrawOp(z: z) { c in
                    Flame.tongue(c, base: p0, normal: n, flow: t, height: h, width: w, curl: curl, lean: lean, s: s, pal: pal, d: d)
                })
                // 付き添う小さな舌（揺らぎ）
                if q > 0.35 && j % 2 == 0 {
                    let p1 = CGPoint.polar(1.0, ang - deg(5))
                    ops.append(DrawOp(z: z - 0.02) { c in
                        Flame.tongue(c, base: p1, normal: n, flow: t, height: h * 0.55, width: w * 0.6, curl: curl * 0.6, lean: lean * 0.8, s: s, pal: pal, d: d)
                    })
                }
            }
        }
        // 輪の残りに点在する小さな灯
        for ad in [CGFloat(120), 300, 160, 350] where q > 0.3 {
            let ang = deg(ad)
            let n = CGPoint(x: cos(ang), y: sin(ang)), t = CGPoint(x: -sin(ang), y: cos(ang))
            let p0 = CGPoint.polar(1.0, ang)
            ops.append(DrawOp(z: 0.45) { c in
                Flame.tongue(c, base: p0, normal: n, flow: t, height: 0.07, width: 0.026 * boost, curl: 0.3, lean: 1.0, s: s, pal: pal, d: d)
            })
        }

        // 3) 火の粉：外へ舞い上がる
        let embers = Int(6 + 18 * q)
        for _ in 0..<embers {
            var ang: CGFloat
            repeat { ang = deg(rng.range(0, 360)) } while rng.unit() > density(ang) * 0.8
            let p = CGPoint.polar(rng.range(1.12, 1.27), ang + rng.range(-0.08, 0.08))
            let r = rng.range(0.004, 0.009) * boost
            ops.append(DrawOp(z: 1) { c in Flame.ember(c, p, r, s: s, pal: pal, d: d) })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = Flame.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0xCA, airAnchors: [
            (cc.tl, 0.5, pal.secondary, s.isDark ? 0.12 : 0.1),
            (CGPoint(x: cc.rect.maxX - 40 * k, y: cc.rect.maxY - 30 * k), 0.75, pal.primary, s.isDark ? 0.24 : 0.14),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        // 蝋燭の光だまり（右下）
        var lc = inner
        if s.isDark { lc.blendMode = .plusLighter }
        lc.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [col.mid.c(s.isDark ? 0.22 : 0.16), col.outer.c(s.isDark ? 0.08 : 0.05), col.outer.c(0)]),
                                                     center: CGPoint(x: cc.rect.maxX - 28 * k, y: cc.rect.maxY - 30 * k), startRadius: 0, endRadius: 120 * k))
        if !cc.tiny {
            // 左上の煙
            var smoke: [CGPoint] = []
            for i in 0...40 {
                let t = CGFloat(i) / 40
                smoke.append(CGPoint(x: cc.rect.minX + 18 * k + sin(t * 7) * 6 * k * t, y: cc.rect.minY + 74 * k - t * 62 * k))
            }
            let ws = (0...40).map { i -> CGFloat in d.w(1.0 * k * sin(CGFloat.pi * CGFloat(i) / 40), minPx: 0.4) }
            drawTaperedStroke(inner, points: smoke, widths: ws, color: s.isDark ? RGB(0xB9AFCF) : RGB(0x9C8E98), alpha: 0.35)
        }
        // 蝋燭（右下に大小、左下に小）
        let tall = CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 9 * k)
        Flame.candle(ctx, base: tall, width: 11 * k, height: 40 * k, s: s, pal: pal, d: d, seed: 3)
        Flame.candle(ctx, base: CGPoint(x: tall.x - 18 * k, y: tall.y), width: 10 * k, height: 24 * k, s: s, pal: pal, d: d, seed: 5)
        if !cc.tiny {
            Flame.candle(ctx, base: CGPoint(x: cc.rect.minX + 22 * k, y: cc.rect.maxY - 9 * k), width: 8 * k, height: 18 * k, s: s, pal: pal, d: d, seed: 7)
            var rng = SeededRNG(0xCC)
            for _ in 0..<12 {
                let p = CGPoint(x: tall.x - rng.range(-10, 60) * k, y: tall.y - rng.range(50, 110) * k)
                if cc.textZone.contains(p) { continue }
                Flame.ember(ctx, p, rng.range(0.5, 1.1) * k, s: s, pal: pal, d: d)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            if flip { return }
            Flame.tongue(c, base: CGPoint(x: p.x, y: p.y + 4 * k), normal: CGPoint(x: 0, y: -1), flow: CGPoint(x: 1, y: 0), height: 12 * k, width: 4.4 * k,
                         curl: 0.15, s: s, pal: pal, d: d)
        }
    }
}

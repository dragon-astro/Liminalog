// 光の部品と「暁線」「陽線」。
import SwiftUI

enum Sun {
    /// 陽の色。暖色側（橙寄り）を体に、もう一方を縁と光線の差し色にする
    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> (core: RGB, body: RGB, edge: RGB, ray: RGB) {
        let warmFirst = pal.primary.b < pal.secondary.b
        let warm = warmFirst ? pal.primary : pal.secondary, other = warmFirst ? pal.secondary : pal.primary
        if s.isDark { return (RGB(0xFFF6E2), warm.mix(RGB(0xFFE3A3), 0.35), warm, other) }
        return (RGB(0xFFFBF0), warm.withLightness(0.76), warm.withLightness(0.45, saturationBoost: 0.9), other.withLightness(0.5))
    }

    /// 太陽の円盤：芯が白く、縁へ向かって色づく。宵では控えめな暈を一枚。
    static func disc(_ ctx: GraphicsContext, center p: CGPoint, radius r: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, halo: Bool = true) {
        let col = colors(s, pal)
        if halo {
            var c = ctx
            if s.isDark { c.blendMode = .plusLighter }
            c.fill(liminalDisc(p, r * 2.2), with: .radialGradient(Gradient(colors: [col.body.c(s.isDark ? 0.35 : 0.3), col.edge.c(0)]), center: p, startRadius: r * 0.6, endRadius: r * 2.2))
        }
        ctx.fill(liminalDisc(p, r), with: .radialGradient(Gradient(stops: [
            .init(color: col.core.c(), location: 0), .init(color: col.body.c(), location: 0.6), .init(color: col.edge.c(), location: 1),
        ]), center: p, startRadius: 0, endRadius: r))
        ctx.stroke(liminalDisc(p, r), with: .color(col.edge.mix(s.isDark ? .white : .black, 0.15).c(0.7)), lineWidth: d.w(r * 0.04, minPx: 0.4))
    }

    /// 先細りの光線（三角形）
    static func ray(_ ctx: GraphicsContext, from p: CGPoint, angle: CGFloat, length L: CGFloat, width w: CGFloat, color: RGB, alpha: Double) {
        let dir = CGPoint.polar(1, angle), n = dir.perpendicular
        var tri = Path()
        tri.move(to: p + n * (w / 2)); tri.addLine(to: p + dir * L); tri.addLine(to: p - n * (w / 2)); tri.closeSubpath()
        ctx.fill(tri, with: .linearGradient(Gradient(colors: [color.c(alpha), color.c(0)]), startPoint: p, endPoint: p + dir * L))
    }
}

/// `disc` は Core で定義済み。名前の衝突を避けたラッパ。
func liminalDisc(_ p: CGPoint, _ r: CGFloat) -> Path { disc(p, r) }

// MARK: - 暁線

enum DawnMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let col = Sun.colors(s, pal)
        let top = s.isDark ? RGB(0xB79CFF) : RGB(0x7C5BC9)
        // 1) 夜明けの輪：上は夜の菫、下へ行くほど朝焼け（輪そのものが空の階調）
        ops.append(DrawOp(z: 0) { c in
            // 下半分に朝の光だまり
            var cc = c
            if s.isDark { cc.blendMode = .plusLighter }
            var band = Path(); band.addPath(liminalDisc(.zero, 1.25)); band.addPath(liminalDisc(.zero, 0.99))
            cc.fill(band, with: .radialGradient(Gradient(colors: [col.body.c(s.isDark ? 0.3 : 0.22), col.edge.c(0)]),
                                                center: CGPoint(x: 0, y: 1.0), startRadius: 0, endRadius: 0.55), style: FillStyle(eoFill: true))
            let ring = Gradient(stops: [
                .init(color: top.c(0.85), location: 0), .init(color: pal.line(s).c(0.95), location: 0.3),
                .init(color: col.body.c(), location: 0.5), .init(color: pal.line(s).c(0.95), location: 0.7), .init(color: top.c(0.85), location: 1),
            ])
            c.stroke(liminalDisc(.zero, 1.0), with: .conicGradient(ring, center: .zero, angle: .degrees(-90)), lineWidth: d.w(0.012 * boost, minPx: 1))
            c.stroke(liminalDisc(.zero, 0.995), with: .color(RGB.white.c(s.isDark ? 0.35 : 0.6)), lineWidth: d.w(0.003, minPx: 0.4))
        })
        // 2) 朝焼けの層雲（下半分の外側に、途切れた細い筋が重なる）
        var rng = SeededRNG(0xDA)
        for (li, r0) in [CGFloat(1.055), 1.1, 1.15, 1.2].enumerated() where q > 0.3 || li < 2 {
            var a: CGFloat = 25
            while a < 155 {
                let span = rng.range(14, 34)
                let gap = rng.range(5, 12)
                let a0 = a, a1 = min(155, a + span)
                var pts: [CGPoint] = []
                for i in 0...20 { let t = CGFloat(i) / 20; pts.append(CGPoint.polar(r0 + 0.004 * sin(t * 6), deg(a0 + (a1 - a0) * t))) }
                let fade = 1 - abs((a0 + a1) / 2 - 90) / 75
                let ws = (0...20).map { i -> CGFloat in d.w(0.013 * boost * (1 - CGFloat(li) * 0.16) * sin(CGFloat.pi * CGFloat(i) / 20), minPx: 0.5) }
                let color = li % 2 == 0 ? pal.line(s) : col.ray
                ops.append(DrawOp(z: 0.1) { c in drawTaperedStroke(c, points: pts, widths: ws, color: color, alpha: Double(0.25 + 0.6 * fade) * (1 - Double(li) * 0.15)) })
                a = a1 + gap
            }
        }
        // 3) 昇る陽：アバターの下縁から顔を出す（内側は隠す）＋扇の光
        let sunC = CGPoint.polar(1.0, deg(90))
        let sunR = 0.1 * boost
        ops.append(DrawOp(z: 0.5) { c in
            var cc = c
            var clip = Path(); clip.addPath(liminalDisc(.zero, 1.32)); clip.addPath(liminalDisc(.zero, 0.992))
            cc.clip(to: clip, style: FillStyle(eoFill: true))
            var rr = SeededRNG(0xDB)
            var rc = cc
            if s.isDark { rc.blendMode = .plusLighter }
            for i in 0..<(q < 0.4 ? 9 : 17) {
                let t = CGFloat(i) / CGFloat(q < 0.4 ? 8 : 16)
                let ang = deg(90) + (t - 0.5) * deg(150)
                let L = (i % 2 == 0 ? 0.25 : 0.15) * rr.range(0.85, 1.1) * (q < 0.4 ? 1.1 : 1)
                Sun.ray(rc, from: sunC + CGPoint.polar(sunR * 1.1, ang), angle: ang, length: L, width: (i % 2 == 0 ? 0.016 : 0.01) * boost, color: col.ray, alpha: 0.75)
            }
            Sun.disc(cc, center: sunC, radius: sunR, s: s, pal: pal, d: d)
        })
        // 4) 地平の光の線（陽の左右へ）
        ops.append(DrawOp(z: 0.45) { c in
            var pts: [CGPoint] = []
            for i in 0...40 { pts.append(CGPoint.polar(1.035, deg(40 + 100 * CGFloat(i) / 40))) }
            let ws = (0...40).map { i -> CGFloat in d.w(0.006 * boost * pow(sin(CGFloat.pi * CGFloat(i) / 40), 1.5), minPx: 0.5) }
            var cc = c
            if s.isDark { cc.blendMode = .plusLighter }
            drawTaperedStroke(cc, points: pts, widths: ws, color: s.isDark ? col.core : pal.line(s), alpha: 0.85)
        })
        // 5) 明けの明星（左上）と小さな星
        if q > 0.3 {
            let st = StarStyle.make(s, pal)
            for (ad, r, m) in [(CGFloat(232), CGFloat(1.16), 0), (CGFloat(305), CGFloat(1.13), 2), (CGFloat(258), CGFloat(1.22), 3)] {
                let p = CGPoint.polar(r, deg(ad))
                ops.append(DrawOp(z: 1) { c in Celestial.star(c, at: p, magnitude: m, size: 0.034, tint: st.tints[1], style: st, d: d) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = Sun.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0xD1, airAnchors: [
            (cc.tl, 0.45, RGB(0x8E7BE0), s.isDark ? 0.14 : 0.08),
            (CGPoint(x: cc.rect.midX + 40 * k, y: cc.rect.maxY), 0.85, pal.primary, s.isDark ? 0.22 : 0.16),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        let horizon = cc.rect.maxY - 20 * k
        // 朝焼けの空（下ほど色づく）
        inner.fill(Path(CGRect(x: cc.rect.minX, y: cc.rect.minY + cc.rect.height * 0.55, width: cc.rect.width, height: cc.rect.height * 0.45)),
                   with: .linearGradient(Gradient(colors: [pal.secondary.c(0), pal.secondary.c(s.isDark ? 0.14 : 0.12), pal.primary.c(s.isDark ? 0.22 : 0.18)]),
                                         startPoint: CGPoint(x: 0, y: cc.rect.minY + cc.rect.height * 0.55), endPoint: CGPoint(x: 0, y: horizon)))
        // 陽：地平線から半分
        let sun = CGPoint(x: cc.rect.midX + 34 * k, y: horizon)
        var upper = inner
        upper.clip(to: Path(CGRect(x: cc.rect.minX, y: cc.rect.minY, width: cc.rect.width, height: horizon - cc.rect.minY)))
        var glow = upper
        if s.isDark { glow.blendMode = .plusLighter }
        glow.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [col.body.c(s.isDark ? 0.4 : 0.35), col.edge.c(0)]), center: sun, startRadius: 6 * k, endRadius: 80 * k))
        if !cc.tiny {
            for i in 0..<13 {
                let ang = deg(180 + 180 * CGFloat(i + 1) / 14)
                Sun.ray(glow, from: sun + CGPoint.polar(16 * k, ang), angle: ang, length: (i % 2 == 0 ? 24 : 14) * k, width: (i % 2 == 0 ? 2.6 : 1.6) * k, color: col.ray, alpha: 0.5)
            }
        }
        Sun.disc(upper, center: sun, radius: 13 * k, s: s, pal: pal, d: d, halo: false)
        // 地平線と水面の照り返し
        var hl = Path(); hl.move(to: CGPoint(x: cc.rect.minX, y: horizon)); hl.addLine(to: CGPoint(x: cc.rect.maxX, y: horizon))
        inner.stroke(hl, with: .linearGradient(Gradient(colors: [pal.line(s).c(0), (s.isDark ? col.core : pal.line(s)).c(0.85), pal.line(s).c(0)]),
                                               startPoint: CGPoint(x: cc.rect.minX, y: 0), endPoint: CGPoint(x: cc.rect.maxX, y: 0)), lineWidth: d.w(0.8 * k, minPx: 0.8))
        var rng = SeededRNG(0xD2)
        for i in 0..<9 {
            let y = horizon + (2.2 + CGFloat(i) * 1.7) * k
            let w = (26 - CGFloat(i) * 2.2) * k * rng.range(0.7, 1.1)
            var line = Path()
            line.move(to: CGPoint(x: sun.x - w / 2 + rng.range(-3, 3) * k, y: y)); line.addLine(to: CGPoint(x: sun.x + w / 2 + rng.range(-3, 3) * k, y: y))
            inner.stroke(line, with: .color((s.isDark ? col.body : pal.line(s)).c(0.55 - Double(i) * 0.05)), style: StrokeStyle(lineWidth: d.w(0.8 * k, minPx: 0.6), lineCap: .round))
        }
        // 層雲の筋（本文の下と左右）
        if !cc.tiny {
            for (x0, x1, y, w) in [(CGFloat(0.02), CGFloat(0.3), CGFloat(-22), CGFloat(2.2)), (0.66, 0.98, -24, 2.0), (0.48, 0.8, -15, 1.4), (0.04, 0.2, -12, 1.2)] {
                var pts: [CGPoint] = []
                for i in 0...24 {
                    let t = CGFloat(i) / 24
                    pts.append(CGPoint(x: cc.rect.minX + cc.rect.width * (x0 + (x1 - x0) * t), y: horizon + y * k + sin(t * 3) * 1.2 * k))
                }
                Air.wisp(inner, points: pts, width: w * k, color: s.isDark ? pal.primary : pal.line(s), alpha: 0.6, d: d)
            }
            let st = StarStyle.make(s, pal)
            Celestial.star(ctx, at: CGPoint(x: cc.rect.maxX - 26 * k, y: cc.rect.minY + 28 * k), magnitude: 0, size: 5 * k, tint: st.tints[1], style: st, d: d)
            Celestial.star(ctx, at: CGPoint(x: cc.rect.maxX - 52 * k, y: cc.rect.minY + 18 * k), magnitude: 3, size: 4 * k, tint: st.tints[1], style: st, d: d)
        }
        CardBase.drawRule(ctx, cc, gap: 26) { c, p, flip in
            if flip { return }
            let q = CGPoint(x: p.x, y: p.y + 2.6 * k)
            var cc2 = c
            cc2.clip(to: Path(CGRect(x: q.x - 10 * k, y: q.y - 10 * k, width: 20 * k, height: 10 * k)))
            for i in 0..<5 {
                let ang = deg(180 + 180 * CGFloat(i + 1) / 6)
                Sun.ray(cc2, from: q + CGPoint.polar(4.6 * k, ang), angle: ang, length: 4.4 * k, width: 1.2 * k, color: col.ray, alpha: 0.9)
            }
            Sun.disc(cc2, center: q, radius: 4 * k, s: s, pal: pal, d: d, halo: false)
        }
    }
}

// MARK: - 陽線

enum SunlineMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let col = Sun.colors(s, pal)
        let sunAngle = deg(226)
        // 1) 二重の軌道
        ops.append(DrawOp(z: 0) { c in
            let g = Gradient(colors: [pal.line(s).c(), col.ray.c(), pal.line(s).c(), col.ray.c(), pal.line(s).c()])
            c.stroke(liminalDisc(.zero, 1.0), with: .conicGradient(g, center: .zero, angle: .radians(sunAngle)), lineWidth: d.w(0.009 * boost, minPx: 1))
            c.stroke(liminalDisc(.zero, 0.993), with: .color(RGB.white.c(s.isDark ? 0.3 : 0.6)), lineWidth: d.w(0.0025, minPx: 0.4))
            if q > 0.3 {
                c.stroke(liminalDisc(.zero, 1.085), with: .color(pal.line(s).c(0.55)), style: StrokeStyle(lineWidth: d.w(0.004, minPx: 0.6), lineCap: .round, dash: [0, 0.026]))
            }
        })
        // 2) 光環の線：長短が交互の細い光線。陽のある側ほど長い
        ops.append(DrawOp(z: 0.2) { c in
            var cc = c
            if s.isDark { cc.blendMode = .plusLighter }
            let n = q < 0.4 ? 36 : 72
            for i in 0..<n {
                let a = CGFloat(i) / CGFloat(n) * 2 * .pi
                let near = 0.4 + 0.6 * pow(max(0, cos(angleDelta(a, sunAngle) / 2)), 2)
                let long = i % 2 == 0
                let L = (long ? 0.24 : 0.1) * near * near * (i % 6 == 0 ? 1.25 : 1) * (q < 0.4 ? 1.15 : 1) + 0.02
                Sun.ray(cc, from: CGPoint.polar(1.02, a), angle: a, length: L, width: (long ? 0.012 : 0.008) * boost, color: long ? col.edge : col.ray,
                        alpha: Double(0.45 + 0.45 * near))
            }
        })
        // 3) 外の軌道に乗る小さな陽と、その光芒
        let sp = CGPoint.polar(1.11, sunAngle)
        ops.append(DrawOp(z: 0.6) { c in
            var cc = c
            if s.isDark { cc.blendMode = .plusLighter }
            for i in 0..<16 {
                let a = CGFloat(i) / 16 * 2 * .pi
                Sun.ray(cc, from: sp + CGPoint.polar(0.065 * boost, a), angle: a, length: (i % 2 == 0 ? 0.08 : 0.045) * boost, width: 0.012 * boost, color: col.edge, alpha: 0.85)
            }
            Sun.disc(c, center: sp, radius: 0.072 * boost, s: s, pal: pal, d: d)
        })
        // 4) 反対側の小さな光点
        if q > 0.35 {
            let st = StarStyle.make(s, pal)
            ops.append(DrawOp(z: 0.7) { c in
                Celestial.star(c, at: CGPoint.polar(1.085, sunAngle + .pi), magnitude: 1, size: 0.03, tint: st.tints[0], style: st, d: d)
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = Sun.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x5A, airAnchors: [
            (cc.tr, 0.8, pal.primary, s.isDark ? 0.24 : 0.18), (cc.bl, 0.45, pal.secondary, s.isDark ? 0.12 : 0.1),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        let sun = CGPoint(x: cc.rect.maxX - 18 * k, y: cc.rect.minY + 18 * k)
        // 縁に沿って走る陽の線（上辺と右辺に寝かせ、本文へは差し込ませない）
        var rc = inner
        if s.isDark { rc.blendMode = .plusLighter }
        var rng = SeededRNG(0x5B)
        let fans: [(CGFloat, CGFloat, Int)] = [(deg(176), deg(196), cc.tiny ? 4 : 9), (deg(84), deg(104), cc.tiny ? 3 : 7)]
        for (a0, a1, n) in fans {
            for i in 0..<n {
                let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(max(1, n - 1))
                let L = rng.range(80, 165) * k * (i % 2 == 0 ? 1 : 0.6)
                Sun.ray(rc, from: sun + CGPoint.polar(26 * k, a), angle: a, length: L, width: rng.range(2.4, 4.4) * k, color: i % 2 == 0 ? col.edge : col.ray, alpha: 0.5)
            }
        }
        // 陽を巡る弧
        for (r, dash) in [(CGFloat(34), false), (46, true), (60, false)] where !cc.tiny || r == 34 {
            var arc = Path()
            arc.addArc(center: sun, radius: r * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            inner.stroke(arc, with: .color(pal.line(s).c(0.55)), style: StrokeStyle(lineWidth: d.w((dash ? 1.0 : 0.6) * k, minPx: 0.6), lineCap: .round, dash: dash ? [0, 3.2 * k] : []))
        }
        // 光芒つきの陽
        var sc = ctx
        sc.clip(to: cc.shape)
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            Sun.ray(rc, from: sun + CGPoint.polar(17 * k, a), angle: a, length: (i % 2 == 0 ? 12 : 7) * k, width: 2.4 * k, color: col.edge, alpha: 0.8)
        }
        Sun.disc(sc, center: sun, radius: 15 * k, s: s, pal: pal, d: d)
        // 左下の小さな光点の連なり
        if !cc.tiny {
            let st = StarStyle.make(s, pal)
            for (dx, dy, m) in [(CGFloat(22), CGFloat(-26), 1), (40, -16, 3), (14, -46, 3)] {
                Celestial.star(ctx, at: CGPoint(x: cc.rect.minX + dx * k, y: cc.rect.maxY + dy * k), magnitude: m, size: 4 * k, tint: st.tints[0], style: st, d: d)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            var cc2 = c
            if s.isDark { cc2.blendMode = .plusLighter }
            for i in 0..<8 {
                let a = CGFloat(i) / 8 * 2 * .pi
                Sun.ray(cc2, from: p + CGPoint.polar(3.6 * k, a), angle: a, length: 3.6 * k, width: 1.2 * k, color: col.edge, alpha: 0.9)
            }
            Sun.disc(c, center: p, radius: 3 * k, s: s, pal: pal, d: d, halo: false)
        }
    }
}

// 花隅（桜：切れ込みのある五弁・蕾・散る花びら・細い枝）と、夜花（月下美人のような細い花弁が放射する夜の花・つる・蛍）。
import SwiftUI

enum Sakura {
    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> (petal: RGB, edge: RGB, center: RGB, twig: RGB, stamen: RGB) {
        if s.isDark { return (pal.primary.mix(.white, 0.45), pal.primary, pal.primary.mix(RGB(0xC0306A), 0.3), pal.secondary.withLightness(0.5, saturationBoost: 0.3), RGB(0xFFE3A3)) }
        return (pal.primary.mix(.white, 0.62), pal.primary.withLightness(0.62), pal.primary.withLightness(0.5), pal.secondary.withLightness(0.36, saturationBoost: 0.3), RGB(0xC9962E))
    }

    /// 切れ込みのある花びら（原点=付け根、+x=先端）
    static func petal(_ L: CGFloat, width w: CGFloat = 0.62) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: L * 0.92, y: -L * 0.2), control1: CGPoint(x: L * 0.2, y: -L * w * 0.7), control2: CGPoint(x: L * 0.8, y: -L * w * 0.75))
        p.addQuadCurve(to: CGPoint(x: L * 0.84, y: 0), control: CGPoint(x: L * 0.95, y: -L * 0.06))    // 切れ込み
        p.addQuadCurve(to: CGPoint(x: L * 0.92, y: L * 0.2), control: CGPoint(x: L * 0.95, y: L * 0.06))
        p.addCurve(to: .zero, control1: CGPoint(x: L * 0.8, y: L * w * 0.75), control2: CGPoint(x: L * 0.2, y: L * w * 0.7))
        p.closeSubpath()
        return p
    }

    static func blossom(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, rotation: CGFloat, tilt: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64, open: Int = 5) {
        var rng = SeededRNG(seed)
        let col = colors(s, pal)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: 1 - tilt)
        if !s.isDark {
            c.fill(disc(CGPoint(x: r * 0.08, y: r * 0.14), r * 1.02), with: .radialGradient(Gradient(colors: [RGB(0xA7774F).c(0.18), RGB(0xA7774F).c(0)]),
                                                                                        center: CGPoint(x: r * 0.08, y: r * 0.14), startRadius: r * 0.4, endRadius: r * 1.05))
        }
        for i in 0..<open {
            let a = CGFloat(i) / 5 * 2 * .pi + rng.range(-0.08, 0.08)
            var pc = c
            pc.rotate(by: .radians(a))
            let L = r * rng.range(0.92, 1.05)
            let shape = petal(L)
            pc.fill(shape, with: .radialGradient(Gradient(stops: [
                .init(color: col.center.c(0.95), location: 0), .init(color: col.petal.mix(col.edge, 0.35).c(0.97), location: 0.35),
                .init(color: col.petal.c(), location: 0.8), .init(color: col.edge.mix(col.petal, 0.4).c(), location: 1),
            ]), center: .zero, startRadius: 0, endRadius: L))
            if d.px(r) > 8 {
                for vv in [CGFloat(-0.12), 0, 0.12] {
                    var vein = Path(); vein.move(to: CGPoint(x: L * 0.12, y: 0)); vein.addQuadCurve(to: CGPoint(x: L * 0.62, y: L * vv), control: CGPoint(x: L * 0.4, y: L * vv * 0.3))
                    pc.stroke(vein, with: .color(col.edge.c(0.3)), lineWidth: d.w(r * 0.02, minPx: 0.3))
                }
            }
            pc.stroke(shape, with: .color(col.edge.c(s.isDark ? 0.5 : 0.45)), lineWidth: d.w(r * 0.025, minPx: 0.3))
        }
        // しべ
        if d.px(r) > 5 {
            for i in 0..<9 {
                let a = CGFloat(i) / 9 * 2 * .pi + 0.3
                let end = CGPoint.polar(r * rng.range(0.38, 0.5), a)
                var st = Path(); st.move(to: .zero); st.addLine(to: end)
                c.stroke(st, with: .color(col.center.c(0.8)), lineWidth: d.w(r * 0.025, minPx: 0.3))
                c.fill(disc(end, d.w(r * 0.045, minPx: 0.5)), with: .color(col.stamen.c()))
            }
        }
        c.fill(disc(.zero, r * 0.12), with: .color(col.center.c()))
    }

    static func bud(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size sz: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        var b = Path()
        b.move(to: .zero)
        b.addCurve(to: CGPoint(x: sz, y: 0), control1: CGPoint(x: sz * 0.15, y: -sz * 0.6), control2: CGPoint(x: sz * 0.9, y: -sz * 0.35))
        b.addCurve(to: .zero, control1: CGPoint(x: sz * 0.9, y: sz * 0.35), control2: CGPoint(x: sz * 0.15, y: sz * 0.6))
        c.fill(b, with: .linearGradient(Gradient(colors: [col.edge.c(), col.petal.c()]), startPoint: .zero, endPoint: CGPoint(x: sz, y: 0)))
        c.stroke(b, with: .color(col.edge.c(0.5)), lineWidth: d.w(sz * 0.04, minPx: 0.3))
        var calyx = Path(); calyx.addEllipse(in: CGRect(x: -sz * 0.12, y: -sz * 0.18, width: sz * 0.32, height: sz * 0.36))
        c.fill(calyx, with: .color(col.twig.mix(RGB(0x6E8E5A), 0.4).c()))
    }

    /// 散る花びら（一枚）
    static func falling(_ ctx: GraphicsContext, at p: CGPoint, size L: CGFloat, rotation: CGFloat, curl: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: 1 - curl)
        let shape = petal(L, width: 0.7)
        c.fill(shape, with: .linearGradient(Gradient(colors: [col.edge.c(0.9), col.petal.c()]), startPoint: .zero, endPoint: CGPoint(x: L, y: 0)))
        c.stroke(shape, with: .color(col.edge.c(0.4)), lineWidth: d.w(L * 0.03, minPx: 0.3))
    }

    /// 細い枝（節で少し曲がり、先へ細る）
    static func twig(_ ctx: GraphicsContext, points: [CGPoint], width w: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        let ws = (0..<points.count).map { i in d.w(w * (1 - 0.7 * CGFloat(i) / CGFloat(points.count - 1)), minPx: 0.5) }
        drawTaperedStroke(ctx, points: points, widths: ws, color: col.twig, alpha: 0.95)
        drawTaperedStroke(ctx, points: points.map { $0 + CGPoint(x: -w * 0.15, y: -w * 0.15) }, widths: ws.map { $0 * 0.3 }, color: col.twig.mix(.white, 0.35), alpha: 0.6)
    }
}

enum PetalMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0x5AC)
        let q = d.quality, boost = d.boost
        // 1) 輪に沿う細い枝（途切れながら、対角の花房へ向かう）
        for (a0, span, r0) in [(CGFloat(150), CGFloat(130), CGFloat(1.0)), (CGFloat(-20), CGFloat(110), CGFloat(1.0))] {
            var pts: [CGPoint] = []
            for i in 0...30 {
                let a = deg(a0 + span * CGFloat(i) / 30)
                pts.append(CGPoint.polar(r0 + 0.02 * sin(CGFloat(i) * 0.9), a))
            }
            ops.append(DrawOp(z: 0) { c in Sakura.twig(c, points: pts, width: 0.018 * boost, s: s, pal: pal, d: d) })
        }
        // 2) 花房：左上（大）と右下、ほかに点々と
        let blossoms: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [   // 角度, 半径, 大きさ, 優先度
            (214, 1.09, 0.13, 0), (240, 1.13, 0.09, 0.2), (190, 1.14, 0.08, 0.3), (226, 1.21, 0.055, 0.6),
            (38, 1.09, 0.115, 0), (60, 1.13, 0.075, 0.3), (16, 1.14, 0.06, 0.5),
            (132, 1.09, 0.06, 0.5), (300, 1.08, 0.055, 0.6), (98, 1.08, 0.045, 0.8),
        ]
        for (i, b) in blossoms.enumerated() where b.3 <= d.keep {
            let p = CGPoint.polar(b.1, deg(b.0))
            let seed = rng.next()
            let rot = rng.range(0, 6.28), tilt = rng.range(0, 0.35)
            ops.append(DrawOp(z: 0.5 + Double(i) * 0.01) { c in
                Sakura.blossom(c, at: p, radius: b.2 * boost, rotation: rot, tilt: tilt, s: s, pal: pal, d: d, seed: seed)
            })
        }
        // 3) 蕾と散る花びら
        if q > 0.3 {
            for (ad, r) in [(CGFloat(250), CGFloat(1.07)), (CGFloat(176), CGFloat(1.06)), (CGFloat(70), CGFloat(1.05))] {
                let p = CGPoint.polar(r, deg(ad))
                ops.append(DrawOp(z: 0.4) { c in Sakura.bud(c, at: p, angle: deg(ad) + 0.6, size: 0.045 * boost, s: s, pal: pal, d: d) })
            }
            for _ in 0..<Int(6 + 10 * q) {
                let ang = deg(rng.range(0, 360))
                let p = CGPoint.polar(rng.range(1.14, 1.27), ang)
                let size = rng.range(0.022, 0.034) * boost, rot = rng.range(0, 6.28), curl = rng.range(0.1, 0.55)
                ops.append(DrawOp(z: 0.9) { c in Sakura.falling(c, at: p, size: size, rotation: rot, curl: curl, s: s, pal: pal, d: d) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0x5A)
        var rng = SeededRNG(0x5B)
        // 右下の枝（角から左上へ伸びる）
        let br: [CGPoint] = [CGPoint(x: cc.rect.maxX + 6 * k, y: cc.rect.maxY - 10 * k), CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 24 * k),
                             CGPoint(x: cc.rect.maxX - 64 * k, y: cc.rect.maxY - 22 * k), CGPoint(x: cc.rect.maxX - 104 * k, y: cc.rect.maxY - 34 * k)]
        Sakura.twig(ctx, points: smoothSample(br), width: 3.2 * k, s: s, pal: pal, d: d)
        let br2: [CGPoint] = [CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 24 * k), CGPoint(x: cc.rect.maxX - 40 * k, y: cc.rect.maxY - 50 * k),
                              CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 76 * k)]
        Sakura.twig(ctx, points: smoothSample(br2), width: 2.0 * k, s: s, pal: pal, d: d)
        let flowers: [(CGFloat, CGFloat, CGFloat)] = [(-26, -30, 11), (-60, -28, 9), (-44, -54, 8), (-98, -40, 7), (-28, -80, 7), (-12, -52, 6), (-80, -16, 6)]
        for (i, f) in flowers.enumerated() where !cc.tiny || i < 4 {
            Sakura.blossom(ctx, at: CGPoint(x: cc.rect.maxX + f.0 * k, y: cc.rect.maxY + f.1 * k), radius: f.2 * k * (cc.tiny ? 1.25 : 1), rotation: rng.range(0, 6.28),
                           tilt: rng.range(0, 0.3), s: s, pal: pal, d: d, seed: rng.next())
        }
        Sakura.bud(ctx, at: CGPoint(x: cc.rect.maxX - 112 * k, y: cc.rect.maxY - 36 * k), angle: deg(200), size: 6 * k, s: s, pal: pal, d: d)
        // 左上の小枝
        if !cc.tiny {
            let tl: [CGPoint] = [CGPoint(x: cc.rect.minX - 4 * k, y: cc.rect.minY + 10 * k), CGPoint(x: cc.rect.minX + 20 * k, y: cc.rect.minY + 14 * k), CGPoint(x: cc.rect.minX + 40 * k, y: cc.rect.minY + 8 * k)]
            Sakura.twig(ctx, points: smoothSample(tl), width: 2.0 * k, s: s, pal: pal, d: d)
            Sakura.blossom(ctx, at: CGPoint(x: cc.rect.minX + 16 * k, y: cc.rect.minY + 14 * k), radius: 7 * k, rotation: 0.4, tilt: 0.2, s: s, pal: pal, d: d, seed: 91)
            Sakura.bud(ctx, at: CGPoint(x: cc.rect.minX + 40 * k, y: cc.rect.minY + 8 * k), angle: deg(-20), size: 5 * k, s: s, pal: pal, d: d)
            // 散る花びら（右側の余白と下辺）
            for _ in 0..<14 {
                let p = CGPoint(x: cc.rect.maxX - rng.range(10, 150) * k, y: cc.rect.minY + rng.range(20, 200) * k)
                if cc.textZone.insetBy(dx: -4 * k, dy: -4 * k).contains(p) || !cc.rect.insetBy(dx: 6 * k, dy: 6 * k).contains(p) { continue }
                Sakura.falling(ctx, at: p, size: rng.range(3, 5) * k, rotation: rng.range(0, 6.28), curl: rng.range(0.1, 0.6), s: s, pal: pal, d: d)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            Sakura.blossom(c, at: CGPoint(x: p.x, y: p.y + (flip ? -0.5 : 0.5) * k), radius: 4.4 * k, rotation: flip ? 0.6 : 0, tilt: 0, s: s, pal: pal, d: d, seed: flip ? 3 : 4)
        }
    }

    static func smoothSample(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 0..<(pts.count - 1) {
            for j in 0..<10 {
                let t = CGFloat(j) / 10
                let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
                let t2 = t * t, t3 = t2 * t
                out.append(CGPoint(x: 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                                   y: 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)))
            }
        }
        out.append(pts.last!)
        return out
    }
}

// MARK: - 夜花

enum NightFlower {
    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> (outer: RGB, inner: RGB, core: RGB, vine: RGB, leaf: RGB, glow: RGB) {
        if s.isDark { return (pal.secondary, RGB(0xFFF2F8).mix(pal.primary, 0.15), pal.primary, pal.secondary.withLightness(0.32), RGB(0x2F5A55), pal.primary) }
        return (pal.secondary.withLightness(0.55), RGB(0xFFF6FA), pal.primary.withLightness(0.55), pal.secondary.withLightness(0.3, saturationBoost: 0.6), RGB(0x3E6E62), pal.primary)
    }

    /// 細い花弁が二重に放射する花。外弁は細長く反り、内弁は白く幅広
    static func bloom(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, rotation: CGFloat, tilt: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let col = colors(s, pal)
        if s.isDark {
            var g = ctx
            g.blendMode = .plusLighter
            g.fill(disc(p, r * 1.6), with: .radialGradient(Gradient(colors: [col.glow.c(0.3), col.glow.c(0)]), center: p, startRadius: 0, endRadius: r * 1.6))
        }
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: 1 - tilt)
        func lance(_ L: CGFloat, _ w: CGFloat, _ bend: CGFloat) -> Path {
            var path = Path()
            path.move(to: .zero)
            path.addCurve(to: CGPoint(x: L, y: bend * L), control1: CGPoint(x: L * 0.3, y: -w * L), control2: CGPoint(x: L * 0.75, y: -w * L * 0.6 + bend * L * 0.6))
            path.addCurve(to: .zero, control1: CGPoint(x: L * 0.75, y: w * L * 0.6 + bend * L * 0.6), control2: CGPoint(x: L * 0.3, y: w * L))
            path.closeSubpath()
            return path
        }
        let outerN = d.px(r) > 10 ? 14 : 9
        for i in 0..<outerN {
            let a = CGFloat(i) / CGFloat(outerN) * 2 * .pi + rng.range(-0.05, 0.05)
            var pc = c
            pc.rotate(by: .radians(a))
            let shape = lance(r * rng.range(0.92, 1.08), 0.12, rng.range(-0.08, 0.08))
            if s.isDark { pc.blendMode = .plusLighter }
            pc.fill(shape, with: .linearGradient(Gradient(colors: [col.outer.c(0.35), col.outer.c(0.85), col.outer.mix(.white, 0.3).c(0.6)]), startPoint: .zero, endPoint: CGPoint(x: r, y: 0)))
        }
        for i in 0..<10 {
            let a = CGFloat(i) / 10 * 2 * .pi + 0.16
            var pc = c
            pc.rotate(by: .radians(a))
            let shape = lance(r * 0.68 * rng.range(0.92, 1.05), 0.2, 0)
            pc.fill(shape, with: .linearGradient(Gradient(colors: [col.core.c(0.6), col.inner.c(), col.inner.c()]), startPoint: .zero, endPoint: CGPoint(x: r * 0.68, y: 0)))
            pc.stroke(shape, with: .color(col.core.c(0.35)), lineWidth: d.w(r * 0.015, minPx: 0.3))
        }
        // しべ（長く弧を描き、先が光る）
        if d.px(r) > 6 {
            for i in 0..<7 {
                let a = deg(-60) + CGFloat(i) * deg(17)
                let end = CGPoint.polar(r * 0.75, a)
                var st = Path(); st.move(to: .zero); st.addQuadCurve(to: end, control: CGPoint.polar(r * 0.4, a - 0.25))
                c.stroke(st, with: .color(col.core.mix(.white, 0.3).c(0.85)), lineWidth: d.w(r * 0.018, minPx: 0.35))
                var tipC = c
                if s.isDark { tipC.blendMode = .plusLighter }
                tipC.fill(disc(end, d.w(r * 0.04, minPx: 0.5)), with: .color((s.isDark ? RGB(0xFFF4C8) : RGB(0xC9962E)).c()))
            }
        }
        c.fill(disc(.zero, r * 0.1), with: .color(col.core.c()))
    }

    /// ハート形の葉
    static func heartLeaf(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size L: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        var h = Path()
        h.move(to: .zero)
        h.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: -L * 0.15, y: -L * 0.65), control2: CGPoint(x: L * 0.7, y: -L * 0.45))
        h.addCurve(to: .zero, control1: CGPoint(x: L * 0.7, y: L * 0.45), control2: CGPoint(x: -L * 0.15, y: L * 0.65))
        h.closeSubpath()
        c.fill(h, with: .linearGradient(Gradient(colors: [col.leaf.c(), col.leaf.mix(s.isDark ? pal.secondary : .white, 0.3).c()]), startPoint: .zero, endPoint: CGPoint(x: L, y: 0)))
        var mid = Path(); mid.move(to: CGPoint(x: L * 0.05, y: 0)); mid.addLine(to: CGPoint(x: L * 0.85, y: 0))
        c.stroke(mid, with: .color(col.leaf.mix(.white, 0.45).c(0.6)), lineWidth: d.w(L * 0.03, minPx: 0.3))
    }

    static func firefly(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        var c = ctx
        if s.isDark {
            c.blendMode = .plusLighter
            c.fill(disc(p, r * 4), with: .radialGradient(Gradient(colors: [RGB(0xFFF4C8).c(0.4), RGB(0xFFF4C8).c(0)]), center: p, startRadius: 0, endRadius: r * 4))
        }
        c.fill(disc(p, d.w(r, minPx: 0.6)), with: .color((s.isDark ? RGB(0xFFF8DC) : RGB(0xC9962E)).c()))
    }
}

enum NightBloomMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0x9B)
        let q = d.quality, boost = d.boost
        let col = NightFlower.colors(s, pal)
        // 1) つる：輪に絡みながら一周弱。ところどころ外へ巻きひげ
        var vine: [CGPoint] = []
        for i in 0...300 {
            let a = deg(120) + CGFloat(i) / 300 * deg(320)
            vine.append(CGPoint.polar(1.0 + 0.03 * sin(a * 7), a))
        }
        let vws = (0...300).map { i -> CGFloat in d.w(0.012 * boost * (1 - 0.5 * CGFloat(i) / 300), minPx: q < 0.4 ? 0.8 : 0.5) }
        ops.append(DrawOp(z: 0) { c in
            drawTaperedStroke(c, points: vine, widths: vws, color: col.vine, alpha: 0.95)
            drawTaperedStroke(c, points: vine.map { $0 * 0.996 }, widths: vws.map { $0 * 0.3 }, color: col.vine.mix(.white, 0.4), alpha: 0.5)
        })
        // 2) ハートの葉
        for i in stride(from: 12, to: 300, by: q < 0.4 ? 40 : 22) {
            let p = vine[i]
            let tan = (vine[min(300, i + 1)] - vine[max(0, i - 1)]).angle
            let side: CGFloat = (i / 22) % 2 == 0 ? 1 : -1
            let L = rng.range(0.06, 0.09) * boost
            ops.append(DrawOp(z: 0.2) { c in NightFlower.heartLeaf(c, at: p, angle: tan + side * deg(55), size: L, s: s, pal: pal, d: d) })
        }
        // 3) 花：左上に大輪、右下に中輪、蕾
        let blooms: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(218, 1.12, 0.19, 0), (40, 1.1, 0.14, 0), (300, 1.07, 0.075, 0.5), (140, 1.08, 0.065, 0.6)]
        for (i, b) in blooms.enumerated() where b.3 <= d.keep {
            let p = CGPoint.polar(b.1, deg(b.0))
            let seed = rng.next()
            let rot = rng.range(0, 6.28), tilt = rng.range(0.05, 0.3)
            ops.append(DrawOp(z: 0.6 + Double(i) * 0.01) { c in
                NightFlower.bloom(c, at: p, radius: min(0.2, b.2 * boost), rotation: rot, tilt: tilt, s: s, pal: pal, d: d, seed: seed)
            })
        }
        // 4) 蛍
        if q > 0.35 {
            for _ in 0..<12 {
                let p = CGPoint.polar(rng.range(1.08, 1.27), deg(rng.range(0, 360)))
                let r = rng.range(0.005, 0.009)
                ops.append(DrawOp(z: 1) { c in NightFlower.firefly(c, p, r, s: s, pal: pal, d: d) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = NightFlower.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x9B, airAnchors: [
            (cc.br, 0.7, pal.secondary, s.isDark ? 0.24 : 0.14), (cc.tl, 0.5, pal.primary, s.isDark ? 0.14 : 0.1),
        ])
        var rng = SeededRNG(0x9C)
        // 下辺と右辺を這うつる
        var vine: [CGPoint] = []
        for i in 0...200 {
            let t = CGFloat(i) / 200
            if t < 0.6 {
                let u = t / 0.6
                vine.append(CGPoint(x: cc.rect.maxX - 6 * k - u * 150 * k, y: cc.rect.maxY - 12 * k + 5 * k * sin(u * 9)))
            } else {
                let u = (t - 0.6) / 0.4
                vine.append(CGPoint(x: cc.rect.maxX - 12 * k + 5 * k * sin(u * 7), y: cc.rect.maxY - 12 * k - u * 90 * k))
            }
        }
        let vws = (0...200).map { _ in d.w(1.2 * k, minPx: 0.6) }
        drawTaperedStroke(ctx, points: Array(vine[0...120]), widths: Array(vws[0...120]), color: col.vine, alpha: 0.9)
        drawTaperedStroke(ctx, points: Array(vine[121...200]), widths: Array(vws[121...200]), color: col.vine, alpha: 0.9)
        for i in stride(from: 8, to: 200, by: cc.tiny ? 36 : 16) {
            let p = vine[i]
            let tan = (vine[min(200, i + 1)] - vine[max(0, i - 1)]).angle
            NightFlower.heartLeaf(ctx, at: p, angle: tan + ((i / 16) % 2 == 0 ? 1 : -1) * deg(60), size: rng.range(9, 13) * k, s: s, pal: pal, d: d)
        }
        NightFlower.bloom(ctx, at: CGPoint(x: cc.rect.maxX - 32 * k, y: cc.rect.maxY - 34 * k), radius: (cc.tiny ? 24 : 21) * k, rotation: 0.3, tilt: 0.12, s: s, pal: pal, d: d, seed: 5)
        if !cc.tiny {
            NightFlower.bloom(ctx, at: CGPoint(x: cc.rect.maxX - 92 * k, y: cc.rect.maxY - 16 * k), radius: 12 * k, rotation: 1.1, tilt: 0.3, s: s, pal: pal, d: d, seed: 6)
            NightFlower.bloom(ctx, at: CGPoint(x: cc.rect.minX + 18 * k, y: cc.rect.minY + 16 * k), radius: 10 * k, rotation: 0.7, tilt: 0.25, s: s, pal: pal, d: d, seed: 7)
            for _ in 0..<16 {
                let p = CGPoint(x: cc.rect.minX + rng.unit() * cc.rect.width, y: cc.rect.minY + rng.unit() * cc.rect.height)
                if cc.textZone.insetBy(dx: -6 * k, dy: -6 * k).contains(p) || cc.avatarZone.contains(p) { continue }
                NightFlower.firefly(ctx, p, rng.range(0.6, 1.1) * k, s: s, pal: pal, d: d)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            NightFlower.bloom(c, at: CGPoint(x: p.x, y: p.y + (flip ? -0.5 : 0.5) * k), radius: 5 * k, rotation: 0, tilt: 0, s: s, pal: pal, d: d, seed: 9)
        }
    }
}

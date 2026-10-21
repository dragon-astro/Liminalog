// 石径：平たい川石を並べた小径。石は上から光を受け、縁に影と苔、ところどころに金の粒。
import SwiftUI

enum Stone {
    static func tones(_ s: DecoScheme, _ pal: ItemPalette) -> [RGB] {
        if s.isDark { return [RGB(0x6E7A82), RGB(0x7F8A7C), RGB(0x8A8295), RGB(0x5E6E74), pal.primary.withLightness(0.42, saturationBoost: 0.4)] }
        return [RGB(0xB9BDB4), RGB(0xC7C0B4), RGB(0xA9B3AC), RGB(0xBFB5B9), pal.primary.withLightness(0.7, saturationBoost: 0.35)]
    }

    static func stone(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, flat: CGFloat, rotation: CGFloat, tone: RGB, s: DecoScheme, pal: ItemPalette, d: Detail,
                      seed: UInt64, moss: Bool, gold: Bool) {
        var rng = SeededRNG(seed)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: flat)
        let shape = organicBlob(radius: r, rng: &rng, points: 9, roughness: 0.12)
        // 接地の影
        var sh = c
        sh.translateBy(x: r * 0.06, y: r * 0.18)
        sh.fill(shape, with: .color((s.isDark ? RGB.black : RGB(0x7A5A40)).c(s.isDark ? 0.45 : 0.25)))
        c.fill(shape, with: .radialGradient(Gradient(stops: [
            .init(color: tone.mix(.white, s.isDark ? 0.35 : 0.5).c(), location: 0), .init(color: tone.c(), location: 0.55),
            .init(color: tone.mix(.black, s.isDark ? 0.45 : 0.25).c(), location: 1),
        ]), center: CGPoint(x: -r * 0.3, y: -r * 0.45), startRadius: 0, endRadius: r * 1.5))
        var ins = c
        ins.clip(to: shape)
        // 石の粒と、うっすらとした層の筋
        if d.px(r) > 6 {
            for _ in 0..<Int(10 + d.px(r) * 0.6) {
                let q = CGPoint(x: rng.range(-r, r), y: rng.range(-r, r))
                ins.fill(disc(q, d.w(r * rng.range(0.015, 0.04), minPx: 0.4)), with: .color((rng.chance(0.5) ? RGB.white : RGB.black).c(Double(rng.range(0.08, 0.2)))))
            }
            var band = Path()
            band.move(to: CGPoint(x: -r, y: r * rng.range(-0.2, 0.3)))
            band.addQuadCurve(to: CGPoint(x: r, y: r * rng.range(-0.2, 0.3)), control: CGPoint(x: 0, y: r * rng.range(-0.4, 0.5)))
            ins.stroke(band, with: .color(RGB.white.c(0.14)), lineWidth: d.w(r * 0.08, minPx: 0.4))
        }
        if moss {
            let mossC = s.isDark ? RGB(0x5FA87F).mix(pal.primary, 0.3) : RGB(0x6B9E6A)
            for _ in 0..<Int(14 + d.px(r) * 0.8) {
                let a = rng.range(deg(190), deg(340)), rr = r * rng.range(0.55, 1.0)
                let q = CGPoint.polar(rr, a)
                ins.fill(disc(q, d.w(r * rng.range(0.04, 0.09), minPx: 0.5)), with: .color(mossC.mix(.white, Double(rng.range(0, 0.3))).c(0.9)))
            }
        }
        c.stroke(shape, with: .color(tone.mix(.black, 0.5).c(s.isDark ? 0.5 : 0.3)), lineWidth: d.w(r * 0.03, minPx: 0.35))
        if gold {
            let gp = CGPoint(x: r * rng.range(-0.3, 0.3), y: -r * rng.range(0.1, 0.4))
            var gc = c
            if s.isDark { gc.blendMode = .plusLighter }
            gc.fill(disc(gp, d.w(r * 0.07, minPx: 0.6)), with: .color((s.isDark ? RGB(0xFFE3A3) : RGB(0xC9962E)).c()))
            gc.translateBy(x: gp.x, y: gp.y)
            gc.fill(Celestial.sparklePath(long: r * 0.25, waist: r * 0.03), with: .color((s.isDark ? RGB(0xFFF4DA) : RGB(0xC9962E)).c(0.9)))
        }
    }

    /// 二枚葉の芽
    static func sprout(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size L: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let stem = CGPoint.polar(L * 0.6, angle)
        var st = Path(); st.move(to: p); st.addLine(to: p + stem)
        let green = s.isDark ? pal.primary.withLightness(0.55) : RGB(0x4F8E62)
        ctx.stroke(st, with: .color(green.c()), lineWidth: d.w(L * 0.07, minPx: 0.5))
        for sgn in [CGFloat(-1), 1] {
            var c = ctx
            c.translateBy(x: (p + stem).x, y: (p + stem).y)
            c.rotate(by: .radians(angle + sgn * deg(50)))
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: L * 0.55, y: 0), control: CGPoint(x: L * 0.27, y: -L * 0.25))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: L * 0.27, y: L * 0.25))
            c.fill(leaf, with: .color(green.mix(.white, 0.2).c()))
        }
    }
}

enum StoneMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0x570E)
        let q = d.quality, boost = d.boost
        let tones = Stone.tones(s, pal)
        // 輪に沿って石を敷く：下半分と対角に大きな石、上は小石。角度を詰めて小径にする
        var a: CGFloat = 0
        var i = 0
        while a < 360 {
            let ang = deg(a)
            let weight = 0.45 + 0.55 * ((sin(ang) + 1) / 2) + 0.3 * angularBump(ang, 214, 30)
            let r = (0.034 + 0.05 * weight * rng.range(0.7, 1.05)) * (q < 0.4 ? 1.15 : 1)
            let p = CGPoint.polar(1.0 + r * 0.35 + rng.range(-0.01, 0.01), ang)
            let tone = rng.pick(tones)
            let seed = rng.next(), flat = rng.range(0.62, 0.85), rot = ang + .pi / 2 + rng.range(-0.3, 0.3)
            let moss = rng.chance(0.3), gold = rng.chance(0.12) && q > 0.4
            ops.append(DrawOp(z: 0.3 + Double(i) * 0.001) { c in
                Stone.stone(c, at: p, radius: r, flat: flat, rotation: rot, tone: tone, s: s, pal: pal, d: d, seed: seed, moss: moss, gold: gold)
            })
            a += (r * 2.05 / 1.04) * 180 / .pi * rng.range(0.92, 1.1)   // 石の直径ぶん角度を送る
            i += 1
        }
        // 小石の隙間を埋める砂利
        if q > 0.4 {
            for _ in 0..<60 {
                let ang = deg(rng.range(0, 360))
                let p = CGPoint.polar(rng.range(1.0, 1.15), ang)
                let tone = rng.pick(tones)
                let r = rng.range(0.006, 0.014)
                ops.append(DrawOp(z: 0.1) { c in
                    c.fill(disc(p, d.w(r, minPx: 0.6)), with: .color(tone.mix(s.isDark ? .black : .white, 0.15).c(0.9)))
                })
            }
            // 芽
            for ad in [CGFloat(200), 232, 30, 58, 300] {
                let ang = deg(ad)
                let p = CGPoint.polar(1.13, ang)
                ops.append(DrawOp(z: 0.9) { c in Stone.sprout(c, at: p, angle: ang + rng.range(-0.3, 0.3), size: 0.07 * boost, s: s, pal: pal, d: d) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let tones = Stone.tones(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x57)
        var rng = SeededRNG(0x58)
        // 左下から右下へ弧を描く飛び石
        let path: [CGPoint] = (0...14).map { i in
            let t = CGFloat(i) / 14
            return CGPoint(x: cc.rect.minX + 14 * k + t * (cc.rect.width - 30 * k), y: cc.rect.maxY - 14 * k - 10 * k * sin(t * .pi) - (t > 0.75 ? (t - 0.75) * 120 * k : 0))
        }
        for (i, p) in path.enumerated() {
            let mid = p.x > cc.rect.minX + 120 * k && p.x < cc.rect.maxX - 100 * k
            let r = (mid ? 6 : 9) * k * rng.range(0.85, 1.15) * (cc.tiny ? 1.25 : 1)
            Stone.stone(ctx, at: p, radius: r, flat: rng.range(0.6, 0.8), rotation: rng.range(-0.4, 0.4), tone: rng.pick(tones), s: s, pal: pal, d: d,
                        seed: UInt64(i * 31 + 7), moss: rng.chance(0.35), gold: rng.chance(0.15) && !cc.tiny)
        }
        if !cc.tiny {
            // 苔の茂みと芽
            for _ in 0..<30 {
                let p = path[Int(rng.range(0, 14))] + CGPoint(x: rng.range(-10, 10) * k, y: rng.range(-12, 4) * k)
                ctx.fill(disc(p, rng.range(0.8, 1.8) * k), with: .color((s.isDark ? RGB(0x5FA87F).mix(pal.primary, 0.3) : RGB(0x6B9E6A)).c(0.7)))
            }
            for (i, p) in [path[2], path[11], path[13]].enumerated() {
                Stone.sprout(ctx, at: p + CGPoint(x: 6 * k, y: -6 * k), angle: deg(-80 + CGFloat(i) * 12), size: 9 * k, s: s, pal: pal, d: d)
            }
            // 右上の小石
            for (dx, dy, r) in [(CGFloat(-18), CGFloat(18), CGFloat(5)), (-30, 12, 3.4), (-10, 32, 2.8)] {
                Stone.stone(ctx, at: CGPoint(x: cc.rect.maxX + dx * k, y: cc.rect.minY + dy * k), radius: r * k, flat: 0.75, rotation: 0.2, tone: rng.pick(tones),
                            s: s, pal: pal, d: d, seed: UInt64(dx * -3), moss: true, gold: dx == -18)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 26) { c, p, flip in
            for (j, dx) in [CGFloat(-6), 0, 6].enumerated() {
                Stone.stone(c, at: CGPoint(x: p.x + dx * k, y: p.y + (flip ? -0.8 : 0.8) * k), radius: (j == 1 ? 3.4 : 2.4) * k, flat: 0.7, rotation: 0,
                            tone: tones[j], s: s, pal: pal, d: d, seed: UInt64(j + (flip ? 10 : 0)), moss: false, gold: j == 1)
            }
        }
    }
}

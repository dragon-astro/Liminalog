// 墨：一筆の円相（穂先の毛の筋・墨溜まり・かすれ）、にじみ、飛沫、落款。
import SwiftUI

enum Ink {
    static func inkColor(_ s: DecoScheme, _ pal: ItemPalette) -> RGB { s.isDark ? pal.primary.mix(.white, 0.08) : pal.primary.withLightness(0.3, saturationBoost: 0.85) }
    static func washColor(_ s: DecoScheme, _ pal: ItemPalette) -> RGB { s.isDark ? pal.secondary : pal.secondary.withLightness(0.62) }

    /// 筆の一画。中心線と太さの列を受け取り、毛の筋（strands本）で描く。dry は t>dry からかすれる。
    static func brush(_ ctx: GraphicsContext, center: [CGPoint], widths: [CGFloat], strands: Int, dry: CGFloat,
                      s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let ink = inkColor(s, pal)
        let n = center.count
        var normals: [CGPoint] = []
        for i in 0..<n {
            let a = center[max(0, i - 1)], b = center[min(n - 1, i + 1)]
            normals.append((b - a).normalized.perpendicular)
        }
        // 墨のある前半は面で下塗り（筋の隙間を埋める）
        let solidEnd = Int(CGFloat(n) * dry)
        if solidEnd > 2 {
            let body = ribbonPath(Array(center.prefix(solidEnd)), widths: widths.prefix(solidEnd).map { $0 * 0.9 })
            ctx.fill(body, with: .linearGradient(Gradient(colors: [ink.c(0.92), ink.c(0.7)]), startPoint: center[0], endPoint: center[solidEnd - 1]))
        }
        for j in 0..<strands {
            let off = (CGFloat(j) / CGFloat(strands - 1) - 0.5) * 0.94
            let density = Double(rng.range(0.55, 1.0))
            let edge = abs(off) * 2  // 0=中心, 1=縁
            let ph = rng.range(0, 100), fr = rng.range(18, 40)
            var pts: [CGPoint] = [], ws: [CGFloat] = [], als: [Double] = []
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1)
                let w = widths[i]
                pts.append(center[i] + normals[i] * (off * w))
                ws.append(d.w(w / CGFloat(strands) * 1.9, minPx: 0.35))
                var a = density * (0.75 + 0.25 * Double(edge))  // 縁に墨が溜まる
                if t > dry {
                    // かすれ：縁の毛から先に墨が切れ、途切れ途切れになる
                    let dryness = (t - dry) / (1 - dry)
                    let noise = 0.5 + 0.5 * sin(fr * t + ph) * sin(fr * 0.37 * t + ph * 0.5)
                    let threshold = dryness * (0.55 + 0.6 * edge)
                    a *= noise > threshold ? Double(1 - dryness * 0.5) : 0
                }
                als.append(a)
            }
            drawVaryingStroke(ctx, points: pts, widths: ws, alphas: als, color: j % 3 == 0 ? ink.mix(.white, s.isDark ? 0.18 : 0.12) : ink)
        }
    }

    /// にじみ：不規則な色面を重ね、縁を少し濃く（乾き際）
    static func bloom(_ ctx: GraphicsContext, center: CGPoint, radius R: CGFloat, s: DecoScheme, pal: ItemPalette, seed: UInt64, alpha: Double, blur: CGFloat) {
        var rng = SeededRNG(seed)
        let wash = washColor(s, pal), ink = inkColor(s, pal)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: blur))
            for i in 0..<6 {
                let c = center + CGPoint(x: rng.gauss() * R * 0.25, y: rng.gauss() * R * 0.2)
                let blob = organicBlob(radius: R * rng.range(0.45, 0.8), rng: &rng, points: 13, roughness: rng.range(0.18, 0.32), center: c)
                let col = i % 3 == 0 ? ink : wash
                l.fill(blob, with: .radialGradient(Gradient(colors: [col.c(alpha * 0.5), col.c(alpha * 0.85)]), center: c, startRadius: 0, endRadius: R))
                l.stroke(blob, with: .color(ink.c(alpha * 0.7)), lineWidth: R * 0.025)
            }
        }
    }

    static func splatter(_ ctx: GraphicsContext, around p: CGPoint, spread: CGFloat, count: Int, size: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let ink = inkColor(s, pal)
        for _ in 0..<count {
            let q = p + CGPoint(x: rng.gauss() * spread, y: rng.gauss() * spread)
            let r = size * pow(rng.range(0.15, 1), 2)
            var c = ctx
            c.translateBy(x: q.x, y: q.y)
            c.rotate(by: .radians(rng.range(0, 3.14)))
            c.scaleBy(x: rng.range(1, 1.8), y: 1)
            c.fill(disc(.zero, d.w(r, minPx: 0.6)), with: .color(ink.c(Double(rng.range(0.6, 0.95)))))
        }
    }

    /// 落款（角印）：二色ルールを守り、アイテムの墨色で押す
    static func seal(_ ctx: GraphicsContext, at p: CGPoint, size S: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let ink = inkColor(s, pal)
        let r = CGRect(x: p.x - S / 2, y: p.y - S / 2, width: S, height: S)
        ctx.fill(Path(roundedRect: r, cornerRadius: S * 0.12), with: .color(ink.c(0.88)))
        ctx.stroke(Path(roundedRect: r.insetBy(dx: S * 0.1, dy: S * 0.1), cornerRadius: S * 0.06),
                   with: .color((s.isDark ? RGB(0x17132A) : RGB.white).c(0.85)), lineWidth: d.w(S * 0.05, minPx: 0.5))
        ctx.draw(Text("墨").font(.system(size: S * 0.55, weight: .heavy, design: .serif)).foregroundColor((s.isDark ? RGB(0x17132A) : RGB.white).c(0.92)), at: p)
    }
}

// MARK: - 墨縁

enum InkMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        // 円相：左やや上から入り（墨溜まり）、時計回りに約325°、右上で筆を抜く
        let start = deg(200), sweep = deg(326)
        let n = q < 0.4 ? 160 : 360
        var center: [CGPoint] = [], widths: [CGFloat] = []
        var rng = SeededRNG(0x1A4)
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let a = start + sweep * t
            let r = 1.035 + 0.012 * sin(3 * a + 0.6) + 0.006 * sin(7 * a)
            center.append(CGPoint.polar(r, a))
            var w: CGFloat
            if t < 0.03 { w = 0.06 + (0.1 - 0.06) * t / 0.03 }
            else if t < 0.5 { w = 0.1 - 0.025 * (t - 0.03) / 0.47 }
            else if t < 0.86 { w = 0.075 - 0.03 * (t - 0.5) / 0.36 }
            else { w = 0.045 - 0.028 * (t - 0.86) / 0.14 }
            w *= 1 + 0.06 * sin(t * 40 + rng.range(0, 0.2))
            widths.append(w * (q < 0.4 ? 1.25 : 1))
        }
        // にじみ（入りの所だけ紙に吸われる）
        ops.append(DrawOp(z: 0) { c in
            Ink.bloom(c, center: CGPoint.polar(1.11, start + deg(8)), radius: 0.13, s: s, pal: pal, seed: 11, alpha: s.isDark ? 0.22 : 0.18, blur: 0.02)
        })
        let cc = center, ww = widths
        ops.append(DrawOp(z: 0.5) { c in
            Ink.brush(c, center: cc, widths: ww, strands: q < 0.4 ? 9 : 18, dry: 0.62, s: s, pal: pal, d: d, seed: 21)
        })
        // 入りの墨溜まり（丸く重い起筆）
        ops.append(DrawOp(z: 0.6) { c in
            let p = cc[2]
            var rr = SeededRNG(3)
            let blob = organicBlob(radius: 0.048 * (q < 0.4 ? 1.2 : 1), rng: &rr, points: 10, roughness: 0.18, center: p + CGPoint.polar(0.012, start + .pi))
            c.fill(blob, with: .color(Ink.inkColor(s, pal).c(0.9)))
        })
        // 飛沫（入りの近くと、抜きの先）
        if q > 0.3 {
            ops.append(DrawOp(z: 0.7) { c in
                Ink.splatter(c, around: CGPoint.polar(1.13, start - deg(6)), spread: 0.05, count: 12, size: 0.014, s: s, pal: pal, d: d, seed: 5)
                Ink.splatter(c, around: CGPoint.polar(1.12, start + sweep + deg(8)), spread: 0.035, count: 6, size: 0.01, s: s, pal: pal, d: d, seed: 6)
            })
        }
        // 抜きの後に残る細い糸（筆の最後の一本）
        if q > 0.4 {
            var thread: [CGPoint] = []
            for i in 0...30 {
                let t = CGFloat(i) / 30
                thread.append(CGPoint.polar(1.0 + 0.02 * t, start + sweep + deg(10) * t))
            }
            let ws = (0...30).map { i -> CGFloat in d.w(0.004 * (1 - CGFloat(i) / 30), minPx: 0.35) }
            ops.append(DrawOp(z: 0.8) { c in drawTaperedStroke(c, points: thread, widths: ws, color: Ink.inkColor(s, pal), alpha: 0.7) })
        }
        _ = boost
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0x1B, airAnchors: [
            (cc.tl, 0.55, pal.secondary, s.isDark ? 0.14 : 0.1), (cc.br, 0.6, pal.primary, s.isDark ? 0.16 : 0.1),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        // にじみ（左上・右下）
        Ink.bloom(inner, center: CGPoint(x: cc.rect.minX + 8 * k, y: cc.rect.minY + 10 * k), radius: 58 * k, s: s, pal: pal, seed: 31,
                  alpha: s.isDark ? 0.2 : 0.16, blur: 2.2 * k)
        Ink.bloom(inner, center: CGPoint(x: cc.rect.maxX - 6 * k, y: cc.rect.maxY - 4 * k), radius: 70 * k, s: s, pal: pal, seed: 32,
                  alpha: s.isDark ? 0.22 : 0.18, blur: 2.2 * k)
        // 下辺を走る一筆（太→細）。一覧サイズでも筆跡だけは残す
        do {
            var center: [CGPoint] = [], widths: [CGFloat] = []
            for i in 0..<160 {
                let t = CGFloat(i) / 159
                let x = cc.rect.maxX - 18 * k - t * 170 * k
                let y = cc.rect.maxY - 20 * k + 6 * k * sin(t * 2.6) - 4 * k * t
                center.append(CGPoint(x: x, y: y))
                widths.append(k * (t < 0.08 ? 4 + 30 * t : max(0.6, 6.2 - 6 * t)) * (cc.tiny ? 1.8 : 1))
            }
            Ink.brush(inner, center: center, widths: widths, strands: 10, dry: 0.45, s: s, pal: pal, d: d, seed: 41)
            Ink.splatter(inner, around: CGPoint(x: cc.rect.maxX - 22 * k, y: cc.rect.maxY - 30 * k), spread: 10 * k, count: 14, size: 1.6 * k, s: s, pal: pal, d: d, seed: 42)
            Ink.splatter(inner, around: CGPoint(x: cc.rect.minX + 30 * k, y: cc.rect.minY + 26 * k), spread: 9 * k, count: 8, size: 1.3 * k, s: s, pal: pal, d: d, seed: 43)
        }
        // 落款
        Ink.seal(ctx, at: CGPoint(x: cc.rect.maxX - 22 * k, y: cc.rect.maxY - 44 * k), size: (cc.tiny ? 14 : 12) * k, s: s, pal: pal, d: d)
        CardBase.drawRule(ctx, cc, gap: 26) { c, p, flip in
            // 小さな筆の点（点画）
            var rr = SeededRNG(flip ? 9 : 8)
            let blob = organicBlob(radius: 2.6 * k, rng: &rr, points: 9, roughness: 0.25, center: CGPoint(x: p.x, y: p.y + (flip ? -1 : 1) * 1.5 * k))
            c.fill(blob, with: .color(Ink.inkColor(s, pal).c(0.85)))
        }
    }
}

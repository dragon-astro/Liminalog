// 雨粒：同じ角度で降る細い雨脚、ガラスに結ぶ大小の水滴、伝い落ちる雫の跡、足元の小さな波紋。
import SwiftUI

enum Rain {
    static let slant = deg(104)   // 下やや左へ降る

    static func streak(_ ctx: GraphicsContext, at p: CGPoint, length L: CGFloat, width w: CGFloat, color: RGB, alpha: Double) {
        let dir = CGPoint.polar(1, slant)
        let tail = p - dir * L
        var line = Path(); line.move(to: tail); line.addLine(to: p)
        ctx.stroke(line, with: .linearGradient(Gradient(colors: [color.c(0), color.c(alpha)]), startPoint: tail, endPoint: p),
                   style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    /// ガラスを伝い落ちた跡（上へ細くなる不規則な道）と、その先の雫
    static func runnel(_ ctx: GraphicsContext, bottom p: CGPoint, length L: CGFloat, dropR: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        var pts: [CGPoint] = []
        var x = p.x
        for i in 0...24 {
            let t = CGFloat(i) / 24
            x += rng.range(-0.06, 0.06) * dropR
            pts.append(CGPoint(x: x, y: p.y - dropR * 0.8 - L * t))
        }
        let ws = (0...24).map { i -> CGFloat in d.w(dropR * 0.7 * (1 - CGFloat(i) / 26), minPx: 0.35) }
        drawTaperedStroke(ctx, points: pts, widths: ws, color: pal.fill(s), alpha: s.isDark ? 0.28 : 0.22)
        drawTaperedStroke(ctx, points: pts.map { $0 + CGPoint(x: -dropR * 0.15, y: 0) }, widths: ws.map { $0 * 0.3 }, color: .white, alpha: s.isDark ? 0.35 : 0.7)
        Water.droplet(ctx, p, dropR, s: s, pal: pal, d: d)
    }
}

enum RainMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0x4A1)
        let q = d.quality, boost = d.boost
        let streakC = s.isDark ? pal.primary.mix(.white, 0.25) : pal.line(s)

        // 1) ガラスの縁（細い二重線）
        ops.append(DrawOp(z: 0) { c in
            c.stroke(disc(.zero, 1.0), with: .color(pal.line(s).c(0.6)), lineWidth: d.w(0.004 * boost, minPx: 0.7))
            c.stroke(disc(.zero, 0.993), with: .color(RGB.white.c(s.isDark ? 0.3 : 0.7)), lineWidth: d.w(0.002, minPx: 0.4))
        })
        // 2) 雨脚：輪の外側。上半分と対角で多い
        let count = Int(40 + 90 * q)
        for _ in 0..<count {
            let ang = deg(rng.range(0, 360))
            let w0 = 0.35 + 0.65 * (angularBump(ang, 230, 70) + angularBump(ang, 30, 50))
            guard rng.unit() < w0 else { continue }
            let p = CGPoint.polar(rng.range(1.05, 1.28), ang)
            let L = rng.range(0.07, 0.16) * (q < 0.4 ? 1.2 : 1)
            let tail = p - CGPoint.polar(L, Rain.slant)
            guard tail.length > 1.03, tail.length < 1.31 else { continue }
            let w = d.w(rng.range(0.005, 0.009) * boost, minPx: q < 0.4 ? 0.9 : 0.6)
            let alpha = Double(rng.range(0.4, 0.85))
            ops.append(DrawOp(z: 0.1) { c in Rain.streak(c, at: p, length: L, width: w, color: streakC, alpha: alpha) })
        }
        // 3) 縁に結ぶ水滴（下ほど大きく多い）と、下で垂れる雫
        let beads = Int(20 + 30 * q)
        for _ in 0..<beads {
            let ang = deg(rng.range(0, 360))
            let lower = (sin(ang) + 1) / 2   // 下=1
            guard rng.unit() < 0.3 + 0.7 * lower else { continue }
            let r = (0.016 + 0.04 * lower * rng.range(0.45, 1.0)) * boost
            let p = CGPoint.polar(1.0 + r * 0.3, ang)
            ops.append(DrawOp(z: 0.5 + Double(r)) { c in Water.droplet(c, p, r, s: s, pal: pal, d: d, shadow: false) })
        }
        for (i, ad) in [CGFloat(84), 104, 60].enumerated() where q > 0.3 || i == 0 {
            let p = CGPoint.polar(1.0, deg(ad))
            let hang = CGPoint(x: p.x, y: p.y + (0.045 + CGFloat(i) * 0.01) * boost)
            let r = (0.02 - CGFloat(i) * 0.004) * boost
            ops.append(DrawOp(z: 0.9) { c in
                var neck = Path(); neck.move(to: p); neck.addLine(to: hang)
                c.stroke(neck, with: .color(pal.fill(s).c(0.5)), style: StrokeStyle(lineWidth: d.w(r * 0.6, minPx: 0.5), lineCap: .round))
                Water.droplet(c, hang, r, s: s, pal: pal, d: d, shadow: false)
            })
        }
        // 3b) 縁の上側に乗る大粒の雨粒（輪郭に変化を作る）
        for (ad, rr) in [(CGFloat(222), CGFloat(0.05)), (CGFloat(246), CGFloat(0.034)), (CGFloat(304), CGFloat(0.03)), (CGFloat(20), CGFloat(0.036))] where q > 0.25 || ad == 222 {
            let p = CGPoint.polar(1.0 + rr * 0.55, deg(ad))
            ops.append(DrawOp(z: 0.95) { c in Water.droplet(c, p, rr * boost, s: s, pal: pal, d: d, shadow: false) })
        }
        // 4) 落ちた一滴の波紋（下）
        if q > 0.4 {
            ops.append(DrawOp(z: 0.2) { c in
                var cc = c
                var clip = Path(); clip.addPath(disc(.zero, 1.32)); clip.addPath(disc(.zero, 1.03))
                cc.clip(to: clip, style: FillStyle(eoFill: true))
                Water.ripple(cc, center: CGPoint(x: 0.04, y: 1.2), radius: 0.12, rings: 3, ratio: 0.38, s: s, pal: pal, d: d, width: 0.006, alpha: 0.9)
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0x4A, airAnchors: [
            (cc.tr, 0.7, pal.primary, s.isDark ? 0.18 : 0.12), (cc.bl, 0.6, pal.secondary, s.isDark ? 0.16 : 0.1),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        var rng = SeededRNG(0x4B)
        let streakC = s.isDark ? pal.primary.mix(.white, 0.2) : pal.line(s)
        // 雨脚：縁ほど多く、本文列は避ける
        for _ in 0..<(cc.tiny ? 50 : 240) {
            let p = CGPoint(x: cc.rect.minX + rng.unit() * cc.rect.width, y: cc.rect.minY + rng.unit() * cc.rect.height)
            let ex = (p.x - cc.rect.midX) / (cc.rect.width / 2), ey = (p.y - cc.rect.midY) / (cc.rect.height / 2)
            let edge = max(abs(ex), abs(ey))
            guard rng.unit() < pow(edge, 2.2) + 0.05, !cc.textZone.insetBy(dx: -4 * k, dy: -4 * k).contains(p), !cc.avatarZone.contains(p) else { continue }
            let L = rng.range(10, 26) * k
            let tail = p - CGPoint.polar(L, Rain.slant)
            guard !cc.textZone.insetBy(dx: -4 * k, dy: -4 * k).contains(tail), !cc.avatarZone.contains(tail) else { continue }
            Rain.streak(inner, at: p, length: L, width: d.w(rng.range(0.6, 1.1) * k, minPx: 0.6), color: streakC, alpha: Double(rng.range(0.35, 0.75)))
        }
        // ガラスの水滴と伝い跡（右側と下）
        if !cc.tiny {
            for (dx, dy, r, L) in [(CGFloat(-20), CGFloat(-28), CGFloat(4.6), CGFloat(46)), (-44, -14, 3.2, 26), (-10, -74, 2.8, 34), (-64, -36, 2.4, 0), (-30, -52, 2.0, 0), (-84, -18, 1.8, 14)] {
                let p = CGPoint(x: cc.rect.maxX + dx * k, y: cc.rect.maxY + dy * k)
                if L > 0 { Rain.runnel(ctx, bottom: p, length: L * k, dropR: r * k, s: s, pal: pal, d: d, seed: UInt64(abs(dx * 7))) }
                else { Water.droplet(ctx, p, r * k, s: s, pal: pal, d: d) }
            }
            for _ in 0..<26 {
                let p = CGPoint(x: cc.rect.maxX - rng.range(6, 110) * k, y: cc.rect.maxY - rng.range(6, 90) * k)
                if cc.textZone.insetBy(dx: -4 * k, dy: -4 * k).contains(p) { continue }
                Water.droplet(ctx, p, rng.range(0.7, 2.0) * k, s: s, pal: pal, d: d, shadow: false)
            }
            for _ in 0..<10 {
                let p = CGPoint(x: cc.rect.minX + rng.range(6, 60) * k, y: cc.rect.minY + rng.range(6, 40) * k)
                Water.droplet(ctx, p, rng.range(0.6, 1.6) * k, s: s, pal: pal, d: d, shadow: false)
            }
        }
        if cc.tiny {
            // 一覧サイズ：大きな雫と伝い跡だけで「雨粒」と分かるように
            Rain.runnel(ctx, bottom: CGPoint(x: cc.rect.maxX - 22 * k, y: cc.rect.maxY - 30 * k), length: 50 * k, dropR: 7 * k, s: s, pal: pal, d: d, seed: 3)
            Water.droplet(ctx, CGPoint(x: cc.rect.maxX - 52 * k, y: cc.rect.maxY - 22 * k), 4.6 * k, s: s, pal: pal, d: d)
            Water.droplet(ctx, CGPoint(x: cc.rect.minX + 26 * k, y: cc.rect.minY + 30 * k), 4 * k, s: s, pal: pal, d: d)
        }
        // 足元の波紋
        Water.ripple(inner, center: CGPoint(x: cc.rect.minX + 70 * k, y: cc.rect.maxY - 12 * k), radius: 26 * k, rings: 3, ratio: 0.32, s: s, pal: pal, d: d, width: 0.7 * k, alpha: 0.75)
        Water.ripple(inner, center: CGPoint(x: cc.rect.minX + 112 * k, y: cc.rect.maxY - 8 * k), radius: 16 * k, rings: 2, ratio: 0.32, s: s, pal: pal, d: d, width: 0.6 * k, alpha: 0.6)
        CardBase.drawRule(ctx, cc, gap: 22) { c, p, flip in
            if flip {
                Water.ripple(c, center: p, radius: 7 * k, rings: 2, ratio: 0.38, s: s, pal: pal, d: d, width: 0.6 * k)
            } else {
                var cc2 = c
                cc2.translateBy(x: p.x, y: p.y + 2 * k)
                Water.teardrop(cc2, .zero, 2.4 * k, s: s, pal: pal, d: d)
            }
        }
    }
}

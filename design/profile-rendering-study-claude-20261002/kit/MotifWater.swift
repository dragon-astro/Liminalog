// 水の部品と「水縁」。
import SwiftUI

enum Water {
    /// 水滴（球）：屈折で下側が明るく、上に鏡面、縁は締まる。下に小さな影。
    static func droplet(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail, shadow: Bool = true) {
        let body = pal.fill(s)
        if shadow {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.9, y: p.y + r * 0.55, width: r * 1.8, height: r * 0.7)),
                     with: .radialGradient(Gradient(colors: [(s.isDark ? RGB.black : pal.deep(s)).c(s.isDark ? 0.35 : 0.18), RGB.black.c(0)]),
                                           center: CGPoint(x: p.x, y: p.y + r * 0.9), startRadius: 0, endRadius: r))
        }
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(stops: [
            .init(color: body.mix(.white, s.isDark ? 0.15 : 0.55).c(s.isDark ? 0.35 : 0.55), location: 0),
            .init(color: body.c(s.isDark ? 0.55 : 0.6), location: 0.7),
            .init(color: pal.deep(s).c(s.isDark ? 0.95 : 0.85), location: 1),
        ]), center: CGPoint(x: p.x + r * 0.15, y: p.y + r * 0.25), startRadius: 0, endRadius: r * 1.05))
        // 屈折で底に集まる光
        if d.px(r) > 2.2 {
            var crescent = Path()
            crescent.addArc(center: p, radius: r * 0.72, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            ctx.stroke(crescent, with: .color(pal.highlight(s).c(0.7)), style: StrokeStyle(lineWidth: max(r * 0.16, d.minWidth(0.4)), lineCap: .round))
        }
        // 鏡面
        let hr = r * 0.3
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.52, y: p.y - r * 0.6, width: hr * 1.5, height: hr)), with: .color(.white.opacity(0.9)))
        ctx.stroke(disc(p, r), with: .color(pal.deep(s).c(0.5)), lineWidth: d.w(r * 0.06, minPx: 0.35))
    }

    static func teardrop(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, s: DecoScheme, pal: ItemPalette, d: Detail) {
        var t = Path()
        t.move(to: CGPoint(x: p.x, y: p.y - r * 2.1))
        t.addCurve(to: CGPoint(x: p.x + r, y: p.y + r * 0.1), control1: CGPoint(x: p.x + r * 0.15, y: p.y - r * 1.2), control2: CGPoint(x: p.x + r, y: p.y - r * 0.6))
        t.addArc(center: p, radius: r, startAngle: .degrees(5), endAngle: .degrees(175), clockwise: false)
        t.addCurve(to: CGPoint(x: p.x, y: p.y - r * 2.1), control1: CGPoint(x: p.x - r, y: p.y - r * 0.6), control2: CGPoint(x: p.x - r * 0.15, y: p.y - r * 1.2))
        t.closeSubpath()
        ctx.fill(t, with: .linearGradient(Gradient(colors: [pal.fill(s).mix(.white, 0.4).c(0.6), pal.fill(s).c(0.85), pal.deep(s).c(0.9)]),
                                          startPoint: CGPoint(x: p.x, y: p.y - r * 2), endPoint: CGPoint(x: p.x, y: p.y + r)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.55, width: r * 0.35, height: r * 0.5)), with: .color(.white.opacity(0.85)))
        ctx.stroke(t, with: .color(pal.deep(s).c(0.45)), lineWidth: d.w(r * 0.07, minPx: 0.35))
    }

    /// 同心の波紋。各輪は「明るい峰＋外側の暗い谷」の二重線で立体に見せる。ratio<1 で遠近の楕円。
    static func ripple(_ ctx: GraphicsContext, center: CGPoint, radius R: CGFloat, rings: Int, ratio: CGFloat = 1, rotation: CGFloat = 0,
                       s: DecoScheme, pal: ItemPalette, d: Detail, width: CGFloat, alpha: Double = 1) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: ratio)
        for i in 0..<rings {
            let t = CGFloat(i + 1) / CGFloat(rings)
            let r = R * (0.22 + 0.78 * pow(t, 1.15))
            let fade = Double(1 - t * 0.78) * alpha
            let w = d.w(width * (1.15 - 0.55 * t), minPx: 0.45)
            c.stroke(disc(.zero, r + w * 0.9), with: .color(pal.deep(s).c((s.isDark ? 0.55 : 0.28) * fade)), lineWidth: w * 1.2)
            c.stroke(disc(.zero, r), with: .color(pal.line(s).c(0.85 * fade)), lineWidth: w)
            c.stroke(disc(.zero, r - w * 0.35), with: .color(pal.highlight(s).c((s.isDark ? 0.55 : 0.8) * fade)), lineWidth: w * 0.35)
        }
    }

    /// 水底に揺れる光の網（コースティクス）：歪んだ小さな輪を敷き詰め、中心から外へ消す。
    static func caustics(_ ctx: GraphicsContext, center: CGPoint, radius R: CGFloat, cell: CGFloat,
                         s: DecoScheme, pal: ItemPalette, d: Detail, seed: UInt64, avoid: CGRect? = nil) {
        var rng = SeededRNG(seed)
        let col = pal.highlight(s)
        var c = ctx
        if s.isDark { c.blendMode = .plusLighter }
        let n = Int(ceil(R / cell))
        for gy in -n...n {
            for gx in -n...n {
                let p = center + CGPoint(x: (CGFloat(gx) + (gy % 2 == 0 ? 0 : 0.5)) * cell, y: CGFloat(gy) * cell * 0.86)
                    + CGPoint(x: rng.range(-0.25, 0.25) * cell, y: rng.range(-0.25, 0.25) * cell)
                let dist = (p - center).length / R
                guard dist < 1 else { continue }
                if let avoid, avoid.insetBy(dx: -cell * 0.6, dy: -cell * 0.6).contains(p) { continue }
                let fade = pow(1 - dist, 1.6)
                let loop = organicBlob(radius: cell * rng.range(0.36, 0.5), rng: &rng, points: 7, roughness: 0.28, center: p)
                c.stroke(loop, with: .color(col.c((s.isDark ? 0.3 : 0.6) * Double(fade))), lineWidth: d.w(cell * 0.05, minPx: 0.5))
            }
        }
    }
}

// MARK: - 水縁

enum RippleMotif: DecoMotif {
    /// アバターを「水に落ちた一滴」に見立て、そこから広がる同心の波紋で縁を作る。
    /// 対角に落ちた小さな雫の波紋が重なり（干渉）、交点がきらめく。
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0xA11E)
        let q = d.quality, boost = d.boost
        let hi = pal.highlight(s), deep = pal.deep(s), line = pal.line(s), line2 = pal.line2(s)

        // 二次波源（対角の雫）
        let sources: [(CGPoint, CGFloat)] = [(CGPoint.polar(1.12, deg(212)), 1.0), (CGPoint.polar(1.1, deg(36)), 0.85), (CGPoint.polar(1.1, deg(126)), 0.5)]
        func interference(_ p: CGPoint) -> CGFloat {
            var v: CGFloat = 0
            for (c, w) in sources.prefix(q < 0.4 ? 1 : 3) {
                let dist = (p - c).length
                v += w * 0.012 * sin(dist * 70) * exp(-dist * 4.5)
            }
            return v
        }

        // 1) 水の地：波紋の間にうっすら水の色
        ops.append(DrawOp(z: 0) { c in
            var ring = Path()
            ring.addPath(disc(.zero, 1.27))
            ring.addPath(disc(.zero, 0.93))
            c.fill(ring, with: .radialGradient(Gradient(stops: [
                .init(color: pal.fill(s).c(0), location: 0.93 / 1.27),
                .init(color: pal.fill(s).c(s.isDark ? 0.2 : 0.14), location: 1.0 / 1.27),
                .init(color: line2.c(s.isDark ? 0.08 : 0.06), location: 1.12 / 1.27),
                .init(color: line2.c(0), location: 1.0),
            ]), center: .zero, startRadius: 0, endRadius: 1.27), style: FillStyle(eoFill: true))
            // 縁の内側に水面の張り（メニスカス）
            c.stroke(disc(.zero, 0.972), with: .color(hi.c(s.isDark ? 0.35 : 0.6)), lineWidth: d.w(0.004, minPx: 0.5))
        })

        // 2) 一次の波紋：外へ行くほど弱く、間隔が開く。各輪は「谷の陰＋峰の線＋峰の光」
        let radii: [CGFloat] = q < 0.4 ? [1.0, 1.085, 1.18] : [1.0, 1.06, 1.125, 1.195, 1.265]
        for (i, r0) in radii.enumerated() {
            let t = CGFloat(i) / CGFloat(max(1, radii.count - 1))
            let fade = Double(1 - 0.72 * t)
            let wBase = (0.011 - 0.0055 * t) * boost
            let phase = rng.range(0, 6), m = CGFloat(Int(rng.range(3, 6)))
            var crest: [CGPoint] = [], trough: [CGPoint] = [], widths: [CGFloat] = [], alphas: [Double] = [], glints: [Double] = []
            let sh1 = rng.range(0, 6), sh2 = rng.range(0, 6), shK = CGFloat(Int(rng.range(5, 9)))
            for k in 0...300 {
                let a = CGFloat(k) / 300 * 2 * .pi
                let base = CGPoint.polar(r0, a)
                let r = r0 + 0.006 * sin(m * a + phase) + interference(base)
                crest.append(CGPoint.polar(r, a))
                trough.append(CGPoint.polar(r + wBase * 1.1, a))
                // 光を受ける左上で太く、右下で細い（立体の手がかり）
                let lit = 0.5 + 0.5 * cos(a - deg(225))
                widths.append(d.w(wBase * (0.65 + 0.6 * lit), minPx: q < 0.4 ? 0.8 : 0.45))
                // 揺らめき：明るい区間と沈む区間が交互に来る（全周が同じ明るさの「標的」にしない）
                let shimmer = 0.5 + 0.5 * sin(shK * a + sh1) * cos((shK - 2) * a + sh2)
                let floor: Double = i == 0 ? 0.55 : 0.18
                alphas.append(Double(0.92 * fade) * (floor + (1 - floor) * Double(shimmer)))
                glints.append(Double(max(0, shimmer - 0.55) / 0.45))
            }
            ops.append(DrawOp(z: 0.2 - Double(i) * 0.01) { c in
                drawVaryingStroke(c, points: trough, widths: widths.map { $0 * 1.25 }, alphas: alphas.map { $0 * (s.isDark ? 0.55 : 0.25) }, color: deep)
                drawVaryingStroke(c, points: crest, widths: widths, alphas: alphas, color: i == 0 ? line : line.mix(line2, Double(t)))
                var hc = c
                if s.isDark { hc.blendMode = .plusLighter }
                drawVaryingStroke(hc, points: crest.map { $0 * (1 - wBase * 0.25) }, widths: widths.map { $0 * 0.34 },
                                  alphas: glints.map { $0 * (s.isDark ? 0.8 : 0.95) * fade }, color: hi)
            })
        }

        // 3) 二次の波紋（対角の雫）：輪の外側だけに出す
        for (si, src) in sources.enumerated() where q > 0.35 || si == 0 {
            let (p, w) = src
            ops.append(DrawOp(z: 0.3 + Double(si) * 0.01) { c in
                var cc = c
                var clip = Path()
                clip.addPath(disc(.zero, 1.31))
                clip.addPath(disc(.zero, 0.985))
                cc.clip(to: clip, style: FillStyle(eoFill: true))
                Water.ripple(cc, center: p, radius: 0.22 * w * (q < 0.4 ? 1.15 : 1), rings: q < 0.4 ? 2 : 4, s: s, pal: pal, d: d,
                             width: 0.0075 * boost, alpha: 0.85)
            })
        }

        // 4) 雫：落ちて跳ねる一滴と、着水点の王冠の飛沫
        for (si, src) in sources.prefix(q < 0.4 ? 1 : 2).enumerated() {
            let (p, w) = src
            let outward = p.normalized
            let drop = p + outward * (0.075 * w) + outward.perpendicular * (si == 0 ? -0.02 : 0.02)
            ops.append(DrawOp(z: 1.0 + Double(si) * 0.01) { c in
                Water.droplet(c, drop, 0.024 * w * boost, s: s, pal: pal, d: d, shadow: false)
            })
        }

        // 5) 干渉の交点のきらめき（波紋どうしが重なる所）
        if q > 0.45 {
            for (c0, _) in sources.prefix(2) {
                for r0 in radii.dropFirst() {
                    for sign in [CGFloat(-1), 1] {
                        // 一次の輪（半径 r0）と二次の輪（半径 ~0.12）の交点の近似
                        let rr: CGFloat = 0.12
                        let dist = c0.length
                        let a = (r0 * r0 + dist * dist - rr * rr) / (2 * r0 * dist)
                        guard abs(a) <= 1 else { continue }
                        let ang = c0.angle + sign * acos(a)
                        let p = CGPoint.polar(r0, ang)
                        ops.append(DrawOp(z: 1.4) { c in
                            var cc = c
                            if s.isDark { cc.blendMode = .plusLighter }
                            cc.translateBy(x: p.x, y: p.y)
                            cc.fill(Celestial.sparklePath(long: 0.024, waist: 0.0028), with: .color(hi.c(0.95)))
                        })
                    }
                }
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0x51)
        var inner = ctx
        inner.clip(to: cc.shape)

        // 水面の溜まり（右下）と水底の光の網。本文列は避ける
        inner.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [pal.fill(s).c(s.isDark ? 0.16 : 0.12), pal.fill(s).c(0)]),
                                                        center: CGPoint(x: cc.rect.maxX - 50 * k, y: cc.rect.maxY), startRadius: 0, endRadius: 140 * k))
        if !cc.tiny {
            Water.caustics(inner, center: CGPoint(x: cc.rect.maxX - 46 * k, y: cc.rect.maxY - 10 * k), radius: 100 * k, cell: 13 * k,
                           s: s, pal: pal, d: d, seed: 7, avoid: cc.textZone)
            Water.caustics(inner, center: CGPoint(x: cc.rect.minX + 6 * k, y: cc.rect.minY + 6 * k), radius: 64 * k, cell: 11 * k,
                           s: s, pal: pal, d: d, seed: 9, avoid: cc.textZone)
        }

        // 波紋（水面を斜めから見た楕円）。本文列にかからない高さに中心を置く
        let main = CGPoint(x: cc.rect.maxX - 60 * k, y: cc.rect.maxY - 16 * k)
        Water.ripple(inner, center: main, radius: 74 * k, rings: cc.tiny ? 3 : 5, ratio: 0.36, s: s, pal: pal, d: d, width: 1.0 * k)
        Water.ripple(inner, center: CGPoint(x: cc.rect.minX + 26 * k, y: cc.rect.maxY - 12 * k), radius: 34 * k, rings: 3, ratio: 0.36, s: s, pal: pal, d: d, width: 0.8 * k, alpha: 0.8)
        Water.ripple(inner, center: CGPoint(x: cc.rect.maxX - 14 * k, y: cc.rect.minY + 40 * k), radius: 26 * k, rings: 3, ratio: 0.36, s: s, pal: pal, d: d, width: 0.7 * k, alpha: 0.65)

        // 落ちる一滴と、ガラスに付いた水滴
        Water.teardrop(ctx, CGPoint(x: main.x, y: main.y - 30 * k), 2.6 * k, s: s, pal: pal, d: d)
        if !cc.tiny {
            let beads: [(CGFloat, CGFloat, CGFloat)] = [(-18, -46, 3.2), (-8, -60, 1.8), (-30, -38, 1.4), (-112, -10, 2.0), (-6, -96, 1.6)]
            for (dx, dy, r) in beads {
                Water.droplet(ctx, CGPoint(x: cc.rect.maxX + dx * k, y: cc.rect.maxY + dy * k), r * k, s: s, pal: pal, d: d)
            }
            for (dx, dy, r) in [(CGFloat(14), CGFloat(70), CGFloat(2.4)), (24, 84, 1.4)] {
                Water.droplet(ctx, CGPoint(x: cc.rect.minX + dx * k, y: cc.rect.minY + dy * k + 90 * k), r * k, s: s, pal: pal, d: d)
            }
        }

        CardBase.drawRule(ctx, cc, gap: 28) { c, p, flip in
            var f = c
            f.translateBy(x: p.x, y: p.y)
            if flip { f.scaleBy(x: 1, y: -1) }
            var arcs = Path()
            for (r, a) in [(CGFloat(5.5), 1.0), (9.0, 0.6)] {
                arcs.move(to: CGPoint(x: -r * k, y: 0))
                arcs.addQuadCurve(to: CGPoint(x: r * k, y: 0), control: CGPoint(x: 0, y: r * 0.55 * k))
                f.stroke(arcs, with: .color(pal.line(s).c(0.7 * a)), lineWidth: d.w(0.7 * k, minPx: 0.6))
                arcs = Path()
            }
            Water.droplet(f, CGPoint(x: 0, y: -0.5 * k), 2.6 * k, s: s, pal: pal, d: d, shadow: false)
        }
    }
}

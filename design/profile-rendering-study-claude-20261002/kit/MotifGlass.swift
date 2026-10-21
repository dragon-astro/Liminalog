// 硝子点：細い糸に通した硝子玉（丸玉・切子玉・雫玉）。屈折で下側に光が集まり、上に鏡面が乗る。
import SwiftUI

enum Glass {
    enum Kind { case round, faceted, drop }

    static func bead(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, kind: Kind, tint: RGB, s: DecoScheme, d: Detail, rotation: CGFloat = 0) {
        let body = s.isDark ? tint : tint.withLightness(0.62, saturationBoost: 0.9)
        let deep = s.isDark ? tint.withLightness(0.3) : tint.withLightness(0.38)
        // 影（曙では暖色の柔らかい影）
        if !s.isDark {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.85, y: p.y + r * 0.55, width: r * 1.7, height: r * 0.7)),
                     with: .radialGradient(Gradient(colors: [RGB(0xA7774F).c(0.22), RGB(0xA7774F).c(0)]), center: CGPoint(x: p.x, y: p.y + r * 0.9), startRadius: 0, endRadius: r))
        }
        switch kind {
        case .round:
            ctx.fill(disc(p, r), with: .radialGradient(Gradient(stops: [
                .init(color: body.mix(.white, 0.55).c(0.9), location: 0), .init(color: body.c(0.85), location: 0.55), .init(color: deep.c(0.95), location: 1),
            ]), center: CGPoint(x: p.x + r * 0.1, y: p.y + r * 0.35), startRadius: 0, endRadius: r * 1.15))
            // 屈折で底に集まる光
            var crescent = Path()
            crescent.addArc(center: p, radius: r * 0.68, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            ctx.stroke(crescent, with: .color(RGB.white.c(0.55)), style: StrokeStyle(lineWidth: max(r * 0.14, d.minWidth(0.4)), lineCap: .round))
        case .faceted:
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(rotation))
            let n = 8
            var outline = Path()
            var verts: [CGPoint] = []
            for i in 0..<n { verts.append(CGPoint.polar(r, CGFloat(i) / CGFloat(n) * 2 * .pi + .pi / 8)) }
            outline.move(to: verts[0]); for v in verts.dropFirst() { outline.addLine(to: v) }; outline.closeSubpath()
            for i in 0..<n {
                var facet = Path()
                facet.move(to: .zero); facet.addLine(to: verts[i]); facet.addLine(to: verts[(i + 1) % n]); facet.closeSubpath()
                let shade = 0.5 + 0.5 * cos(CGFloat(i) / CGFloat(n) * 2 * .pi - deg(225) + rotation)
                c.fill(facet, with: .color(body.mix(.white, Double(shade) * 0.6).mix(deep, Double(1 - shade) * 0.5).c(0.92)))
            }
            // 天面（テーブル）
            var table = Path()
            for i in 0..<n {
                let v = verts[i] * 0.45
                if i == 0 { table.move(to: v) } else { table.addLine(to: v) }
            }
            table.closeSubpath()
            c.fill(table, with: .color(body.mix(.white, 0.45).c(0.85)))
            c.stroke(table, with: .color(RGB.white.c(0.6)), lineWidth: d.w(r * 0.04, minPx: 0.3))
            c.stroke(outline, with: .color(deep.c(0.75)), lineWidth: d.w(r * 0.06, minPx: 0.35))
        case .drop:
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(rotation))
            var t = Path()
            t.move(to: CGPoint(x: 0, y: -r * 1.8))
            t.addCurve(to: CGPoint(x: r, y: r * 0.1), control1: CGPoint(x: r * 0.2, y: -r * 1.1), control2: CGPoint(x: r, y: -r * 0.6))
            t.addArc(center: .zero, radius: r, startAngle: .degrees(5), endAngle: .degrees(175), clockwise: false)
            t.addCurve(to: CGPoint(x: 0, y: -r * 1.8), control1: CGPoint(x: -r, y: -r * 0.6), control2: CGPoint(x: -r * 0.2, y: -r * 1.1))
            c.fill(t, with: .linearGradient(Gradient(colors: [body.mix(.white, 0.4).c(0.85), body.c(0.85), deep.c(0.95)]),
                                            startPoint: CGPoint(x: 0, y: -r * 1.8), endPoint: CGPoint(x: 0, y: r)))
            c.stroke(t, with: .color(deep.c(0.6)), lineWidth: d.w(r * 0.06, minPx: 0.35))
        }
        // 鏡面と縁の光
        let hr = r * 0.28
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.58, width: hr * 1.5, height: hr)), with: .color(RGB.white.c(0.95)))
        ctx.fill(disc(CGPoint(x: p.x + r * 0.42, y: p.y - r * 0.2), r * 0.07), with: .color(RGB.white.c(0.8)))
        if kind == .round {
            ctx.stroke(disc(p, r), with: .color(deep.c(0.55)), lineWidth: d.w(r * 0.06, minPx: 0.35))
        }
    }

    /// 糸に沿って玉を並べる（大小のリズム、丸玉と切子玉を交互に）
    static func strand(_ ctx: GraphicsContext, points: [CGPoint], spacingScale: CGFloat, radius r: CGFloat, tints: [RGB], s: DecoScheme, d: Detail, threadColor: RGB) {
        guard points.count > 1 else { return }
        ctx.stroke(smoothPath(points, closed: false), with: .color(threadColor.c(0.7)), lineWidth: d.w(r * 0.08, minPx: 0.45))
        var cum: [CGFloat] = [0]
        for i in 1..<points.count { cum.append(cum[i - 1] + (points[i] - points[i - 1]).length) }
        var dist: CGFloat = r
        var idx = 0, n = 0
        while dist < cum.last! - r * 0.5 {
            while idx < cum.count - 2 && cum[idx + 1] < dist { idx += 1 }
            let f = (dist - cum[idx]) / max(1e-6, cum[idx + 1] - cum[idx])
            let p = lerp(points[idx], points[idx + 1], f)
            let big = n % 3 == 0
            let rr = r * (big ? 1.0 : 0.62)
            bead(ctx, at: p, radius: rr, kind: big ? .round : .faceted, tint: tints[n % tints.count], s: s, d: d, rotation: CGFloat(n) * 0.4)
            dist += (big ? r * 1.0 : r * 0.62) + (n % 3 == 2 ? r * 1.0 : r * 0.62) + r * 0.1 * spacingScale
            n += 1
        }
    }
}

enum GlassMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let tints = [pal.primary, pal.secondary, pal.primary.mix(pal.secondary, 0.5)]
        // 糸の輪と玉：ちょうどアバターの縁に並べ、玉の半分が外へ出る
        let R: CGFloat = 1.035
        let beadR = 0.05 * boost
        var pts: [CGPoint] = []
        for i in 0...360 { pts.append(CGPoint.polar(R, deg(-90) + CGFloat(i) / 360 * 2 * .pi)) }
        ops.append(DrawOp(z: 0) { c in
            if let (g, a) = pal.glow(s) {
                c.drawLayer { l in
                    l.addFilter(.blur(radius: 0.03))
                    l.stroke(disc(.zero, R), with: .color(g.c(a * 0.7)), lineWidth: 0.06)
                }
            }
            Glass.strand(c, points: pts, spacingScale: q < 0.4 ? 0 : 1, radius: beadR, tints: tints, s: s, d: d,
                         threadColor: s.isDark ? pal.secondary.mix(.white, 0.4) : pal.line(s))
        })
        // 下に垂れる雫玉の飾り（三連）
        if q > 0.25 {
            ops.append(DrawOp(z: 1) { c in
                for (i, dx) in [CGFloat(-0.07), 0, 0.07].enumerated() {
                    let top = CGPoint(x: dx, y: R + beadR * 0.6)
                    let len: CGFloat = i == 1 ? 0.13 : 0.08
                    let end = CGPoint(x: dx * 1.1, y: top.y + len)
                    var thread = Path(); thread.move(to: top); thread.addLine(to: end)
                    c.stroke(thread, with: .color((s.isDark ? pal.secondary.mix(.white, 0.4) : pal.line(s)).c(0.7)), lineWidth: d.w(0.004, minPx: 0.45))
                    Glass.bead(c, at: CGPoint(x: end.x, y: end.y + (i == 1 ? 0.034 : 0.026) * boost), radius: (i == 1 ? 0.034 : 0.026) * boost, kind: .drop,
                               tint: tints[i % 2], s: s, d: d, rotation: .pi)
                }
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let tints = [pal.primary, pal.secondary, pal.primary.mix(pal.secondary, 0.5)]
        CardBase.drawGround(ctx, cc, seed: 0x6B)
        var inner = ctx
        inner.clip(to: cc.shape)
        // 薄膜の虹（ごく淡い斜めの帯）：二色の範囲で
        if !cc.tiny {
            inner.drawLayer { l in
                l.addFilter(.blur(radius: 4 * k))
                for (i, x0) in [CGFloat(0.62), 0.7, 0.78].enumerated() {
                    var band = Path()
                    let xa = cc.rect.minX + cc.rect.width * x0
                    band.move(to: CGPoint(x: xa, y: cc.rect.maxY)); band.addLine(to: CGPoint(x: xa + 50 * k, y: cc.rect.maxY))
                    band.addLine(to: CGPoint(x: xa + 140 * k, y: cc.rect.minY)); band.addLine(to: CGPoint(x: xa + 120 * k, y: cc.rect.minY)); band.closeSubpath()
                    l.fill(band, with: .color(tints[i % 3].c(s.isDark ? 0.08 : 0.1)))
                }
                l.blendMode = .destinationIn
                l.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [RGB.white.c(1), RGB.white.c(0)]), center: cc.br, startRadius: 0, endRadius: 170 * k))
            }
        }
        // 右上から下がる玉の連（懸垂線）
        func catenary(from a: CGPoint, to b: CGPoint, sag: CGFloat) -> [CGPoint] {
            (0...60).map { i in
                let t = CGFloat(i) / 60
                let p = lerp(a, b, t)
                return CGPoint(x: p.x, y: p.y + sag * 4 * t * (1 - t))
            }
        }
        let thread = s.isDark ? pal.secondary.mix(.white, 0.4) : pal.line(s)
        Glass.strand(ctx, points: catenary(from: CGPoint(x: cc.rect.maxX - 104 * k, y: cc.rect.minY - 2 * k), to: CGPoint(x: cc.rect.maxX + 4 * k, y: cc.rect.minY + 58 * k), sag: 26 * k),
                     spacingScale: 1, radius: 4.2 * k, tints: tints, s: s, d: d, threadColor: thread)
        Glass.strand(ctx, points: catenary(from: CGPoint(x: cc.rect.minX - 4 * k, y: cc.rect.maxY - 46 * k), to: CGPoint(x: cc.rect.minX + 120 * k, y: cc.rect.maxY + 4 * k), sag: 18 * k),
                     spacingScale: 1, radius: cc.tiny ? 4.6 * k : 3.6 * k, tints: tints.reversed(), s: s, d: d, threadColor: thread)
        // こぼれた玉
        if !cc.tiny {
            for (dx, dy, r, kind) in [(CGFloat(-24), CGFloat(-22), CGFloat(4.4), Glass.Kind.round), (-40, -12, 3.0, .faceted), (-12, -42, 2.4, .faceted), (-56, -26, 2.0, .round)] {
                Glass.bead(ctx, at: CGPoint(x: cc.rect.maxX + dx * k, y: cc.rect.maxY + dy * k), radius: r * k, kind: kind, tint: tints[Int(abs(dx)) % 3], s: s, d: d, rotation: dx)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 22) { c, p, flip in
            Glass.bead(c, at: CGPoint(x: p.x, y: p.y + (flip ? -0.5 : 0.5) * k), radius: 3.4 * k, kind: .faceted, tint: pal.primary, s: s, d: d, rotation: 0)
        }
    }
}

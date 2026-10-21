// 糸：撚り紐（三本撚り）・結び・房・刺繍（ランニングステッチ／サテン／フィッシュボーン／フレンチノット）。
import SwiftUI

enum Cord {
    static func strandColors(_ s: DecoScheme, _ pal: ItemPalette) -> [RGB] {
        // 主色を多めに、副色と生成りを細く混ぜる（コントラストの強い縞＝飴棒に見せない）
        if s.isDark { return [pal.primary, pal.primary.mix(pal.secondary, 0.55), pal.primary, RGB(0xF1E6FA)] }
        return [pal.primary.withLightness(0.6, saturationBoost: 0.85), pal.primary.mix(pal.secondary, 0.55).withLightness(0.66), pal.primary.withLightness(0.6, saturationBoost: 0.85), RGB(0xFFF6EE)]
    }

    /// 経路に沿って撚り紐を描く：斜めの俵形（陰影付き）を一定間隔で並べる
    static func rope(_ ctx: GraphicsContext, path pts: [CGPoint], width W: CGFloat, colors: [RGB], s: DecoScheme, d: Detail,
                     pitch: CGFloat = 0.62, slant: CGFloat = deg(48), closed: Bool = false) {
        guard pts.count > 1 else { return }
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + (pts[i] - pts[i - 1]).length) }
        let total = cum.last!
        let step = W * pitch
        let count = Int(total / step)
        var idx = 0
        let outline = (s.isDark ? RGB.black : RGB(0x5A4058))
        for k in 0..<count {
            let target = CGFloat(k) * step + step * 0.5
            while idx < cum.count - 2 && cum[idx + 1] < target { idx += 1 }
            let f = (target - cum[idx]) / max(1e-6, cum[idx + 1] - cum[idx])
            let c = lerp(pts[idx], pts[idx + 1], f)
            let tan = (pts[idx + 1] - pts[idx]).normalized
            let col = colors[k % colors.count]
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(tan.angle + slant))
            let L = W * 1.32, T = W * 0.56
            let cap = Path(roundedRect: CGRect(x: -L / 2, y: -T / 2, width: L, height: T), cornerRadius: T / 2)
            g.fill(cap, with: .linearGradient(Gradient(stops: [
                .init(color: col.mix(.black, s.isDark ? 0.55 : 0.4).c(), location: 0),
                .init(color: col.c(), location: 0.3),
                .init(color: col.mix(.white, 0.38).c(), location: 0.48),
                .init(color: col.c(), location: 0.66),
                .init(color: col.mix(.black, s.isDark ? 0.6 : 0.45).c(), location: 1),
            ]), startPoint: CGPoint(x: 0, y: -T / 2), endPoint: CGPoint(x: 0, y: T / 2)))
            if d.px(W) > 6 {
                // 糸の撚り目（細い筋）
                var fib = Path()
                for j in 0..<3 {
                    let y = (CGFloat(j) - 1) * T * 0.22
                    fib.move(to: CGPoint(x: -L * 0.34, y: y)); fib.addLine(to: CGPoint(x: L * 0.34, y: y + T * 0.05))
                }
                g.stroke(fib, with: .color(col.mix(.black, 0.25).c(0.35)), lineWidth: d.w(T * 0.05, minPx: 0.3))
            }
            g.stroke(cap, with: .color(outline.c(s.isDark ? 0.45 : 0.3)), lineWidth: d.w(T * 0.07, minPx: 0.35))
        }
    }

    /// 刺繍のサテンステッチで埋めた花弁・葉
    static func satin(_ ctx: GraphicsContext, shape: Path, axisAngle: CGFloat, center: CGPoint, span: CGFloat, spacing: CGFloat,
                      color: RGB, s: DecoScheme, d: Detail) {
        var c = ctx
        c.clip(to: shape)
        c.fill(shape, with: .color(color.c(0.35)))
        var lines = Path()
        let dir = CGPoint.polar(1, axisAngle + .pi / 2 + 0.25)
        let nrm = CGPoint.polar(1, axisAngle)
        var t = -span
        while t <= span {
            let p = center + nrm * t
            lines.move(to: p - dir * span); lines.addLine(to: p + dir * span)
            t += spacing
        }
        c.stroke(lines, with: .color(color.c(0.95)), lineWidth: d.w(spacing * 0.72, minPx: 0.4))
        var hl = Path()
        t = -span + spacing * 0.5
        while t <= span {
            let p = center + nrm * t
            hl.move(to: p - dir * span); hl.addLine(to: p + dir * span)
            t += spacing * 2
        }
        c.stroke(hl, with: .color(color.mix(.white, 0.5).c(0.45)), lineWidth: d.w(spacing * 0.2, minPx: 0.3))
        ctx.stroke(shape, with: .color(color.mix(.black, s.isDark ? 0.35 : 0.3).c(0.6)), lineWidth: d.w(spacing * 0.35, minPx: 0.35))
    }

    static func frenchKnot(_ ctx: GraphicsContext, _ p: CGPoint, _ r: CGFloat, color: RGB, d: Detail) {
        ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [color.mix(.white, 0.5).c(), color.c(), color.mix(.black, 0.3).c()]),
                                                   center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        var swirl = Path()
        swirl.addArc(center: p, radius: r * 0.55, startAngle: .degrees(0), endAngle: .degrees(250), clockwise: false)
        ctx.stroke(swirl, with: .color(color.mix(.black, 0.3).c(0.5)), lineWidth: d.w(r * 0.15, minPx: 0.3))
    }
}

// MARK: - 糸枠

enum ThreadMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let colors = Cord.strandColors(s, pal)
        let W = 0.062 * (q < 0.4 ? 1.25 : 1)

        // 1) 内側のランニングステッチ（縫い目）
        if q > 0.4 {
            ops.append(DrawOp(z: 0) { c in
                let r = 0.93
                c.stroke(disc(.zero, r), with: .color((s.isDark ? RGB.black : RGB(0x8A6F80)).c(0.25)),
                         style: StrokeStyle(lineWidth: d.w(0.008, minPx: 0.5), lineCap: .round, dash: [0.03, 0.022]))
                c.stroke(disc(.zero, r - 0.002), with: .color(colors[2].c(s.isDark ? 0.85 : 0.95)),
                         style: StrokeStyle(lineWidth: d.w(0.006, minPx: 0.5), lineCap: .round, dash: [0.03, 0.022]))
            })
        }
        // 2) 撚り紐の輪
        var ring: [CGPoint] = []
        for i in 0...720 {
            let a = CGFloat(i) / 720 * 2 * .pi + deg(90)
            ring.append(CGPoint.polar(1.0 + 0.004 * sin(4 * a), a))
        }
        ops.append(DrawOp(z: 0.2) { c in
            c.stroke(disc(.zero, 1.0), with: .color((s.isDark ? RGB.black : RGB(0xA7774F)).c(s.isDark ? 0.45 : 0.18)), lineWidth: W * 1.1)
            Cord.rope(c, path: ring, width: W, colors: colors, s: s, d: d)
        })
        // 3) 結び（八の字）を対角に
        for (i, ad) in [CGFloat(215), CGFloat(36)].enumerated() {
            let a0 = deg(ad)
            let tan = CGPoint(x: -sin(a0), y: cos(a0)), nrm = CGPoint(x: cos(a0), y: sin(a0))
            let A: CGFloat = (i == 0 ? 0.17 : 0.145) * (q < 0.4 ? 1.1 : 1), B: CGFloat = (i == 0 ? 0.095 : 0.085)
            let base = CGPoint.polar(1.0 + 0.045, a0)
            var knot: [CGPoint] = []
            for j in 0...240 {
                let t = CGFloat(j) / 240 * 2 * .pi
                let u = A * sin(t), v = B * sin(t) * cos(t) * 1.6
                knot.append(base + tan * u + nrm * v)
            }
            ops.append(DrawOp(z: 0.6 + Double(i) * 0.01) { c in
                Cord.rope(c, path: knot, width: W * 0.9, colors: [colors[1], colors[3], colors[1], colors[0]], s: s, d: d)
                // 結び目の芯
                c.fill(disc(base, W * 0.42), with: .radialGradient(Gradient(colors: [colors[3].c(), colors[1].c(), colors[1].mix(.black, 0.35).c()]),
                                                                    center: base - CGPoint(x: W * 0.12, y: W * 0.12), startRadius: 0, endRadius: W * 0.5))
            })
        }
        // 4) 房（下）
        let a0 = deg(90)
        let tan = CGPoint(x: -sin(a0), y: cos(a0)), nrm = CGPoint(x: cos(a0), y: sin(a0))
        let bead = CGPoint.polar(1.075, a0)
        ops.append(DrawOp(z: 0.7) { c in
            // 紐から房へ
            var hang = Path(); hang.move(to: CGPoint.polar(1.02, a0)); hang.addLine(to: bead)
            c.stroke(hang, with: .color(colors[0].c()), lineWidth: d.w(W * 0.3, minPx: 0.6))
            let br = 0.026 * boost
            c.fill(disc(bead, br), with: .radialGradient(Gradient(colors: [colors[2].c(), colors[1].c(), colors[1].mix(.black, 0.4).c()]),
                                                          center: bead - CGPoint(x: br * 0.35, y: br * 0.35), startRadius: 0, endRadius: br * 1.3))
            // 房の頭（巻き）
            let capTop = bead + nrm * (br * 1.1)
            let capH = 0.035 * boost, capW = 0.05 * boost
            var cap = Path()
            cap.addRoundedRect(in: CGRect(x: -capW / 2, y: 0, width: capW, height: capH), cornerSize: CGSize(width: capW * 0.3, height: capW * 0.3))
            var cc = c
            cc.translateBy(x: capTop.x, y: capTop.y)
            cc.rotate(by: .radians(a0 - .pi / 2))
            cc.fill(cap, with: .linearGradient(Gradient(colors: [colors[0].mix(.black, 0.3).c(), colors[0].c(), colors[0].mix(.white, 0.35).c(), colors[0].c()]),
                                               startPoint: CGPoint(x: -capW / 2, y: 0), endPoint: CGPoint(x: capW / 2, y: 0)))
            for j in 1..<4 {
                var band = Path(); band.move(to: CGPoint(x: -capW / 2, y: capH * CGFloat(j) / 4)); band.addLine(to: CGPoint(x: capW / 2, y: capH * CGFloat(j) / 4))
                cc.stroke(band, with: .color(colors[2].c(0.7)), lineWidth: d.w(0.002, minPx: 0.3))
            }
            // 房の糸
            var rr = SeededRNG(77)
            let fringe = q < 0.4 ? 8 : 16
            for j in 0..<fringe {
                let x0 = (CGFloat(j) / CGFloat(fringe - 1) - 0.5) * capW * 0.9
                var pts: [CGPoint] = []
                let len = 0.11 * boost * rr.range(0.85, 1.05)
                let spread = x0 * 0.9
                for m in 0...14 {
                    let t = CGFloat(m) / 14
                    pts.append(CGPoint(x: x0 + spread * t + 0.004 * sin(t * 6 + CGFloat(j)), y: capH + len * t))
                }
                let col = colors[j % 2]
                cc.stroke(smoothPath(pts, closed: false), with: .color(col.c(0.95)), style: StrokeStyle(lineWidth: d.w(0.0042, minPx: 0.5), lineCap: .round))
            }
            _ = tan
        })
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let colors = Cord.strandColors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x7E)
        var inner = ctx
        inner.clip(to: cc.shape)

        // 布目（細かな縦横の織り）
        if !cc.tiny {
            var weave = Path()
            var x = cc.rect.minX
            while x < cc.rect.maxX { weave.move(to: CGPoint(x: x, y: cc.rect.minY)); weave.addLine(to: CGPoint(x: x, y: cc.rect.maxY)); x += 2.2 * k }
            var y = cc.rect.minY
            while y < cc.rect.maxY { weave.move(to: CGPoint(x: cc.rect.minX, y: y)); weave.addLine(to: CGPoint(x: cc.rect.maxX, y: y)); y += 2.2 * k }
            inner.stroke(weave, with: .color((s.isDark ? RGB.white : RGB(0x8A6F80)).c(s.isDark ? 0.025 : 0.035)), lineWidth: d.w(0.3 * k, minPx: 0.4))
        }

        // ランニングステッチの縁取り（罫の内側）
        let stitchRect = cc.rect.insetBy(dx: 14 * k, dy: 14 * k)
        let stitch = Path(roundedRect: stitchRect, cornerRadius: max(2, cc.radius - 11 * k), style: .continuous)
        let dash: [CGFloat] = [5 * k, 3.4 * k]
        ctx.stroke(stitch, with: .color((s.isDark ? RGB.black : RGB(0x8A6F80)).c(0.3)), style: StrokeStyle(lineWidth: d.w(1.5 * k, minPx: 0.8), lineCap: .round, dash: dash, dashPhase: -0.3 * k))
        ctx.stroke(stitch, with: .color(colors[1].c(0.95)), style: StrokeStyle(lineWidth: d.w(1.1 * k, minPx: 0.7), lineCap: .round, dash: dash))
        ctx.stroke(stitch, with: .color(RGB.white.c(0.5)), style: StrokeStyle(lineWidth: d.w(0.35 * k, minPx: 0.35), lineCap: .round, dash: dash))

        // 角の刺繍：サテンの花・フィッシュボーンの葉・フレンチノット・ステムの茎
        func flower(_ c: CGPoint, _ r: CGFloat, _ col: RGB, _ rot: CGFloat) {
            for i in 0..<5 {
                let a = rot + CGFloat(i) / 5 * 2 * .pi
                var pc = ctx
                pc.translateBy(x: c.x, y: c.y)
                pc.rotate(by: .radians(a))
                let petal = petalShape(r)
                Cord.satin(pc, shape: petal, axisAngle: 0, center: CGPoint(x: r * 0.5, y: 0), span: r * 0.6, spacing: max(0.55 * k, r * 0.11), color: col, s: s, d: d)
            }
            Cord.frenchKnot(ctx, c, r * 0.22, color: colors[3].mix(RGB(0xF2C46A), 0.5), d: d)
        }
        func leaf(_ base: CGPoint, _ angle: CGFloat, _ L: CGFloat) {
            var c = ctx
            c.translateBy(x: base.x, y: base.y)
            c.rotate(by: .radians(angle))
            var shape = Path()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: L, y: 0), control: CGPoint(x: L * 0.45, y: -L * 0.42))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: L * 0.45, y: L * 0.42))
            let green = s.isDark ? RGB(0x8FD9B6) : RGB(0x3E8E6E)
            var cl = c
            cl.clip(to: shape)
            cl.fill(shape, with: .color(green.c(0.3)))
            var bones = Path()
            var t: CGFloat = 0.1
            var side: CGFloat = 1
            while t < 0.95 {
                bones.move(to: CGPoint(x: L * t, y: 0)); bones.addLine(to: CGPoint(x: L * (t - 0.12), y: side * L * 0.32))
                t += 0.07; side *= -1
            }
            cl.stroke(bones, with: .color(green.c(0.95)), lineWidth: d.w(L * 0.06, minPx: 0.45))
            c.stroke(shape, with: .color(green.mix(.black, 0.3).c(0.6)), lineWidth: d.w(L * 0.03, minPx: 0.35))
        }
        func stem(_ from: CGPoint, _ to: CGPoint, _ ctrl: CGPoint) {
            var p = Path(); p.move(to: from); p.addQuadCurve(to: to, control: ctrl)
            let green = s.isDark ? RGB(0x8FD9B6) : RGB(0x3E8E6E)
            ctx.stroke(p, with: .color(green.c(0.9)), style: StrokeStyle(lineWidth: d.w(1.1 * k, minPx: 0.6), lineCap: .round, dash: [2.4 * k, 0.5 * k]))
        }
        let br = CGPoint(x: cc.rect.maxX - 30 * k, y: cc.rect.maxY - 30 * k)
        stem(CGPoint(x: br.x + 14 * k, y: br.y + 16 * k), br, CGPoint(x: br.x + 4 * k, y: br.y + 12 * k))
        stem(CGPoint(x: br.x - 6 * k, y: br.y + 18 * k), CGPoint(x: br.x - 36 * k, y: br.y + 8 * k), CGPoint(x: br.x - 18 * k, y: br.y + 18 * k))
        leaf(CGPoint(x: br.x - 6 * k, y: br.y + 10 * k), deg(200), 14 * k)
        leaf(CGPoint(x: br.x + 6 * k, y: br.y + 6 * k), deg(-60), 12 * k)
        leaf(CGPoint(x: br.x - 26 * k, y: br.y + 12 * k), deg(160), 11 * k)
        flower(br, 9 * k, colors[0], 0.3)
        flower(CGPoint(x: br.x - 38 * k, y: br.y + 6 * k), 6.5 * k, colors[1], 1.0)
        for (dx, dy) in [(CGFloat(-18), CGFloat(-10)), (-46, 0), (10, -16), (-28, 16)] {
            Cord.frenchKnot(ctx, CGPoint(x: br.x + dx * k, y: br.y + dy * k), 1.5 * k, color: colors[(Int(dx) & 1)], d: d)
        }
        if !cc.tiny {
            let tl = CGPoint(x: cc.rect.minX + 24 * k, y: cc.rect.minY + 24 * k)
            leaf(CGPoint(x: tl.x + 4 * k, y: tl.y + 4 * k), deg(40), 11 * k)
            flower(tl, 6.5 * k, colors[1], 0.6)
            Cord.frenchKnot(ctx, CGPoint(x: tl.x + 14 * k, y: tl.y - 4 * k), 1.4 * k, color: colors[0], d: d)
            // 右下から外へ垂れる糸と針
            var thread = Path()
            let start = CGPoint(x: stitchRect.maxX - 30 * k, y: stitchRect.maxY)
            thread.move(to: start)
            thread.addCurve(to: CGPoint(x: cc.rect.maxX + 6 * k, y: cc.rect.maxY - 46 * k),
                            control1: CGPoint(x: start.x + 26 * k, y: start.y + 18 * k), control2: CGPoint(x: cc.rect.maxX + 18 * k, y: cc.rect.maxY - 6 * k))
            ctx.stroke(thread, with: .color(colors[1].c(0.95)), style: StrokeStyle(lineWidth: d.w(1.0 * k, minPx: 0.6), lineCap: .round))
            var needle = ctx
            needle.translateBy(x: cc.rect.maxX + 6 * k, y: cc.rect.maxY - 46 * k)
            needle.rotate(by: .radians(deg(-78)))
            let nl = 22 * k
            var body = Path()
            body.move(to: CGPoint(x: 0, y: -0.7 * k)); body.addLine(to: CGPoint(x: nl, y: 0)); body.addLine(to: CGPoint(x: 0, y: 0.7 * k)); body.closeSubpath()
            needle.fill(body, with: .linearGradient(Gradient(colors: [RGB(0xE8EEF6).c(), RGB(0x9AA4B8).c()]), startPoint: CGPoint(x: 0, y: -0.7 * k), endPoint: CGPoint(x: 0, y: 0.7 * k)))
            needle.stroke(Path(ellipseIn: CGRect(x: 1.2 * k, y: -0.35 * k, width: 2.6 * k, height: 0.7 * k)), with: .color(RGB(0x5A6478).c(0.8)), lineWidth: d.w(0.3 * k, minPx: 0.3))
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            // 小さな結び目
            let q = CGPoint(x: p.x, y: p.y + (flip ? -1 : 1) * 0.5 * k)
            var path: [CGPoint] = []
            for j in 0...80 {
                let t = CGFloat(j) / 80 * 2 * .pi
                path.append(q + CGPoint(x: 7 * k * sin(t), y: 3.2 * k * sin(t) * cos(t) * 1.6))
            }
            Cord.rope(c, path: path, width: 2.6 * k, colors: colors, s: s, d: d)
        }
    }

    static func petalShape(_ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.2, y: -r * 0.55), control2: CGPoint(x: r * 0.95, y: -r * 0.5))
        p.addCurve(to: .zero, control1: CGPoint(x: r * 0.95, y: r * 0.5), control2: CGPoint(x: r * 0.2, y: r * 0.55))
        p.closeSubpath()
        return p
    }
}

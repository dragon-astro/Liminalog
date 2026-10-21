// 波端：青海波（重なる同心の扇）の帯と、対角で立ち上がって巻く波頭（泡の爪）。水縁の「水面の波紋」とは別の、文様としての波。
import SwiftUI

enum Wave {
    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> (fill: RGB, fill2: RGB, line: RGB, foam: RGB, deep: RGB) {
        if s.isDark { return (pal.primary.withLightness(0.32), pal.secondary.withLightness(0.36), pal.primary.mix(.white, 0.3), RGB(0xF2FBFF), pal.primary.withLightness(0.18)) }
        return (pal.primary.withLightness(0.86), pal.secondary.withLightness(0.88), pal.primary.withLightness(0.42), RGB.white, pal.primary.withLightness(0.32))
    }

    /// 青海波の一枚：外側の半円に同心の弧を三本
    static func scale(_ ctx: GraphicsContext, center p: CGPoint, radius R: CGFloat, up: CGFloat, fill: RGB, line: RGB, d: Detail, rings: Int = 3) {
        var half = Path()
        half.addArc(center: p, radius: R, startAngle: .radians(up - .pi / 2), endAngle: .radians(up + .pi / 2), clockwise: false)
        half.closeSubpath()
        ctx.fill(half, with: .color(fill.c()))
        for i in 0..<rings {
            let r = R * (1 - CGFloat(i) * 0.3)
            var arc = Path()
            arc.addArc(center: p, radius: r * 0.94, startAngle: .radians(up - .pi / 2 + 0.05), endAngle: .radians(up + .pi / 2 - 0.05), clockwise: false)
            ctx.stroke(arc, with: .color(line.c(i == 0 ? 0.95 : 0.75)), lineWidth: d.w(R * 0.07, minPx: 0.45))
        }
    }

    /// 巻く波頭。局所座標（x=流れの向き、y=上）を基線 base・向き dir・大きさ size で配置する。flip で左右反転
    static func crest(_ ctx: GraphicsContext, base: CGPoint, dir: CGFloat, size: CGFloat, flip: Bool, s: DecoScheme, pal: ItemPalette, d: Detail) {
        let col = colors(s, pal)
        var c = ctx
        c.translateBy(x: base.x, y: base.y)
        c.rotate(by: .radians(dir))
        c.scaleBy(x: flip ? -size : size, y: -size)   // y を上向きに
        // 波の山（前面）
        let mound: [CGPoint] = [CGPoint(x: -0.1, y: 0), CGPoint(x: 0.2, y: 0.12), CGPoint(x: 0.45, y: 0.42), CGPoint(x: 0.62, y: 0.5), CGPoint(x: 0.85, y: 0.32), CGPoint(x: 1.05, y: 0)]
        var body = smoothPath(mound, closed: false)
        body.closeSubpath()
        c.fill(body, with: .linearGradient(Gradient(colors: [col.fill.c(), col.deep.c()]), startPoint: CGPoint(x: 0.5, y: 0.5), endPoint: CGPoint(x: 0.5, y: 0)))
        // 巻き：中心線に沿った帯（根元が太く先が細い）
        let curl: [CGPoint] = [CGPoint(x: 0.95, y: 0.05), CGPoint(x: 0.85, y: 0.45), CGPoint(x: 0.65, y: 0.78), CGPoint(x: 0.4, y: 0.9),
                               CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.14, y: 0.62), CGPoint(x: 0.24, y: 0.52), CGPoint(x: 0.34, y: 0.58)]
        var center: [CGPoint] = []
        let sp = smoothPath(curl, closed: false)
        _ = sp
        for i in 0...40 {
            let t = CGFloat(i) / 40 * CGFloat(curl.count - 1)
            let j = min(Int(t), curl.count - 2), f = t - CGFloat(j)
            let p0 = curl[max(j - 1, 0)], p1 = curl[j], p2 = curl[j + 1], p3 = curl[min(j + 2, curl.count - 1)]
            let f2 = f * f, f3 = f2 * f
            center.append(CGPoint(x: 0.5 * (2 * p1.x + (-p0.x + p2.x) * f + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * f2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * f3),
                                  y: 0.5 * (2 * p1.y + (-p0.y + p2.y) * f + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * f2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * f3)))
        }
        let widths = (0...40).map { i -> CGFloat in 0.22 * pow(1 - CGFloat(i) / 40, 0.9) + 0.012 }
        let ribbon = ribbonPath(center, widths: widths)
        c.fill(ribbon, with: .linearGradient(Gradient(colors: [col.deep.c(), col.fill.c(), col.fill2.c()]), startPoint: CGPoint(x: 0.9, y: 0), endPoint: CGPoint(x: 0.3, y: 0.9)))
        // 帯の中の水の筋
        for off in [CGFloat(-0.25), 0.05, 0.3] {
            let pts = center.enumerated().map { (i, p) -> CGPoint in
                let a = center[max(0, i - 1)], b = center[min(center.count - 1, i + 1)]
                return p + (b - a).normalized.perpendicular * (widths[i] * off)
            }
            c.stroke(smoothPath(Array(pts.prefix(34)), closed: false), with: .color(col.line.c(0.7)), lineWidth: max(0.008, d.minWidth(0.4) / size))
        }
        // 泡の爪：巻きの外縁に沿って、外へ向かって曲がる短い指
        for i in stride(from: 10, to: 36, by: 3) {
            let a = center[max(0, i - 1)], b = center[min(center.count - 1, i + 1)]
            let nrm = (b - a).normalized.perpendicular * -1
            let root = center[i] + nrm * (widths[i] * 0.5)
            let tipLen = 0.07 + 0.04 * sin(CGFloat(i))
            let tip = root + nrm * tipLen + (b - a).normalized * (tipLen * 0.6)
            var claw = Path()
            claw.move(to: root)
            claw.addQuadCurve(to: tip, control: root + nrm * (tipLen * 0.9))
            c.stroke(claw, with: .color(col.foam.c(0.95)), style: StrokeStyle(lineWidth: max(0.022, d.minWidth(0.6) / size), lineCap: .round))
            c.fill(disc(tip, max(0.016, d.minWidth(0.5) / size)), with: .color(col.foam.c()))
        }
        c.stroke(ribbon, with: .color(col.deep.c(0.6)), lineWidth: max(0.006, d.minWidth(0.35) / size))
    }
}

enum WaveMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let col = Wave.colors(s, pal)
        let R = (0.055 + 0.02 * (1 - q))
        let rowsR: [CGFloat] = [0.975, 0.975 + R * 0.95]
        // 1) 青海波の帯：内側の列から順に重ねる（後の列が前の列の下半分を覆う）
        ops.append(DrawOp(z: 0) { c in
            var cc = c
            var clip = Path(); clip.addPath(disc(.zero, rowsR[1] + R * 1.02)); clip.addPath(disc(.zero, 0.955))
            cc.clip(to: clip, style: FillStyle(eoFill: true))
            for (j, rr) in rowsR.enumerated() {
                let n = Int((2 * .pi * rr) / (R * 1.9))
                for i in 0..<n {
                    let ang = (CGFloat(i) + (j % 2 == 0 ? 0 : 0.5)) / CGFloat(n) * 2 * .pi
                    Wave.scale(cc, center: CGPoint.polar(rr, ang), radius: R, up: ang, fill: (i + j) % 3 == 0 ? col.fill2 : col.fill, line: col.line, d: d, rings: q < 0.4 ? 2 : 3)
                }
            }
        })
        ops.append(DrawOp(z: 0.05) { c in
            c.stroke(disc(.zero, 0.958), with: .color(col.line.c(0.9)), lineWidth: d.w(0.004 * boost, minPx: 0.7))
        })
        // 2) 波頭：対角で帯から立ち上がる
        for (i, spec) in [(CGFloat(206), CGFloat(0.27), false), (CGFloat(40), CGFloat(0.22), true)].enumerated() where q > 0.2 || i == 0 {
            let (ad, size, flip) = spec
            let ang = deg(ad)
            let base = CGPoint.polar(rowsR[1] + R * 0.6, ang)
            let tangentDir = ang + .pi / 2
            ops.append(DrawOp(z: 0.5 + Double(i) * 0.01) { c in
                Wave.crest(c, base: base - CGPoint.polar(size * 0.5, tangentDir), dir: tangentDir, size: size * (q < 0.4 ? 1.1 : 1), flip: flip, s: s, pal: pal, d: d)
            })
        }
        // 3) 飛沫
        if q > 0.35 {
            var rng = SeededRNG(0xBA7E)
            for _ in 0..<26 {
                let ang = deg(rng.chance(0.6) ? rng.range(180, 240) : rng.range(15, 70))
                let p = CGPoint.polar(rng.range(1.12, 1.28), ang)
                let r = rng.range(0.004, 0.011)
                ops.append(DrawOp(z: 0.8) { c in
                    c.fill(disc(p, d.w(r, minPx: 0.6)), with: .color(col.foam.c(0.95)))
                    c.stroke(disc(p, d.w(r, minPx: 0.6)), with: .color(col.line.c(0.5)), lineWidth: d.w(r * 0.25, minPx: 0.3))
                })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = Wave.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0xBA)
        var inner = ctx
        inner.clip(to: cc.shape)
        // 青海波：右下と左上に、角から広がって中央へ消える
        func seigaiha(corner: CGPoint, reach: CGFloat, R: CGFloat) {
            inner.drawLayer { l in
                let cols = Int(cc.rect.width / (R * 2)) + 2, rows = Int(cc.rect.height / (R * 0.5)) + 2
                for j in 0..<rows {
                    for i in 0..<cols {
                        let x = cc.rect.minX + (CGFloat(i) + (j % 2 == 0 ? 0 : 0.5)) * R * 2
                        let y = cc.rect.minY + CGFloat(j) * R * 0.5
                        let p = CGPoint(x: x, y: y)
                        guard (p - corner).length < reach + R else { continue }
                        Wave.scale(l, center: p, radius: R, up: -.pi / 2, fill: (i + j) % 4 == 0 ? col.fill2 : col.fill, line: col.line, d: d, rings: 3)
                    }
                }
                l.blendMode = .destinationIn
                l.fill(Path(cc.rect.insetBy(dx: -20, dy: -20)), with: .radialGradient(Gradient(stops: [
                    .init(color: RGB.white.c(1), location: 0), .init(color: RGB.white.c(0.85), location: 0.55), .init(color: RGB.white.c(0), location: 1),
                ]), center: corner, startRadius: 0, endRadius: reach))
            }
        }
        seigaiha(corner: CGPoint(x: cc.rect.maxX, y: cc.rect.maxY), reach: (cc.tiny ? 90 : 120) * k, R: 9 * k)
        if !cc.tiny { seigaiha(corner: cc.tl, reach: 62 * k, R: 7 * k) }
        // 右下の大きな波頭
        Wave.crest(ctx, base: CGPoint(x: cc.rect.maxX - 64 * k, y: cc.rect.maxY + 2 * k), dir: 0, size: (cc.tiny ? 72 : 54) * k, flip: true, s: s, pal: pal, d: d)
        if !cc.tiny {
            var rng = SeededRNG(0xBB)
            for _ in 0..<18 {
                let p = CGPoint(x: cc.rect.maxX - rng.range(8, 70) * k, y: cc.rect.maxY - rng.range(46, 70) * k)
                if cc.textZone.contains(p) { continue }
                ctx.fill(disc(p, rng.range(0.6, 1.5) * k), with: .color(col.foam.c(0.95)))
                ctx.stroke(disc(p, rng.range(0.6, 1.5) * k), with: .color(col.line.c(0.5)), lineWidth: d.w(0.25 * k, minPx: 0.3))
            }
        }
        CardBase.drawRule(ctx, cc, gap: 26) { c, p, flip in
            let up: CGFloat = flip ? .pi / 2 : -.pi / 2
            let q = CGPoint(x: p.x, y: p.y + (flip ? -2.5 : 2.5) * k)
            Wave.scale(c, center: CGPoint(x: q.x - 5 * k, y: q.y), radius: 5 * k, up: up, fill: col.fill, line: col.line, d: d, rings: 2)
            Wave.scale(c, center: CGPoint(x: q.x + 5 * k, y: q.y), radius: 5 * k, up: up, fill: col.fill2, line: col.line, d: d, rings: 2)
            Wave.scale(c, center: CGPoint(x: q.x, y: q.y + (flip ? -2.5 : 2.5) * k), radius: 5 * k, up: up, fill: col.fill, line: col.line, d: d, rings: 2)
        }
    }
}

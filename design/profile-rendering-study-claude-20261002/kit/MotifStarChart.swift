// 星図線：最初の試作の「夜空の帯＋軌道＋星座」を移植。宵は夜空の帯、曙は淡い空色の紙に刷った星図として描き分ける。
import SwiftUI

private struct ChartColors {
    let bandStops: [(RGB, Double, CGFloat)]   // (色, α, 半径)
    let wisps: [RGB]
    let darkLane: RGB?
    let streak: [RGB]
    let dust: [RGB]
    let orbit: RGB
    let orbit2: RGB
    let additive: Bool

    static func make(_ s: DecoScheme, _ pal: ItemPalette) -> ChartColors {
        if s.isDark {
            return ChartColors(
                bandStops: [(RGB(0x111236), 0, 0.85), (RGB(0x111236), 0.9, 0.905), (RGB(0x18194A), 0.93, 0.975), (RGB(0x2E2A7A), 0.86, 1.04),
                            (RGB(0x5946B2), 0.5, 1.095), (RGB(0x5946B2), 0.16, 1.15), (RGB(0x5946B2), 0, 1.22)],
                wisps: [RGB(0x9468D0), RGB(0x8C93E8), pal.primary.mix(RGB(0x3F93BC), 0.5), RGB(0xE3A6D8)],
                darkLane: RGB(0x0E0E2E),
                streak: [RGB(0x8C93E8), RGB(0xC9B8F6), pal.primary.mix(.white, 0.3)],
                dust: [RGB(0xFFF4DA), RGB(0xF2CC7A), pal.primary.mix(.white, 0.35)],
                orbit: RGB(0xF2CC7A), orbit2: RGB(0xFFF4DA), additive: true)
        }
        let ink = pal.line(s)
        return ChartColors(
            bandStops: [(RGB(0xD3E7F8), 0, 0.85), (RGB(0xC9E0F6), 0.95, 0.905), (RGB(0xD6E4FA), 0.9, 0.975), (RGB(0xDCD8F6), 0.82, 1.04),
                        (RGB(0xE6DCF6), 0.55, 1.095), (RGB(0xEDE4F8), 0.2, 1.15), (RGB(0xEDE4F8), 0, 1.22)],
            wisps: [RGB(0xBFD6F4), RGB(0xD2C4F2), RGB(0xF4D9E6), RGB(0xC8E4F0)],
            darkLane: nil,
            streak: [ink.mix(.white, 0.35), RGB(0x9C8AD8)],
            dust: [ink, RGB(0xC9962E), ink.mix(.white, 0.25)],
            orbit: RGB(0xB8862F), orbit2: ink, additive: false)
    }
}

enum StarChartMotif: DecoMotif {
    static func swell(_ a: CGFloat) -> CGFloat { 0.5 + 0.5 * sin(a * 3 + 0.7) * cos(a * 2 - 0.4) }
    static func rIn(_ a: CGFloat) -> CGFloat { 0.905 + 0.014 * sin(5 * a + 1) + 0.007 * sin(11 * a) + 0.02 * (1 - swell(a)) }
    static func rOut(_ a: CGFloat) -> CGFloat { 1.06 + 0.065 * swell(a) + 0.012 * sin(7 * a + 2) + 0.007 * sin(13 * a + 0.5) }

    static func bandPath(inset: CGFloat = 0) -> Path {
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0..<120 {
            let a = CGFloat(i) / 120 * 2 * .pi
            outer.append(CGPoint.polar(rOut(a) - inset, a))
            inner.append(CGPoint.polar(rIn(a) + inset, a))
        }
        var p = smoothPath(outer, closed: true)
        p.addPath(smoothPath(inner.reversed(), closed: true))
        return p
    }

    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var rng = SeededRNG(0x57A2_2026)
        var ops: [DrawOp] = []
        let q = d.quality, boost = 1 + 0.6 * (1 - q), keep = 0.35 + 0.65 * q
        let col = ChartColors.make(s, pal)
        let st = StarStyle.make(s, pal)
        let band = bandPath()

        // 1) 帯
        ops.append(DrawOp(z: 0) { c in
            c.drawLayer { l in
                l.addFilter(.blur(radius: 0.01))
                l.fill(band, with: .radialGradient(Gradient(stops: col.bandStops.map { .init(color: $0.0.c($0.1), location: $0.2 / 1.22) }),
                                                   center: .zero, startRadius: 0, endRadius: 1.22), style: FillStyle(eoFill: true))
            }
        })
        // 帯の内縁の途切れた金線
        ops.append(DrawOp(z: 0.62) { c in
            for (a0, span) in [(CGFloat(200), CGFloat(105)), (CGFloat(330), CGFloat(70)), (CGFloat(52), CGFloat(92))] {
                var pts: [CGPoint] = []
                for i in 0...60 { let a = deg(a0 + span * CGFloat(i) / 60); pts.append(CGPoint.polar(rIn(a) + 0.012, a)) }
                let ws = (0...60).map { i -> CGFloat in let t = CGFloat(i) / 60; return d.w(0.0042 * min(1, min(t, 1 - t) * 8) * boost, minPx: 0.3) }
                drawTaperedStroke(c, points: pts, widths: ws, color: col.orbit, alpha: 0.85)
            }
        })
        // 2) 帯の中の星雲（帯の形で切り抜き）
        struct Wisp { var p: CGPoint; var rx: CGFloat; var ratio: CGFloat; var rot: CGFloat; var color: RGB; var alpha: Double }
        var wisps: [Wisp] = []
        for _ in 0..<Int(30 + 70 * q) {
            let a = deg(rng.range(0, 360))
            let r = (rIn(a) + rOut(a)) / 2 + rng.gauss() * 0.03
            let dark = col.darkLane != nil && rng.chance(0.22)
            let color = dark ? col.darkLane! : rng.pick(col.wisps)
            wisps.append(Wisp(p: CGPoint.polar(r, a), rx: rng.range(0.05, 0.13), ratio: rng.range(0.18, 0.4), rot: a + .pi / 2 + rng.range(-0.4, 0.4),
                              color: color, alpha: Double(dark ? rng.range(0.25, 0.45) : rng.range(0.16, 0.36))))
        }
        ops.append(DrawOp(z: 0.05) { c in
            var cc = c
            cc.clip(to: bandPath(inset: -0.01), style: FillStyle(eoFill: true))
            cc.drawLayer { l in
                l.addFilter(.blur(radius: 0.011))
                for w in wisps {
                    var bc = l
                    bc.translateBy(x: w.p.x, y: w.p.y)
                    bc.rotate(by: .radians(w.rot))
                    bc.scaleBy(x: 1, y: w.ratio)
                    bc.fill(disc(.zero, w.rx), with: .radialGradient(Gradient(colors: [w.color.c(w.alpha), w.color.c(0)]), center: .zero, startRadius: 0, endRadius: w.rx))
                }
            }
        })
        if q > 0.3 {
            for _ in 0..<Int(3 + 7 * q) {
                let start = rng.range(0, 360), span = rng.range(35, 90)
                let off = rng.gauss() * 0.03, amp = rng.range(0.008, 0.018), f = rng.range(3, 7), ph = rng.range(0, 6)
                var pts: [CGPoint] = []
                for i in 0...40 { let a = deg(start + span * CGFloat(i) / 40); pts.append(CGPoint.polar(1.0 + off + amp * sin(f * a + ph), a)) }
                let base = rng.range(0.003, 0.007)
                let ws = (0...40).map { i -> CGFloat in d.w(base * sin(CGFloat.pi * CGFloat(i) / 40), minPx: 0.25) }
                let color = rng.pick(col.streak)
                let alpha = Double(rng.range(0.35, 0.6))
                ops.append(DrawOp(z: 0.1) { c in
                    var cc = c
                    if col.additive { cc.blendMode = .plusLighter }
                    drawTaperedStroke(cc, points: pts, widths: ws, color: color, alpha: alpha)
                })
            }
        }
        // 3) 星屑
        for _ in 0..<Int(40 + 260 * keep * keep) {
            let a = deg(rng.range(0, 360))
            let inside = rng.chance(0.8)
            let r = inside ? rIn(a) + rng.unit() * (rOut(a) - rIn(a)) : min(1.2, max(0.86, 1.0 + rng.gauss() * 0.11))
            let color = rng.pick(col.dust)
            let rr = rng.range(0.0022, 0.0055) * boost
            let alpha = Double(rng.range(0.45, 1)) * (col.additive ? 1 : 0.75)
            let p = CGPoint.polar(r, a)
            ops.append(DrawOp(z: 0.5) { c in
                var cc = c
                if col.additive { cc.blendMode = .plusLighter }
                cc.fill(disc(p, d.w(rr, minPx: 0.55)), with: .color(color.c(alpha)))
            })
        }
        // 4) 軌道
        let orbitW = d.w(0.0062 * boost, minPx: q < 0.4 ? 1.0 : 0.85)
        ops.append(DrawOp(z: 0.6) { c in
            var cc = c
            cc.rotate(by: .radians(deg(18)))
            cc.stroke(Path(ellipseIn: CGRect(x: -1.07, y: -0.985, width: 2.14, height: 1.97)), with: .color(col.orbit.c(0.88)), lineWidth: orbitW)
            var c2 = c
            c2.rotate(by: .radians(deg(-40)))
            c2.stroke(Path(ellipseIn: CGRect(x: -1.035, y: -1.12, width: 2.07, height: 2.24)), with: .color(col.orbit2.c(q < 0.4 ? 0.75 : 0.6)), lineWidth: orbitW * 0.7)
        })
        if q > 0.3 {
            ops.append(DrawOp(z: 0.61) { c in
                c.stroke(disc(.zero, 0.935), with: .color(col.orbit2.c(0.7)), style: StrokeStyle(lineWidth: d.w(0.006, minPx: 0.9), lineCap: .round, dash: [0, 0.024]))
            })
        }
        if q > 0.45 {
            ops.append(DrawOp(z: 0.62) { c in
                var cc = c
                cc.rotate(by: .radians(deg(-8)))
                var arc = Path()
                arc.addArc(center: .zero, radius: 1.175, startAngle: .degrees(160), endAngle: .degrees(320), clockwise: false)
                cc.stroke(arc, with: .color(col.orbit.c(0.62)), lineWidth: orbitW * 0.75)
                var ticks = Path()
                for k in stride(from: 160.0, through: 320.0, by: 5.0) {
                    let a = deg(CGFloat(k))
                    ticks.move(to: CGPoint.polar(1.175, a))
                    ticks.addLine(to: CGPoint.polar(1.175 - (Int(k) % 30 == 0 ? 0.034 : 0.016), a))
                }
                cc.stroke(ticks, with: .color(col.orbit.c(0.62)), lineWidth: orbitW * 0.65)
                var chords = Path()
                for (a1, a2, r1, r2) in [(CGFloat(232), CGFloat(262), CGFloat(1.12), CGFloat(0.92)), (338, 8, 0.93, 1.12), (96, 128, 1.11, 0.93)] {
                    chords.move(to: CGPoint.polar(r1, deg(a1)))
                    chords.addLine(to: CGPoint.polar(r2, deg(a2)))
                }
                c.stroke(chords, with: .color(col.orbit.c(0.5)), lineWidth: orbitW * 0.6)
            })
        }
        // 5) 星座
        let placements: [(Constellation, CGFloat, CGFloat, Bool, Int?)] = [
            (.dipper, 196, 54, false, 2), (.cassiopeia, 268, 40, false, nil), (.swan, 320, 40, false, nil),
            (.kite, 24, 40, false, 2), (.arc, 80, 44, false, nil), (.cassiopeia, 132, 34, true, nil),
        ]
        for (i, pl) in placements.enumerated() {
            let (con, centerDeg, spanDeg, dashed, circled) = pl
            let xs = con.points.map(\.x), ys = con.points.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let map: (CGPoint) -> CGPoint = { p in
                let u = (p.x - minX) / max(0.001, maxX - minX) - 0.5
                let v = (p.y - minY) / max(0.001, maxY - minY) - 0.5
                return CGPoint.polar(0.995 + v * 0.17, deg(centerDeg + u * spanDeg))
            }
            var style = st
            if q < 0.3 { style.lineAlpha *= 0.85 }
            ops.append(DrawOp(z: 1 + Double(i) * 0.01) { c in
                Celestial.constellation(c, con, map: map, starSize: 0.036 * pow(boost, 0.7), lineWidth: 0.0048 * boost, style: style, d: d,
                                        dashed: dashed && q > 0.3, circledIndex: q > 0.45 ? circled : nil, spin: deg(CGFloat(i) * 7))
            })
        }
        // 6) 主役の一等星
        for (i, f) in [(CGFloat(304), CGFloat(1.1), CGFloat(1.0)), (146, 1.09, 0.9), (52, 1.12, 0.8), (226, 0.97, 0.7)].enumerated() {
            if CGFloat(i) >= 2 + 2 * keep { break }
            let p = CGPoint.polar(f.1, deg(f.0))
            let sz = 0.05 * f.2 * pow(boost, 0.8)
            ops.append(DrawOp(z: 2 + Double(i) * 0.01) { c in
                Celestial.star(c, at: p, magnitude: 0, size: sz, tint: st.tints[0], style: st, d: d, spin: deg(CGFloat(i) * 9))
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let st = StarStyle.make(s, pal)
        let col = ChartColors.make(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x57, airAnchors: [
            (cc.tl, 0.6, s.isDark ? RGB(0x5946B2) : RGB(0xC9DDF6), s.isDark ? 0.22 : 0.4),
            (cc.br, 0.7, s.isDark ? RGB(0x2E2A7A) : RGB(0xDCD2F4), s.isDark ? 0.3 : 0.4),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        // 星屑（周辺ほど多い）
        var rng = SeededRNG(77)
        for _ in 0..<(cc.tiny ? 50 : 300) {
            let p = CGPoint(x: cc.rect.minX + rng.unit() * cc.rect.width, y: cc.rect.minY + rng.unit() * cc.rect.height)
            let ex = (p.x - cc.rect.midX) / (cc.rect.width / 2), ey = (p.y - cc.rect.midY) / (cc.rect.height / 2)
            let edge = max(abs(ex), abs(ey))
            guard rng.unit() < edge * edge + 0.06, !cc.textZone.contains(p) else { continue }
            var c = inner
            if col.additive { c.blendMode = .plusLighter }
            c.fill(disc(p, d.w(rng.range(0.25, 0.7) * k, minPx: 0.6)), with: .color(rng.pick(col.dust).c(Double(rng.range(0.4, 0.9)))))
        }
        // 角の天文図：同心の軌道＋目盛り
        let corners: [(CGPoint, CGFloat, Double)] = [(cc.tl, deg(45), 0.75), (cc.tr, deg(135), 0.45), (cc.bl, deg(-45), 0.55), (cc.br, deg(-135), 0.9)]
        for (ci, cor) in corners.enumerated() {
            let (p, dirA, strength) = cor
            let radii: [CGFloat] = ci == 3 ? [58, 82, 108] : [46, 66, 88]
            for (ri, r0) in radii.enumerated() {
                let r = r0 * k
                var arc = Path()
                arc.addArc(center: p, radius: r, startAngle: .radians(dirA - deg(52)), endAngle: .radians(dirA + deg(52)), clockwise: false)
                inner.stroke(arc, with: .color((ri == 1 ? col.orbit : col.orbit2).c((ri == 1 ? 0.6 : 0.45) * strength)),
                             style: StrokeStyle(lineWidth: d.w((ri == 1 ? 0.55 : 0.75) * k, minPx: 0.6), lineCap: .round, dash: ri == 1 ? [] : [0, 2.6 * k]))
                if ri == 1 && !cc.tiny {
                    var ticks = Path()
                    for tdeg in stride(from: -48.0, through: 48.0, by: 6.0) {
                        let a = dirA + deg(CGFloat(tdeg))
                        ticks.move(to: p + CGPoint.polar(r, a))
                        ticks.addLine(to: p + CGPoint.polar(r + (Int(tdeg) % 24 == 0 ? 3.4 : 1.6) * k, a))
                    }
                    inner.stroke(ticks, with: .color(col.orbit.c(0.55 * strength)), lineWidth: d.w(0.45 * k, minPx: 0.4))
                }
            }
        }
        // 星座（フレームと同じ形）。本文の背後には置かない
        func place(_ con: Constellation, origin: CGPoint, scale sc: CGFloat, rotation: CGFloat, alpha: Double, circled: Int?) {
            var c = ctx
            c.opacity = alpha
            let map: (CGPoint) -> CGPoint = { q in origin + q.rotated(rotation) * (sc * k) }
            Celestial.constellation(c, con, map: map, starSize: (cc.tiny ? 4.8 : 3.8) * k, lineWidth: 0.6 * k, style: st, d: d, circledIndex: cc.tiny ? nil : circled)
        }
        place(.dipper, origin: CGPoint(x: cc.rect.minX + 22 * k, y: cc.rect.minY + 24 * k), scale: 17, rotation: deg(18), alpha: 0.95, circled: 2)
        place(.cassiopeia, origin: CGPoint(x: cc.rect.maxX - 50 * k, y: cc.rect.minY + 13 * k), scale: 11, rotation: deg(30), alpha: 0.62, circled: nil)
        place(.swan, origin: CGPoint(x: cc.rect.minX + 9 * k, y: cc.rect.maxY - 54 * k), scale: 13, rotation: deg(-28), alpha: 0.8, circled: nil)
        place(.kite, origin: CGPoint(x: cc.rect.maxX - 92 * k, y: cc.rect.maxY - 54 * k), scale: 22, rotation: deg(-8), alpha: 1, circled: 2)
        if !cc.tiny {
            place(.arc, origin: CGPoint(x: cc.rect.maxX - 34 * k, y: cc.rect.maxY - 108 * k), scale: 11, rotation: deg(70), alpha: 0.7, circled: nil)
            place(.cassiopeia, origin: CGPoint(x: cc.rect.midX - 40 * k, y: cc.rect.maxY - 22 * k), scale: 9, rotation: deg(-6), alpha: 0.45, circled: nil)
        }
        // 光芒
        var r2 = SeededRNG(301)
        for _ in 0..<(cc.tiny ? 4 : 10) {
            let edgeBias = r2.chance(0.5)
            let x = edgeBias ? (r2.chance(0.5) ? cc.rect.minX + r2.range(14, 70) * k : cc.rect.maxX - r2.range(14, 70) * k) : cc.rect.minX + r2.unit() * cc.rect.width
            let y = edgeBias ? cc.rect.minY + r2.unit() * cc.rect.height : (r2.chance(0.5) ? cc.rect.minY + r2.range(14, 40) * k : cc.rect.maxY - r2.range(14, 40) * k)
            let p = CGPoint(x: x, y: y)
            if cc.textZone.contains(p) { continue }
            Celestial.star(ctx, at: p, magnitude: r2.chance(0.3) ? 0 : 1, size: r2.range(2.2, 3.6) * k, tint: st.tints[0], style: st, d: d)
        }
        CardBase.drawRule(ctx, cc, gap: 34) { c, p, flip in
            var f = c
            f.translateBy(x: p.x, y: p.y)
            f.fill(Celestial.sparklePath(long: 6.5 * k, waist: 0.8 * k), with: .color((s.isDark ? RGB(0xE9E2FF) : pal.line(s)).c()))
            f.stroke(disc(.zero, 3.2 * k), with: .color(col.orbit.c(0.8)), lineWidth: d.w(0.5 * k, minPx: 0.5))
            for sgn in [CGFloat(-1), 1] {
                for j in 0..<3 {
                    f.fill(disc(CGPoint(x: sgn * (11 + CGFloat(j) * 4) * k, y: 0), (j == 0 ? 1.1 : 0.75) * k), with: .color(pal.line(s).c(0.85)))
                }
            }
        }
    }
}

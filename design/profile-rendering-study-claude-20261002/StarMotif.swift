// 星図線：フレームとカード。
import SwiftUI

enum StarMotifPalette {
    static let smokeIndigo = RGB(0x25265F)
    static let smokeTeal = RGB(0x1C4A62)
    static let smokeViolet = RGB(0x5946B2)
    static let smokeOrchid = RGB(0x9468D0)
    static let smokeAqua = RGB(0x3F93BC)
}

// MARK: - Star frame

enum StarFrameBuilder {
    /// 帯の太さ・濃さのうねり（0.1…1）。均一なリングにしない。
    static func swell(_ a: CGFloat) -> CGFloat { 0.5 + 0.5 * sin(a * 3 + 0.7) * cos(a * 2 - 0.4) }
    static func rIn(_ a: CGFloat) -> CGFloat { 0.905 + 0.014 * sin(5 * a + 1) + 0.007 * sin(11 * a) + 0.02 * (1 - swell(a)) }
    static func rOut(_ a: CGFloat) -> CGFloat { 1.06 + 0.065 * swell(a) + 0.012 * sin(7 * a + 2) + 0.007 * sin(13 * a + 0.5) }

    /// 夜空の帯（外縁は角度ごとに膨らみ、雲のように不揃い）。
    static func bandPath(inset: CGFloat = 0) -> Path {
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        let n = 120
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            outer.append(CGPoint.polar(rOut(a) - inset, a))
            inner.append(CGPoint.polar(rIn(a) + inset, a))
        }
        var p = smoothPath(outer, closed: true)
        p.addPath(smoothPath(inner.reversed(), closed: true))
        return p
    }

    static func build(detail d: Detail) -> [DrawOp] {
        var rng = SeededRNG(0x57A2_2026)
        var ops: [DrawOp] = []
        let q = d.quality
        let boost = 1 + 0.6 * (1 - q)
        let keep = 0.35 + 0.65 * q
        let band = bandPath()

        // 1) 夜空の帯：アバター側は濃紺（どんなアバター色とも境界が立つ）、外側へ菫の星雲として抜ける
        ops.append(DrawOp(z: 0) { c in
            c.drawLayer { l in
                l.addFilter(.blur(radius: 0.01))
                l.fill(band, with: .radialGradient(Gradient(stops: [
                    .init(color: RGB(0x111236).c(0.0), location: 0.85 / 1.22),
                    .init(color: RGB(0x111236).c(0.9), location: 0.905 / 1.22),
                    .init(color: RGB(0x18194A).c(0.93), location: 0.975 / 1.22),
                    .init(color: RGB(0x2E2A7A).c(0.86), location: 1.04 / 1.22),
                    .init(color: StarMotifPalette.smokeViolet.c(0.5), location: 1.095 / 1.22),
                    .init(color: StarMotifPalette.smokeViolet.c(0.16), location: 1.15 / 1.22),
                    .init(color: StarMotifPalette.smokeViolet.c(0.0), location: 1.0),
                ]), center: .zero, startRadius: 0, endRadius: 1.22), style: FillStyle(eoFill: true))
            }
        })
        // 帯の内縁に沿う、途切れた金の細線（星図の枠線。全周の機械的な輪にはしない）
        ops.append(DrawOp(z: 0.62) { c in
            for (a0, span) in [(CGFloat(200), CGFloat(105)), (CGFloat(330), CGFloat(70)), (CGFloat(52), CGFloat(92))] {
                var pts: [CGPoint] = []
                for i in 0...60 {
                    let a = deg(a0 + span * CGFloat(i) / 60)
                    pts.append(CGPoint.polar(rIn(a) + 0.012, a))
                }
                let ws = (0...60).map { i -> CGFloat in
                    let t = CGFloat(i) / 60
                    return d.w(0.0042 * min(1, min(t, 1 - t) * 8) * boost, minPx: 0.3)
                }
                Botanical.drawTaperedStroke(c, points: pts, widths: ws, color: StarPalette.gold, alpha: 0.85)
            }
        })

        // 2) 帯の中の星雲：明るい菫・青緑・薄紅の筋雲と暗いダストレーン（帯の形でクリップ）
        struct Wisp { var p: CGPoint; var rx: CGFloat; var ratio: CGFloat; var rot: CGFloat; var color: RGB; var alpha: Double; var dark: Bool }
        var wisps: [Wisp] = []
        for _ in 0..<Int(30 + 70 * q) {
            let a = deg(rng.range(0, 360))
            let r = (rIn(a) + rOut(a)) / 2 + rng.gauss() * 0.03
            let dark = rng.chance(0.22)
            let roll = rng.unit()
            let color = dark ? RGB(0x0E0E2E) : (roll < 0.4 ? StarMotifPalette.smokeOrchid : roll < 0.7 ? StarPalette.periwinkle : roll < 0.88 ? StarMotifPalette.smokeAqua : RGB(0xE3A6D8))
            wisps.append(Wisp(p: CGPoint.polar(r, a), rx: rng.range(0.05, 0.13), ratio: rng.range(0.18, 0.4), rot: a + .pi / 2 + rng.range(-0.4, 0.4),
                              color: color, alpha: Double(dark ? rng.range(0.25, 0.45) : rng.range(0.14, 0.34)), dark: dark))
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
                    bc.fill(Celestial.disc(.zero, w.rx), with: .radialGradient(Gradient(colors: [w.color.c(w.alpha), w.color.c(0)]), center: .zero, startRadius: 0, endRadius: w.rx))
                }
            }
        })
        // 光の細い筋（加算）
        if q > 0.3 {
            for _ in 0..<Int(3 + 7 * q) {
                let start = rng.range(0, 360), span = rng.range(35, 90)
                let off = rng.gauss() * 0.03, amp = rng.range(0.008, 0.018), f = rng.range(3, 7), ph = rng.range(0, 6)
                let steps = 40
                var pts: [CGPoint] = []
                for i in 0...steps {
                    let a = deg(start + span * CGFloat(i) / CGFloat(steps))
                    pts.append(CGPoint.polar(1.0 + off + amp * sin(f * a + ph), a))
                }
                let base = rng.range(0.003, 0.007)
                let ws = (0...steps).map { i -> CGFloat in d.w(base * sin(.pi * CGFloat(i) / CGFloat(steps)), minPx: 0.25) }
                let col = rng.pick([StarPalette.periwinkle, RGB(0xC9B8F6), StarPalette.cyan])
                let alpha = Double(rng.range(0.35, 0.6))
                ops.append(DrawOp(z: 0.1) { c in
                    var cc = c
                    cc.blendMode = .plusLighter
                    Botanical.drawTaperedStroke(cc, points: pts, widths: ws, color: col, alpha: alpha)
                })
            }
        }

        // 3) 星屑：帯の中に密、外へ行くほど疎（加算）
        let dust = Int(40 + 260 * keep * keep)
        for _ in 0..<dust {
            let a = deg(rng.range(0, 360))
            let inside = rng.chance(0.8)
            let r = inside ? rIn(a) + rng.unit() * (rOut(a) - rIn(a)) : min(1.2, max(0.86, 1.0 + rng.gauss() * 0.11))
            let roll = rng.unit()
            let col = roll < 0.55 ? StarPalette.cream : (roll < 0.82 ? StarPalette.gold : StarPalette.cyan)
            let rr = rng.range(0.0022, 0.0055) * boost
            let alpha = Double(rng.range(0.45, 1))
            let p = CGPoint.polar(r, a)
            ops.append(DrawOp(z: 0.5) { c in
                var cc = c
                cc.blendMode = .plusLighter
                cc.fill(Celestial.disc(p, d.w(rr, minPx: 0.55)), with: .color(col.c(alpha)))
            })
        }

        // 4) 軌道：帯を出入りする傾いた楕円（金）・点線の内円・目盛りの外弧・天文図の弦
        let orbitW = d.w(0.0062 * boost, minPx: q < 0.4 ? 1.0 : 0.85)
        ops.append(DrawOp(z: 0.6) { c in
            var cc = c
            cc.rotate(by: .radians(deg(18)))
            cc.stroke(Path(ellipseIn: CGRect(x: -1.07, y: -0.985, width: 2.14, height: 1.97)), with: .color(StarPalette.gold.c(0.88)), lineWidth: orbitW)
            var c2 = c
            c2.rotate(by: .radians(deg(-40)))
            c2.stroke(Path(ellipseIn: CGRect(x: -1.035, y: -1.12, width: 2.07, height: 2.24)), with: .color(StarPalette.cream.c(q < 0.4 ? 0.75 : 0.6)), lineWidth: orbitW * 0.7)
        })
        if q > 0.3 {
            ops.append(DrawOp(z: 0.61) { c in
                let dot = d.w(0.006, minPx: 0.9)
                c.stroke(Celestial.disc(.zero, 0.935), with: .color(StarPalette.cream.c(0.7)), style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0, 0.024]))
            })
        }
        if q > 0.45 {
            ops.append(DrawOp(z: 0.62) { c in
                var cc = c
                cc.rotate(by: .radians(deg(-8)))
                var arc = Path()
                arc.addArc(center: .zero, radius: 1.175, startAngle: .degrees(160), endAngle: .degrees(320), clockwise: false)
                cc.stroke(arc, with: .color(StarPalette.gold.c(0.62)), lineWidth: orbitW * 0.75)
                var ticks = Path()
                for k in stride(from: 160.0, through: 320.0, by: 5.0) {
                    let a = deg(CGFloat(k))
                    let long = Int(k) % 30 == 0
                    ticks.move(to: CGPoint.polar(1.175, a))
                    ticks.addLine(to: CGPoint.polar(1.175 - (long ? 0.034 : 0.016), a))
                }
                cc.stroke(ticks, with: .color(StarPalette.gold.c(0.62)), lineWidth: orbitW * 0.65)
                var chords = Path()
                for (a1, a2, r1, r2) in [(CGFloat(232), CGFloat(262), CGFloat(1.12), CGFloat(0.92)), (338, 8, 0.93, 1.12), (96, 128, 1.11, 0.93)] {
                    chords.move(to: CGPoint.polar(r1, deg(a1)))
                    chords.addLine(to: CGPoint.polar(r2, deg(a2)))
                }
                c.stroke(chords, with: .color(StarPalette.gold.c(0.5)), lineWidth: orbitW * 0.6)
            })
        }

        // 5) 星座：カードと同じ星座形を帯に巻き付ける
        let placements: [(Constellation, CGFloat, CGFloat, Bool, Int?)] = [
            (.dipper, 196, 54, false, 2), (.cassiopeia, 268, 40, false, nil), (.swan, 320, 40, false, nil),
            (.kite, 24, 40, false, 2), (.arc, 80, 44, false, nil), (.cassiopeia, 132, 34, true, nil),
        ]
        let tints = [StarPalette.gold, StarPalette.cream, StarPalette.cyan, StarPalette.gold]
        for (i, pl) in placements.enumerated() {
            let (con, centerDeg, spanDeg, dashed, circled) = pl
            let xs = con.points.map(\.x), ys = con.points.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let map: (CGPoint) -> CGPoint = { p in
                let u = (p.x - minX) / max(0.001, maxX - minX) - 0.5
                let v = (p.y - minY) / max(0.001, maxY - minY) - 0.5
                return CGPoint.polar(0.995 + v * 0.17, deg(centerDeg + u * spanDeg))
            }
            ops.append(DrawOp(z: 1 + Double(i) * 0.01) { c in
                Celestial.drawConstellation(c, con, map: map, starSize: 0.036 * pow(boost, 0.7), lineWidth: 0.0048 * boost, detail: d,
                                            tints: tints, lineAlpha: q < 0.3 ? 0.7 : 0.85, dashed: dashed && q > 0.3,
                                            circledIndex: q > 0.45 ? circled : nil, spin: deg(CGFloat(i) * 7))
            })
        }

        // 6) 主役の一等星：帯の縁から光芒がはみ出し、縮小してもシルエットに変化を残す
        for (i, f) in [(CGFloat(304), CGFloat(1.1), CGFloat(1.0)), (146, 1.09, 0.9), (52, 1.12, 0.8), (226, 0.97, 0.7)].enumerated() {
            if CGFloat(i) >= 2 + 2 * keep { break }
            let p = CGPoint.polar(f.1, deg(f.0))
            let sz = 0.05 * f.2 * pow(boost, 0.8)
            ops.append(DrawOp(z: 2 + Double(i) * 0.01) { c in
                Celestial.drawStar(c, at: p, magnitude: 0, size: sz, tint: StarPalette.gold, detail: d, spin: deg(CGFloat(i) * 9))
            })
        }

        // 7) 惑星マーカー（輪付きの小天体）
        if q > 0.5 {
            for (ad, rr) in [(CGFloat(162), CGFloat(1.11)), (CGFloat(10), CGFloat(0.93))] {
                let p = CGPoint.polar(rr, deg(ad))
                ops.append(DrawOp(z: 1.5) { c in
                    c.fill(Celestial.disc(p, 0.011), with: .radialGradient(Gradient(colors: [.white, StarPalette.cream.c(), StarPalette.gold.c()]), center: p, startRadius: 0, endRadius: 0.012))
                    var cc = c
                    cc.translateBy(x: p.x, y: p.y)
                    cc.rotate(by: .radians(deg(-25)))
                    cc.stroke(Path(ellipseIn: CGRect(x: -0.032, y: -0.009, width: 0.064, height: 0.018)), with: .color(StarPalette.cyan.c(0.85)), lineWidth: d.w(0.003, minPx: 0.4))
                })
            }
        }
        return ops
    }
}

// MARK: - Star card

enum StarCard {
    static let border = RGB(0xE9E2FF)

    static func draw(_ ctx: GraphicsContext, size: CGSize, scale: CGFloat, bleed: CGFloat) {
        let k = CardGeometry.k(size)
        let (rect, radius) = CardGeometry.panel(size)
        let shape = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let d = Detail(pxPerUnit: scale)
        let tiny = size.width < 160

        ctx.fill(Path(roundedRect: rect.insetBy(dx: -1.4 * k, dy: -1.4 * k), cornerRadius: radius + 1.4 * k, style: .continuous), with: .color(RGB(0xCFC6F7).c(0.92)))
        // 本文列の下は明るく保つ（本体の差分合成文字は中間調の背景でコントラストが落ちるため）
        ctx.fill(shape, with: .radialGradient(Gradient(stops: [
            .init(color: RGB(0xE6DDF9).c(), location: 0),
            .init(color: RGB(0xD0CBF6).c(), location: 0.42),
            .init(color: RGB(0xAAAEEC).c(), location: 0.78),
            .init(color: RGB(0x8C93E0).c(), location: 1),
        ]), center: CGPoint(x: rect.midX + 34 * k, y: rect.midY - 4 * k), startRadius: 0, endRadius: rect.width * 0.66))
        var inner = ctx
        inner.clip(to: shape)
        CardGeometry.wash(inner, in: rect, colors: [RGB(0xC9B0F2), RGB(0xEBCBEE), RGB(0xAFBEF4), RGB(0x9F98E4)],
                          count: tiny ? 20 : 54, k: k, alpha: 0.08...0.18, seed: 93, avoidCenter: true, driedEdges: false, blur: 9)

        // フレームと同じ「星雲の煙」を角にだけ薄く流す（カードとフレームの素材を揃える）
        var rng = SeededRNG(0xCA2D)
        inner.drawLayer { l in
            l.addFilter(.blur(radius: 7 * k))
            let anchors: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: rect.minX, y: rect.minY), deg(45), 0.8), (CGPoint(x: rect.maxX, y: rect.maxY), deg(-135), 1.0),
                (CGPoint(x: rect.maxX, y: rect.minY), deg(135), 0.45), (CGPoint(x: rect.minX, y: rect.maxY), deg(-45), 0.6),
            ]
            for (p, dirA, strength) in anchors {
                for _ in 0..<(tiny ? 6 : 16) {
                    let a = dirA + rng.range(-0.75, 0.75)
                    let r = rng.range(55, 105) * k
                    let c = p + CGPoint.polar(r, a)
                    let rx = rng.range(26, 50) * k
                    var bc = l
                    bc.translateBy(x: c.x, y: c.y)
                    bc.rotate(by: .radians(a + .pi / 2 + rng.range(-0.3, 0.3)))
                    bc.scaleBy(x: 1, y: rng.range(0.25, 0.45))
                    let col = rng.pick([StarMotifPalette.smokeViolet, StarMotifPalette.smokeIndigo, StarMotifPalette.smokeOrchid, StarMotifPalette.smokeAqua])
                    let alpha = Double(rng.range(0.08, 0.18)) * Double(strength)
                    bc.fill(Celestial.disc(.zero, rx), with: .radialGradient(Gradient(colors: [col.c(alpha), col.c(0)]), center: .zero, startRadius: 0, endRadius: rx))
                }
            }
        }
        if !tiny { CardGeometry.grain(inner, in: rect, count: Int(rect.width * rect.height / 20), dark: RGB(0x3A3486), light: RGB(0xFFFFFF), seed: 5, scale: scale) }
        // 微光の星屑（周辺ほど多い）
        let dust = tiny ? 40 : 260
        for _ in 0..<dust {
            let p = CGPoint(x: rect.minX + rng.unit() * rect.width, y: rect.minY + rng.unit() * rect.height)
            let cx = (p.x - rect.midX) / (rect.width / 2), cy = (p.y - rect.midY) / (rect.height / 2)
            let edge = max(abs(cx), abs(cy))
            guard rng.unit() < edge * edge + 0.08 else { continue }
            let r = d.w(rng.range(0.25, 0.7) * k, minPx: 0.6)
            inner.fill(Celestial.disc(p, r), with: .color((rng.chance(0.7) ? StarPalette.cream : StarPalette.cyan).c(Double(rng.range(0.45, 0.95)))))
        }
        inner.stroke(shape, with: .color(RGB(0x6D6CC8).c(0.18)), lineWidth: 16 * k)

        // 角の天文図：同心の破線軌道＋目盛り（フレームの目盛り弧と同じ語彙）
        let corners: [(CGPoint, CGFloat, Double)] = [
            (CGPoint(x: rect.minX, y: rect.minY), deg(45), 0.75), (CGPoint(x: rect.maxX, y: rect.minY), deg(135), 0.5),
            (CGPoint(x: rect.minX, y: rect.maxY), deg(-45), 0.6), (CGPoint(x: rect.maxX, y: rect.maxY), deg(-135), 0.85),
        ]
        for (ci, cor) in corners.enumerated() {
            let (p, dirA, strength) = cor
            let radii: [CGFloat] = ci == 3 ? [58, 82, 108] : [46, 66, 88]
            for (ri, r0) in radii.enumerated() {
                let r = r0 * k
                var arc = Path()
                arc.addArc(center: p, radius: r, startAngle: .radians(dirA - deg(52)), endAngle: .radians(dirA + deg(52)), clockwise: false)
                inner.stroke(arc, with: .color((ri == 1 ? StarPalette.gold : StarPalette.cream).c((ri == 1 ? 0.6 : 0.5) * strength)),
                             style: StrokeStyle(lineWidth: d.w((ri == 1 ? 0.55 : 0.75) * k, minPx: 0.6), lineCap: .round, dash: ri == 1 ? [] : [0, 2.6 * k]))
                if ri == 1 && !tiny {
                    var ticks = Path()
                    for tdeg in stride(from: -48.0, through: 48.0, by: 6.0) {
                        let a = dirA + deg(CGFloat(tdeg))
                        ticks.move(to: p + CGPoint.polar(r, a))
                        ticks.addLine(to: p + CGPoint.polar(r + (Int(tdeg) % 24 == 0 ? 3.4 : 1.6) * k, a))
                    }
                    inner.stroke(ticks, with: .color(StarPalette.gold.c(0.55 * strength)), lineWidth: d.w(0.45 * k, minPx: 0.4))
                }
            }
        }

        // 二重罫と頂部・底部の星飾り
        let line1 = rect.insetBy(dx: 5 * k, dy: 5 * k)
        let line2 = rect.insetBy(dx: 7.4 * k, dy: 7.4 * k)
        var lines = ctx
        let gapW = 34 * k
        var gaps = Path(rect.insetBy(dx: -20, dy: -20))
        gaps.addRect(CGRect(x: rect.midX - gapW / 2, y: rect.minY - 4, width: gapW, height: 12 * k + 4))
        gaps.addRect(CGRect(x: rect.midX - gapW / 2, y: rect.maxY - 12 * k, width: gapW, height: 12 * k + 4))
        lines.clip(to: gaps, style: FillStyle(eoFill: true))
        lines.stroke(Path(roundedRect: line1, cornerRadius: max(2, radius - 4 * k), style: .continuous), with: .color(border.c(0.95)), lineWidth: d.w(1.3 * k, minPx: 0.8))
        lines.stroke(Path(roundedRect: line2, cornerRadius: max(2, radius - 6.5 * k), style: .continuous), with: .color(border.c(0.55)), lineWidth: d.w(0.55 * k, minPx: 0.5))
        for top in [true, false] {
            let y = top ? line1.minY + 1 * k : line1.maxY - 1 * k
            var c = ctx
            c.translateBy(x: rect.midX, y: y)
            c.fill(Celestial.sparklePath(long: 6.5 * k, waist: 0.8 * k), with: .color(border.c()))
            c.stroke(Celestial.disc(.zero, 3.2 * k), with: .color(StarPalette.gold.c(0.8)), lineWidth: d.w(0.5 * k, minPx: 0.5))
            for s in [CGFloat(-1), 1] {
                for j in 0..<3 {
                    let q = CGPoint(x: s * (11 + CGFloat(j) * 4) * k, y: 0)
                    c.fill(Celestial.disc(q, (j == 0 ? 1.1 : 0.75) * k), with: .color(border.c(0.9)))
                }
            }
        }

        // 星座（フレームと同じ形・同じ星の描き方）。右上は名前の背後なので控えめに
        let tints = [StarPalette.gold, StarPalette.cream, StarPalette.cyan, StarPalette.gold, StarPalette.cyan]
        func place(_ con: Constellation, origin: CGPoint, scale s: CGFloat, rotation: CGFloat, alpha: Double, circled: Int?) {
            var c = ctx
            c.opacity = alpha
            let map: (CGPoint) -> CGPoint = { q in
                let r = CGPoint(x: q.x * cos(rotation) - q.y * sin(rotation), y: q.x * sin(rotation) + q.y * cos(rotation))
                return origin + r * (s * k)
            }
            Celestial.drawConstellation(c, con, map: map, starSize: (tiny ? 4.8 : 3.8) * k, lineWidth: 0.6 * k, detail: d, tints: tints,
                                        lineColor: RGB(0xFFF6E2), lineAlpha: 0.85, circledIndex: tiny ? nil : circled, spin: 0, additive: false)
        }
        place(.dipper, origin: CGPoint(x: rect.minX + 22 * k, y: rect.minY + 24 * k), scale: 17, rotation: deg(18), alpha: 0.95, circled: 2)
        place(.cassiopeia, origin: CGPoint(x: rect.maxX - 50 * k, y: rect.minY + 13 * k), scale: 11, rotation: deg(30), alpha: 0.62, circled: nil)
        place(.swan, origin: CGPoint(x: rect.minX + 9 * k, y: rect.maxY - 54 * k), scale: 13, rotation: deg(-28), alpha: 0.8, circled: nil)
        place(.kite, origin: CGPoint(x: rect.maxX - 92 * k, y: rect.maxY - 54 * k), scale: 22, rotation: deg(-8), alpha: 1, circled: 2)
        if !tiny {
            place(.arc, origin: CGPoint(x: rect.maxX - 34 * k, y: rect.maxY - 108 * k), scale: 11, rotation: deg(70), alpha: 0.7, circled: nil)
            // 縁に沿う淡い小星座（原画の「周囲いっぱいの星図」の細かさを、文字面を避けて足す）
            place(.cassiopeia, origin: CGPoint(x: rect.midX - 40 * k, y: rect.maxY - 22 * k), scale: 9, rotation: deg(-6), alpha: 0.45, circled: nil)
            place(.kite, origin: CGPoint(x: rect.minX + 14 * k, y: rect.midY - 26 * k), scale: 8, rotation: deg(80), alpha: 0.4, circled: nil)
            place(.arc, origin: CGPoint(x: rect.midX + 22 * k, y: rect.minY + 12 * k), scale: 8, rotation: deg(4), alpha: 0.4, circled: nil)
        }
        // 散在する光芒（細く小さく）
        var r2 = SeededRNG(301)
        for _ in 0..<(tiny ? 4 : 12) {
            let edgeBias = r2.chance(0.5)
            let x = edgeBias ? (r2.chance(0.5) ? rect.minX + r2.range(14, 70) * k : rect.maxX - r2.range(14, 70) * k) : rect.minX + r2.unit() * rect.width
            let y = edgeBias ? rect.minY + r2.unit() * rect.height : (r2.chance(0.5) ? rect.minY + r2.range(14, 40) * k : rect.maxY - r2.range(14, 40) * k)
            var c = ctx
            c.translateBy(x: x, y: y)
            let s = r2.range(1.8, 3.8) * k * (tiny ? 1.3 : 1)
            c.fill(Celestial.sparklePath(long: s, waist: d.w(s * 0.12, minPx: 0.35)), with: .color(StarPalette.cream.c(0.92)))
            c.fill(Celestial.disc(.zero, d.w(s * 0.14, minPx: 0.5)), with: .color(.white))
        }
    }
}

// 空気の部品と「雲幕」「霧面」「極光線」。
import SwiftUI

enum Air {
    // MARK: 雲

    struct Lobe { var c: CGPoint; var r: CGFloat; var back: Bool }

    /// 積雲の塊：房の和集合を陰の色で塗り、上へずらして縮めた房を重ねて中間調→光の当たる頂を作る（輪郭線は描かない）
    static func cloud(_ ctx: GraphicsContext, lobes: [Lobe], up: CGPoint, s: DecoScheme, pal: ItemPalette, d: Detail, soft: CGFloat = 0) {
        let lit = s.isDark ? RGB(0xF2F6FF) : RGB.white
        let mid = s.isDark ? pal.primary.mix(RGB(0x8C93E8), 0.3) : pal.primary.mix(.white, 0.3)
        let under = s.isDark ? pal.secondary.mix(RGB(0x55488F), 0.45) : pal.secondary.mix(pal.primary, 0.25)
        if !s.isDark {
            // 曙：明るい地に溶けないよう、雲の下に空色の柔らかい影を落とす
            var shadow = Path()
            for l in lobes { shadow.addPath(disc(l.c - up * (l.r * 0.25), l.r)) }
            ctx.drawLayer { L in
                L.addFilter(.blur(radius: (lobes.map(\.r).max() ?? 0.05) * 0.35))
                L.fill(shadow, with: .color(pal.primary.withLightness(0.55).c(0.35)))
            }
        }
        for back in [true, false] {
            let group = lobes.filter { $0.back == back }
            guard !group.isEmpty else { continue }
            var union = Path()
            for l in group { union.addPath(disc(l.c, l.r)) }
            ctx.drawLayer { L in
                if soft > 0 { L.addFilter(.blur(radius: soft)) }
                L.opacity = back ? 0.6 : 1
                L.fill(union, with: .color(under.c(0.95)))
                var inside = L
                inside.clip(to: union)
                var midP = Path(), litP = Path(), hiP = Path()
                for l in group {
                    midP.addPath(disc(l.c + up * (l.r * 0.2), l.r * 0.9))
                    litP.addPath(disc(l.c + up * (l.r * 0.42), l.r * 0.7))
                    hiP.addPath(disc(l.c + up * (l.r * 0.55) + up.perpendicular * (l.r * 0.15), l.r * 0.32))
                }
                inside.fill(midP, with: .color(mid.c(0.95)))
                inside.fill(litP, with: .color(lit.mix(mid, 0.25).c(0.95)))
                inside.fill(hiP, with: .color(lit.c(s.isDark ? 0.7 : 0.9)))
            }
        }
    }

    /// 雲の房を、ある基線に沿って大きさを揃えずに並べる
    static func cloudLobes(along base: (CGFloat) -> CGPoint, up: (CGFloat) -> CGPoint, count: Int, size: CGFloat, height: CGFloat, rng: inout SeededRNG) -> [Lobe] {
        var lobes: [Lobe] = []
        for i in 0..<count {
            let t = (CGFloat(i) + rng.range(-0.3, 0.3)) / CGFloat(max(1, count - 1))
            let bell = sin(.pi * clamp01(t))
            let r = size * (0.45 + 0.7 * bell) * rng.range(0.8, 1.15)
            let lift = height * bell * rng.range(0.4, 1.0)
            let p = base(clamp01(t)) + up(clamp01(t)) * (lift + r * 0.35)
            lobes.append(Lobe(c: p, r: r, back: rng.chance(0.35)))
        }
        return lobes
    }

    // MARK: 霧・煙

    /// 透ける帯（両端が消える）。curl>0 で先端が渦を巻く
    static func wisp(_ ctx: GraphicsContext, points: [CGPoint], width: CGFloat, color: RGB, alpha: Double, d: Detail) {
        let n = points.count
        let ws = (0..<n).map { i -> CGFloat in
            let t = CGFloat(i) / CGFloat(n - 1)
            return max(d.minWidth(0.3), width * pow(sin(.pi * t), 0.7))
        }
        let path = ribbonPath(points, widths: ws)
        ctx.fill(path, with: .linearGradient(Gradient(stops: [
            .init(color: color.c(0), location: 0), .init(color: color.c(alpha), location: 0.35),
            .init(color: color.c(alpha), location: 0.65), .init(color: color.c(0), location: 1),
        ]), startPoint: points.first!, endPoint: points.last!))
    }

    static func spiralTail(from p: CGPoint, dir: CGFloat, radius: CGFloat, turns: CGFloat, sign: CGFloat, steps: Int = 30) -> [CGPoint] {
        var pts: [CGPoint] = []
        let center = p + CGPoint.polar(radius, dir + sign * .pi / 2)
        let a0 = (p - center).angle
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let r = radius * (1 - 0.75 * t)
            pts.append(center + CGPoint.polar(r, a0 + sign * turns * 2 * .pi * t))
        }
        return pts
    }

    // MARK: オーロラ

    /// 輪に沿う幕：法線方向に立つ細い光の筋を並べ、下端を明るく、上へ消す。幕の高さは波打つ
    static func auroraCurtain(_ ctx: GraphicsContext, base: (CGFloat) -> CGPoint, up: (CGFloat) -> CGPoint, rays: Int, height: (CGFloat) -> CGFloat,
                              s: DecoScheme, pal: ItemPalette, d: Detail, rayWidth: CGFloat) {
        let low = s.isDark ? pal.primary : pal.line(s)
        let highC = s.isDark ? pal.secondary : pal.line2(s)
        let top = s.isDark ? RGB(0xB79CFF) : RGB(0x8E6BD6)
        var c = ctx
        if s.isDark { c.blendMode = .plusLighter }
        for i in 0..<rays {
            let t = CGFloat(i) / CGFloat(rays - 1)
            let p = base(t), u = up(t)
            let h = height(t)
            guard h > 0.0001 else { continue }
            let q = p + u * h
            var ray = Path(); ray.move(to: p); ray.addLine(to: q)
            let a = Double(0.35 + 0.5 * abs(sin(t * 37.0 + 1.3)) * abs(sin(t * 11.0)))
            c.stroke(ray, with: .linearGradient(Gradient(stops: [
                .init(color: low.c(a * (s.isDark ? 0.95 : 0.7)), location: 0),
                .init(color: highC.c(a * 0.55), location: 0.45),
                .init(color: top.c(a * 0.25), location: 0.75),
                .init(color: top.c(0), location: 1),
            ]), startPoint: p, endPoint: q), lineWidth: d.w(rayWidth, minPx: 0.4))
        }
        // 幕の体：下端から上端までの面に、下ほど明るい階調を敷く（筋だけだと縮小で消えるため）
        var topPts: [CGPoint] = [], basePts: [CGPoint] = []
        for i in 0...80 {
            let t = CGFloat(i) / 80
            basePts.append(base(t)); topPts.append(base(t) + up(t) * height(t))
        }
        var curtain = smoothPath(basePts, closed: false)
        for p in topPts.reversed() { curtain.addLine(to: p) }
        curtain.closeSubpath()
        let mid = basePts[40], midTop = topPts[40]
        c.drawLayer { l in
            if s.isDark { l.blendMode = .plusLighter }
            l.addFilter(.blur(radius: rayWidth * 1.5))
            l.fill(curtain, with: .linearGradient(Gradient(stops: [
                .init(color: low.c(s.isDark ? 0.5 : 0.32), location: 0), .init(color: highC.c(s.isDark ? 0.28 : 0.2), location: 0.45),
                .init(color: top.c(s.isDark ? 0.12 : 0.08), location: 0.8), .init(color: top.c(0), location: 1),
            ]), startPoint: mid, endPoint: midTop))
        }
        // 明るい下端
        var edge: [CGPoint] = []
        for i in 0...60 { edge.append(base(CGFloat(i) / 60)) }
        let ws = (0...60).map { i -> CGFloat in d.w(rayWidth * 1.6 * sin(CGFloat.pi * CGFloat(i) / 60), minPx: 0.4) }
        drawTaperedStroke(c, points: edge, widths: ws, color: s.isDark ? low.mix(.white, 0.45) : low, alpha: 0.8)
    }
}

// MARK: - 雲幕

enum CloudMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0xC10D)
        let q = d.quality, boost = d.boost
        // 1) 輪に沿う薄い層雲の筋
        for (a0, span, r0, w) in [(CGFloat(250), CGFloat(110), CGFloat(1.0), CGFloat(0.03)), (CGFloat(70), CGFloat(120), CGFloat(1.01), CGFloat(0.026)),
                                 (CGFloat(290), CGFloat(70), CGFloat(1.08), CGFloat(0.016)), (CGFloat(110), CGFloat(60), CGFloat(1.09), CGFloat(0.014))] {
            var pts: [CGPoint] = []
            for i in 0...50 { let a = deg(a0 + span * CGFloat(i) / 50); pts.append(CGPoint.polar(r0 + 0.01 * sin(a * 5), a)) }
            ops.append(DrawOp(z: 0) { c in
                Air.wisp(c, points: pts, width: w * boost, color: s.isDark ? pal.primary.mix(.white, 0.3) : pal.line(s).mix(.white, 0.25), alpha: s.isDark ? 0.55 : 0.5, d: d)
            })
        }
        ops.append(DrawOp(z: 0.01) { c in
            c.stroke(disc(.zero, 0.985), with: .color((s.isDark ? pal.primary.mix(.white, 0.4) : pal.line(s)).c(0.5)), lineWidth: d.w(0.003, minPx: 0.5))
        })
        // 2) 積雲の塊：対角に輪へ腰掛ける（上＝外向き）
        for (ci, spec) in [(CGFloat(214), CGFloat(70)), (CGFloat(36), CGFloat(58))].enumerated() {
            let (center, span) = spec
            let a0 = deg(center - span / 2), a1 = deg(center + span / 2)
            let base: (CGFloat) -> CGPoint = { t in CGPoint.polar(1.02, a0 + (a1 - a0) * t) }
            let up: (CGFloat) -> CGPoint = { t in CGPoint.polar(1, a0 + (a1 - a0) * t) }
            // はっきりした積雲のシルエット：平らな底＋盛り上がる頂（局所座標：x=接線, y=外向き）
            let template: [(CGFloat, CGFloat, CGFloat, Bool)] = [
                (-0.19, 0.0, 0.055, true), (-0.11, 0.01, 0.07, false), (-0.02, 0.0, 0.075, false), (0.08, 0.005, 0.068, false), (0.17, 0.0, 0.05, true),
                (-0.12, 0.07, 0.06, true), (-0.05, 0.085, 0.085, false), (0.05, 0.09, 0.078, false), (0.12, 0.06, 0.055, false),
                (0.0, 0.15, 0.07, false), (-0.08, 0.13, 0.05, true),
            ]
            let scale = (ci == 0 ? 1.5 : 1.3) * (q < 0.4 ? 1.1 : 1)
            let ac = deg(center)
            let tanV = CGPoint(x: -sin(ac), y: cos(ac)), nrmV = CGPoint(x: cos(ac), y: sin(ac))
            let anchor = CGPoint.polar(1.0, ac)
            var lobes: [Air.Lobe] = []
            for (x, y, r, back) in template where !(q < 0.4 && back) {
                // 輪の曲率に沿わせて少し曲げる
                let local = anchor + tanV * (x * scale) + nrmV * (y * scale - (x * scale) * (x * scale) * 0.5)
                lobes.append(Air.Lobe(c: local, r: r * scale * boost * 0.92, back: back))
            }
            _ = a0; _ = a1
            // 輪の内側に入り込みすぎないよう、房の中心を外へ寄せる
            let clamped = lobes.map { l -> Air.Lobe in
                var l2 = l
                let r = l.c.length
                if r - l.r < 0.92 { l2.c = l.c * ((0.92 + l.r) / r) }
                if r + l.r > 1.29 { l2.r = max(0.02, 1.29 - r) }
                return l2
            }
            let upMid = CGPoint.polar(1, deg(center))
            ops.append(DrawOp(z: 0.5 + Double(ci) * 0.01) { c in
                if s.isDark {
                    c.drawLayer { l in
                        l.addFilter(.blur(radius: 0.04))
                        for lb in clamped { l.fill(disc(lb.c, lb.r * 1.1), with: .color(pal.secondary.c(0.16))) }
                    }
                }
                Air.cloud(c, lobes: clamped, up: upMid, s: s, pal: pal, d: d, soft: d.minWidth(0.8))
            })
        }
        // 3) 小さな雲片と光の粒
        if q > 0.4 {
            for (ad, r) in [(CGFloat(300), CGFloat(0.035)), (CGFloat(126), CGFloat(0.03)), (CGFloat(160), CGFloat(0.022))] {
                let c0 = CGPoint.polar(1.1, deg(ad))
                var lobes: [Air.Lobe] = []
                for j in 0..<4 { lobes.append(Air.Lobe(c: c0 + CGPoint(x: (CGFloat(j) - 1.5) * r * 0.9, y: -abs(CGFloat(j) - 1.5) * r * -0.2), r: r * (j == 1 || j == 2 ? 1.1 : 0.75), back: false)) }
                ops.append(DrawOp(z: 0.4) { c in Air.cloud(c, lobes: lobes, up: CGPoint(x: 0, y: -1), s: s, pal: pal, d: d, soft: d.minWidth(0.8)) })
            }
            for _ in 0..<10 {
                let p = CGPoint.polar(rng.range(1.08, 1.26), deg(rng.range(0, 360)))
                ops.append(DrawOp(z: 1) { c in
                    var cc = c
                    if s.isDark { cc.blendMode = .plusLighter }
                    cc.fill(disc(p, d.w(0.005, minPx: 0.6)), with: .color((s.isDark ? RGB.white : pal.line2(s)).c(0.8)))
                })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0xC1, airAnchors: [
            (cc.tl, 0.5, pal.primary, s.isDark ? 0.16 : 0.12),
            (CGPoint(x: cc.rect.midX, y: cc.rect.maxY), 0.8, pal.secondary, s.isDark ? 0.18 : 0.14),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        var rng = SeededRNG(0xC2)
        // 層雲の筋
        if !cc.tiny {
            for (y, x0, x1, w) in [(CGFloat(0.84), CGFloat(0.28), CGFloat(0.7), CGFloat(2.4)), (0.9, 0.05, 0.42, 2.0), (0.075, 0.56, 0.98, 1.8)] {
                var pts: [CGPoint] = []
                for i in 0...30 {
                    let t = CGFloat(i) / 30
                    pts.append(CGPoint(x: cc.rect.minX + cc.rect.width * (x0 + (x1 - x0) * t), y: cc.rect.minY + cc.rect.height * y + sin(t * 4) * 1.5 * k))
                }
                Air.wisp(inner, points: pts, width: w * k, color: s.isDark ? pal.primary.mix(.white, 0.35) : pal.line(s).mix(.white, 0.3), alpha: 0.45, d: d)
            }
        }
        // 積雲：右下から湧き上がる大きな塊、左下と右上に小さく
        let up = CGPoint(x: 0.25, y: -1).normalized
        func bank(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ count: Int, _ size: CGFloat, _ height: CGFloat) {
            let lobes = Air.cloudLobes(along: { t in CGPoint(x: x0 + (x1 - x0) * t, y: y) }, up: { _ in CGPoint(x: 0, y: -1) },
                                       count: count, size: size, height: height, rng: &rng)
            if s.isDark {
                inner.drawLayer { l in
                    l.addFilter(.blur(radius: 6 * k))
                    for lb in lobes { l.fill(disc(lb.c, lb.r), with: .color(pal.secondary.c(0.18))) }
                }
            }
            Air.cloud(inner, lobes: lobes, up: up, s: s, pal: pal, d: d, soft: 0.5 * k)
        }
        bank(cc.rect.maxX - 120 * k, cc.rect.maxX + 6 * k, cc.rect.maxY + 6 * k, cc.tiny ? 6 : 13, 15 * k, 30 * k)
        bank(cc.rect.minX - 8 * k, cc.rect.minX + 70 * k, cc.rect.maxY + 8 * k, cc.tiny ? 4 : 8, 11 * k, 16 * k)
        if !cc.tiny { bank(cc.rect.maxX - 52 * k, cc.rect.maxX + 6 * k, cc.rect.minY + 14 * k, 6, 8 * k, 6 * k) }
        CardBase.drawRule(ctx, cc, gap: 30) { c, p, flip in
            let base = CGPoint(x: p.x, y: p.y + (flip ? -1.0 : 2.4) * k)
            let lobes = [Air.Lobe(c: base + CGPoint(x: -5 * k, y: 0), r: 3.2 * k, back: false), Air.Lobe(c: base + CGPoint(x: 0, y: -2 * k), r: 4.2 * k, back: false),
                         Air.Lobe(c: base + CGPoint(x: 5 * k, y: 0), r: 3.0 * k, back: false)]
            Air.cloud(c, lobes: lobes, up: CGPoint(x: 0, y: -1), s: s, pal: pal, d: d)
        }
    }
}

// MARK: - 霧面

enum MistMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0x3157)
        let q = d.quality, boost = d.boost
        let colA = s.isDark ? pal.primary.mix(.white, 0.25) : pal.line(s)
        let colB = s.isDark ? pal.secondary : pal.line(s).mix(.white, 0.35)
        // 輪に沿って幾重にも重なる霧の帯。対角で輪を離れ、渦を巻いてほどける
        let count = q < 0.4 ? 6 : 12
        for i in 0..<count {
            let start = rng.range(0, 360)
            let span = rng.range(70, 150)
            let r0 = 1.0 + rng.range(-0.04, 0.07)
            let amp = rng.range(0.015, 0.04), f = rng.range(2, 4), ph = rng.range(0, 6)
            var pts: [CGPoint] = []
            for j in 0...60 {
                let a = deg(start + span * CGFloat(j) / 60)
                pts.append(CGPoint.polar(r0 + amp * sin(f * a + ph) + 0.07 * angularBump(a, 214, 30) + 0.06 * angularBump(a, 36, 26), a))
            }
            // 先が渦になる（対角近くで）
            let endA = deg(start + span)
            if angularBump(endA, 214, 40) + angularBump(endA, 36, 40) > 0.4 && q > 0.3 {
                let dir = (pts[60] - pts[58]).angle
                pts += Array(Air.spiralTail(from: pts[60], dir: dir, radius: 0.045, turns: 0.9, sign: rng.sign()).dropFirst())
            }
            pts = pts.map { p in p.length > 1.27 ? p * (1.27 / p.length) : (p.length < 0.92 ? p * (0.92 / p.length) : p) }
            let w = rng.range(0.045, 0.09) * boost
            let col = i % 2 == 0 ? colA : colB
            let alpha = Double(rng.range(0.42, 0.7))
            ops.append(DrawOp(z: Double(i) * 0.01) { c in
                if s.isDark {
                    c.drawLayer { l in
                        l.addFilter(.blur(radius: 0.012))
                        Air.wisp(l, points: pts, width: w, color: col, alpha: alpha, d: d)
                    }
                } else {
                    Air.wisp(c, points: pts, width: w, color: col, alpha: alpha * 0.85, d: d)
                }
                // 帯の芯に細い光の筋
                let core = Array(pts.prefix(pts.count - 4))
                let ws = (0..<core.count).map { j -> CGFloat in d.w(0.0035 * sin(CGFloat.pi * CGFloat(j) / CGFloat(core.count - 1)), minPx: 0.3) }
                var cc = c
                if s.isDark { cc.blendMode = .plusLighter }
                drawTaperedStroke(cc, points: core, widths: ws, color: s.isDark ? RGB.white : pal.line(s), alpha: s.isDark ? 0.45 : 0.6)
            })
        }
        // 霧の粒
        if q > 0.4 {
            for _ in 0..<40 {
                let a = deg(rng.range(0, 360))
                let p = CGPoint.polar(1.0 + rng.gauss() * 0.08, a)
                guard p.length > 0.92 && p.length < 1.28 else { continue }
                ops.append(DrawOp(z: 0.5) { c in
                    c.fill(disc(p, d.w(rng.range(0.003, 0.006), minPx: 0.5)), with: .color(colB.c(0.6)))
                })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0x31, airAnchors: [
            (cc.tl, 0.6, pal.primary, s.isDark ? 0.18 : 0.12), (cc.br, 0.65, pal.secondary, s.isDark ? 0.2 : 0.14),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        var rng = SeededRNG(0x32)
        let colA = s.isDark ? pal.primary.mix(.white, 0.25) : pal.line(s)
        let colB = s.isDark ? pal.secondary : pal.line(s).mix(.white, 0.35)
        // 角から流れ込む霧の帯（渦を巻いてほどける）
        func swirl(from p: CGPoint, dir: CGFloat, len: CGFloat, w: CGFloat, col: RGB, sign: CGFloat) {
            var pts: [CGPoint] = []
            for i in 0...40 {
                let t = CGFloat(i) / 40
                pts.append(p + CGPoint.polar(len * t, dir) + CGPoint.polar(len * 0.12 * sin(t * 5), dir + .pi / 2))
            }
            pts += Array(Air.spiralTail(from: pts.last!, dir: dir, radius: len * 0.12, turns: 1.0, sign: sign).dropFirst())
            let boostA = cc.tiny ? 1.5 : 1.0
            if s.isDark {
                inner.drawLayer { l in l.addFilter(.blur(radius: 1.6 * k)); Air.wisp(l, points: pts, width: w, color: col, alpha: 0.5 * boostA, d: d) }
            } else {
                Air.wisp(inner, points: pts, width: w, color: col, alpha: 0.42 * boostA, d: d)
            }
            let ws = (0..<pts.count).map { j -> CGFloat in d.w(0.5 * k * sin(CGFloat.pi * CGFloat(j) / CGFloat(pts.count - 1)), minPx: 0.35) }
            drawTaperedStroke(inner, points: pts, widths: ws, color: s.isDark ? RGB.white : pal.line(s), alpha: 0.45)
        }
        let n = cc.tiny ? 2 : 5
        for i in 0..<n {
            swirl(from: CGPoint(x: cc.rect.maxX + 4 * k, y: cc.rect.maxY - CGFloat(i) * 14 * k - 6 * k), dir: deg(180 + rng.range(-12, 6)),
                  len: rng.range(70, 120) * k, w: rng.range(8, 16) * k * (cc.tiny ? 1.8 : 1), col: i % 2 == 0 ? colA : colB, sign: 1)
        }
        for i in 0..<(cc.tiny ? 1 : 3) {
            swirl(from: CGPoint(x: cc.rect.minX - 4 * k, y: cc.rect.minY + CGFloat(i) * 12 * k + 8 * k), dir: deg(rng.range(-6, 10)),
                  len: rng.range(50, 80) * k, w: rng.range(7, 12) * k, col: i % 2 == 0 ? colB : colA, sign: -1)
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            let spiral = Air.spiralTail(from: CGPoint(x: p.x - 6 * k, y: p.y + (flip ? -0.5 : 0.5) * k), dir: 0, radius: 3.4 * k, turns: 1.2, sign: flip ? -1 : 1)
            let ws = (0..<spiral.count).map { j -> CGFloat in d.w(1.0 * k * (1 - CGFloat(j) / CGFloat(spiral.count)), minPx: 0.4) }
            drawTaperedStroke(c, points: spiral, widths: ws, color: pal.line(s), alpha: 0.85)
        }
    }
}

// MARK: - 極光線

enum AuroraMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        var rng = SeededRNG(0xA0A0)
        let q = d.quality, boost = d.boost
        // 1) 細い軌跡の線と小さな節点（「線」）
        ops.append(DrawOp(z: 0) { c in
            c.stroke(disc(.zero, 1.0), with: .color((s.isDark ? pal.secondary : pal.line2(s)).c(0.75)), lineWidth: d.w(0.004 * boost, minPx: 0.7))
            for ad in [CGFloat(270), 0, 90, 180] {
                let p = CGPoint.polar(1.0, deg(ad))
                c.fill(disc(p, d.w(0.012 * boost, minPx: 1.2)), with: .color((s.isDark ? pal.secondary.mix(.white, 0.4) : pal.line2(s)).c()))
                c.stroke(disc(p, 0.024 * boost), with: .color((s.isDark ? pal.secondary : pal.line2(s)).c(0.6)), lineWidth: d.w(0.0025, minPx: 0.4))
            }
        })
        // 2) オーロラの幕：二枚。輪の外側に立ち上がり、高さが波打つ
        for (i, spec) in [(CGFloat(148), CGFloat(150), CGFloat(0.24)), (CGFloat(-18), CGFloat(108), CGFloat(0.19))].enumerated() {
            let (a0, span, hmax) = spec
            let ph = rng.range(0, 6)
            let base: (CGFloat) -> CGPoint = { t in
                let a = deg(a0 + span * t)
                return CGPoint.polar(0.99 + 0.025 * sin(t * 9 + ph), a)
            }
            let up: (CGFloat) -> CGPoint = { t in CGPoint.polar(1, deg(a0 + span * t)) }
            let height: (CGFloat) -> CGFloat = { t in
                let env = pow(sin(.pi * t), 0.6)
                return min(0.29, hmax * env * (0.65 + 0.35 * sin(t * 13 + ph) * sin(t * 5)))
            }
            ops.append(DrawOp(z: 0.5 + Double(i) * 0.01) { c in
                Air.auroraCurtain(c, base: base, up: up, rays: q < 0.4 ? 60 : 160, height: height, s: s, pal: pal, d: d, rayWidth: 0.0042 * boost)
            })
        }
        // 3) 星
        if q > 0.35 {
            let st = StarStyle.make(s, pal)
            for (ad, r, m) in [(CGFloat(228), CGFloat(1.24), 0), (CGFloat(20), CGFloat(1.22), 1), (CGFloat(300), CGFloat(1.18), 2), (CGFloat(110), CGFloat(1.15), 2)] {
                let p = CGPoint.polar(r, deg(ad))
                ops.append(DrawOp(z: 1) { c in Celestial.star(c, at: p, magnitude: m, size: 0.03, tint: st.tints[1], style: st, d: d) })
            }
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        CardBase.drawGround(ctx, cc, seed: 0xA1, airAnchors: [
            (CGPoint(x: cc.rect.maxX - 60 * k, y: cc.rect.minY), 0.75, pal.primary, s.isDark ? 0.2 : 0.12),
            (cc.bl, 0.5, pal.secondary, s.isDark ? 0.12 : 0.1),
        ])
        var inner = ctx
        inner.clip(to: cc.shape)
        // 上辺に沿う幕（文字の上に出ない高さ）
        let x0 = cc.rect.minX + 130 * k, x1 = cc.rect.maxX - 4 * k
        Air.auroraCurtain(inner, base: { t in CGPoint(x: x0 + (x1 - x0) * t, y: cc.rect.minY + 22 * k + 3 * k * sin(t * 7) - 4 * k * t) },
                          up: { _ in CGPoint(x: 0.12, y: -1).normalized },
                          rays: cc.tiny ? 50 : 150, height: { t in (10 + 6 * sin(.pi * t)) * k * (0.7 + 0.3 * sin(t * 17)) },
                          s: s, pal: pal, d: d, rayWidth: 0.9 * k)
        // 右下の低い幕と、地平の稜線
        let bx0 = cc.rect.maxX - 150 * k, bx1 = cc.rect.maxX + 2 * k
        Air.auroraCurtain(inner, base: { t in CGPoint(x: bx0 + (bx1 - bx0) * t, y: cc.rect.maxY - 22 * k + 5 * k * sin(t * 6)) },
                          up: { _ in CGPoint(x: -0.1, y: -1).normalized },
                          rays: cc.tiny ? 40 : 120, height: { t in 26 * k * pow(sin(.pi * t), 0.8) * (0.6 + 0.4 * sin(t * 11)) },
                          s: s, pal: pal, d: d, rayWidth: 0.9 * k)
        var ridge = Path()
        ridge.move(to: CGPoint(x: cc.rect.minX, y: cc.rect.maxY - 8 * k))
        for i in 0...30 {
            let t = CGFloat(i) / 30
            ridge.addLine(to: CGPoint(x: cc.rect.minX + cc.rect.width * t, y: cc.rect.maxY - 9 * k - 7 * k * abs(sin(t * 5.3 + 0.7)) * sin(.pi * t)))
        }
        ridge.addLine(to: CGPoint(x: cc.rect.maxX, y: cc.rect.maxY)); ridge.addLine(to: CGPoint(x: cc.rect.minX, y: cc.rect.maxY)); ridge.closeSubpath()
        inner.fill(ridge, with: .color((s.isDark ? RGB(0x0E0B1C) : pal.line(s).mix(.white, 0.55)).c(s.isDark ? 0.75 : 0.35)))
        // 星
        if !cc.tiny {
            let st = StarStyle.make(s, pal)
            var rng = SeededRNG(0xA2)
            for _ in 0..<14 {
                let p = CGPoint(x: cc.rect.minX + rng.unit() * cc.rect.width, y: cc.rect.minY + rng.range(8, 60) * k)
                if cc.textZone.contains(p) || cc.avatarZone.contains(p) { continue }
                Celestial.star(ctx, at: p, magnitude: rng.chance(0.2) ? 1 : 3, size: 3 * k, tint: st.tints[1], style: st, d: d)
            }
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            c.fill(disc(p, 2.2 * k), with: .color((s.isDark ? pal.secondary.mix(.white, 0.4) : pal.line2(s)).c()))
            c.stroke(disc(p, 4 * k), with: .color(pal.line2(s).c(0.6)), lineWidth: d.w(0.5 * k, minPx: 0.5))
        }
    }
}

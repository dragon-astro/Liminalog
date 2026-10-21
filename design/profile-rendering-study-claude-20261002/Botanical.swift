// 植物の部品（葉・花・蕾・実・レースフラワー・茎・小枝）。フレームとカードで共有する。
import SwiftUI

struct LeafTone {
    var base: RGB, tip: RGB, shade: RGB, vein: RGB, edge: RGB

    static let emerald = LeafTone(base: RGB(0x2A8670), tip: RGB(0x86CDAE), shade: RGB(0x1B6656), vein: RGB(0xE6F8EE), edge: RGB(0x175746))
    static let mint = LeafTone(base: RGB(0x4FA88B), tip: RGB(0xBDE6CC), shade: RGB(0x37876F), vein: RGB(0xF1FBF5), edge: RGB(0x2A6F5E))
    static let spring = LeafTone(base: RGB(0x5FA47A), tip: RGB(0xD2E8AE), shade: RGB(0x46875F), vein: RGB(0xF5FBE8), edge: RGB(0x376F4D))
    static let lagoon = LeafTone(base: RGB(0x2B8090), tip: RGB(0x98D6D4), shade: RGB(0x1F626F), vein: RGB(0xE4F7F7), edge: RGB(0x18525C))
    static let all: [LeafTone] = [.emerald, .mint, .spring, .lagoon, .emerald, .mint]

    func mixed(_ o: LeafTone, _ t: Double) -> LeafTone {
        LeafTone(base: base.mix(o.base, t), tip: tip.mix(o.tip, t), shade: shade.mix(o.shade, t), vein: vein.mix(o.vein, t), edge: edge.mix(o.edge, t))
    }
    func faded(toward bg: RGB, _ t: Double) -> LeafTone {
        LeafTone(base: base.mix(bg, t), tip: tip.mix(bg, t), shade: shade.mix(bg, t), vein: vein.mix(bg, t * 0.5), edge: edge.mix(bg, t))
    }
    /// 葉裏（白っぽく、脈が濃い）
    var underside: LeafTone {
        LeafTone(base: base.mix(vein, 0.38), tip: tip.mix(vein, 0.45), shade: shade.mix(vein, 0.2), vein: shade.mix(base, 0.3), edge: edge)
    }
}

enum BotanicalPalette {
    static let stemSage = RGB(0x5F9A82)
    static let stemTeal = RGB(0x467F74)
    static let strandCeladon = RGB(0x9FC8B2)
    static let strandGold = RGB(0xC9AB72)
    static let strandRose = RGB(0xC79C9E)
    static let strandShadow = RGB(0x22443B)
    static let petal = RGB(0xFFF8EE)
    static let petalRose = RGB(0xF0B9C4)
    static let petalLilac = RGB(0xEEE8FF)
    static let petalLilacBase = RGB(0xA992EA)
    static let flowerCenter = RGB(0xE5AE52)
    static let berry = RGB(0xB8A8EE)
    static let berryDeep = RGB(0x7C69CF)
    static let pollen = RGB(0xF4DFA6)
}

struct LeafSpec {
    var length: CGFloat
    var width: CGFloat      // 長さに対する半幅比
    var bend: CGFloat       // 主脈の反り（+で下側へ）
    var asym: CGFloat       // 左右非対称
    var widest: CGFloat     // 最大幅の位置（0..1）
    var tip: CGFloat = 0.04 // 葉先の伸び（尖り）
}

/// 葉の種類。1本の枝の中では種類を揃え、枝ごとに変えて「同じ葉の量産」に見せない。
enum LeafKind: CaseIterable {
    case lance, ovate, round, willow

    func spec(_ L: CGFloat, side: CGFloat, rng: inout SeededRNG) -> LeafSpec {
        switch self {
        case .lance:
            return LeafSpec(length: L, width: rng.range(0.2, 0.26), bend: side * rng.range(0.02, 0.1), asym: rng.range(-0.1, 0.1), widest: rng.range(0.38, 0.46), tip: rng.range(0.03, 0.08))
        case .ovate:
            return LeafSpec(length: L * 0.92, width: rng.range(0.3, 0.37), bend: side * rng.range(0.0, 0.08), asym: rng.range(-0.12, 0.12), widest: rng.range(0.34, 0.42), tip: rng.range(0.05, 0.1))
        case .round:
            return LeafSpec(length: L * 0.66, width: rng.range(0.4, 0.47), bend: side * rng.range(0, 0.05), asym: rng.range(-0.08, 0.08), widest: rng.range(0.48, 0.56), tip: 0)
        case .willow:
            return LeafSpec(length: L * 1.18, width: rng.range(0.12, 0.155), bend: side * rng.range(0.06, 0.16), asym: 0, widest: 0.4, tip: 0.04)
        }
    }
}

enum Botanical {
    /// 葉の輪郭・上半分（陰影用）・主脈を返す。原点=葉柄の付け根、+x 方向に伸びる。
    static func leafGeometry(_ s: LeafSpec) -> (outline: Path, upperHalf: Path, mid: [CGPoint], up: [CGPoint], lo: [CGPoint]) {
        let n = 16
        let L = s.length
        let a = log(0.5) / log(max(0.05, min(0.95, s.widest)))
        var mid: [CGPoint] = [], up: [CGPoint] = [], lo: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let x = t * L * (1 + s.tip * pow(t, 6))
            let my = s.bend * L * t * t
            let hw = s.width * L * pow(max(0, sin(.pi * pow(t, a))), 0.82)
            mid.append(CGPoint(x: x, y: my))
            up.append(CGPoint(x: x, y: my - hw * (1 + s.asym)))
            lo.append(CGPoint(x: x, y: my + hw * (1 - s.asym)))
        }
        let ring = up + lo[1..<n].reversed()
        let outline = smoothPath(ring, closed: true)
        var upper = smoothPath(up, closed: false)
        for p in mid.reversed() { upper.addLine(to: p) }
        upper.closeSubpath()
        return (outline, upper, mid, up, lo)
    }

    static func at(_ arr: [CGPoint], _ t: CGFloat) -> CGPoint {
        let f = max(0, min(1, t)) * CGFloat(arr.count - 1)
        let i = min(Int(f), arr.count - 2)
        return lerp(arr[i], arr[i + 1], f - CGFloat(i))
    }

    /// 水彩風の葉。グラデ＋片側の陰＋縁の顔料溜まり＋葉脈。グローは使わない。
    static func drawLeaf(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, spec s: LeafSpec, tone: LeafTone, detail d: Detail, alpha: Double = 1, stem: RGB? = nil) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        c.opacity = alpha
        let g = leafGeometry(s)
        let L = s.length
        let W = s.width * L
        let sizePx = d.px(L)

        if let stem, sizePx > 6 {
            var petiole = Path()
            petiole.move(to: CGPoint(x: -0.16 * L, y: -0.02 * L))
            petiole.addQuadCurve(to: CGPoint(x: 0.02 * L, y: 0), control: CGPoint(x: -0.06 * L, y: 0.02 * L))
            c.stroke(petiole, with: .color(stem.c(0.9)), style: StrokeStyle(lineWidth: d.w(0.05 * W, minPx: 0.5), lineCap: .round))
        }

        let tipPoint = g.mid.last ?? CGPoint(x: L, y: 0)
        c.fill(g.outline, with: .linearGradient(
            Gradient(stops: [
                .init(color: tone.base.c(0.97), location: 0),
                .init(color: tone.base.mix(tone.tip, 0.45).c(0.95), location: 0.45),
                .init(color: tone.tip.c(0.92), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: tipPoint))

        var inside = c
        inside.clip(to: g.outline)
        inside.fill(g.upperHalf, with: .linearGradient(
            Gradient(colors: [tone.shade.c(0.42), tone.shade.c(0.1)]),
            startPoint: CGPoint(x: 0.2 * L, y: -W), endPoint: CGPoint(x: 0.7 * L, y: 0)))
        if sizePx > 9 {
            inside.stroke(g.outline, with: .color(tone.edge.c(0.10)), lineWidth: 0.42 * W)
            inside.stroke(g.outline, with: .color(tone.edge.c(0.14)), lineWidth: 0.2 * W)
            inside.stroke(g.outline, with: .color(tone.edge.c(0.22)), lineWidth: d.w(0.07 * W, minPx: 0.4))
        }
        if sizePx > 13 {
            let midrib = smoothPath(Array(g.mid[0...14]), closed: false)
            inside.stroke(midrib, with: .color(tone.vein.c(0.62)), style: StrokeStyle(lineWidth: d.w(0.055 * W, minPx: 0.45), lineCap: .round))
            if sizePx > 24 && s.width < 0.4 && s.width > 0.17 {
                for k in 0..<5 {
                    let t0 = 0.12 + CGFloat(k) * 0.15
                    for side in [CGFloat(-1), 1] {
                        let tt = t0 + (side > 0 ? 0.06 : 0)
                        let start = at(g.mid, tt)
                        let edge = at(side < 0 ? g.up : g.lo, tt + 0.16)
                        let end = lerp(start, edge, 0.84)
                        let ctrl = lerp(start, edge, 0.5)
                        var v = Path()
                        v.move(to: start)
                        v.addQuadCurve(to: end, control: CGPoint(x: ctrl.x - 0.03 * L, y: ctrl.y))
                        inside.stroke(v, with: .color(tone.vein.c(0.36)), style: StrokeStyle(lineWidth: d.w(0.03 * W, minPx: 0.35), lineCap: .round))
                    }
                }
            }
        }
        c.stroke(g.outline, with: .color(tone.edge.c(0.35)), lineWidth: d.w(0.018 * W, minPx: 0.35))
    }

    static func petalPath(_ r: CGFloat, width: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: r * 0.94, y: -r * 0.08), control1: CGPoint(x: r * 0.28, y: -r * width), control2: CGPoint(x: r * 0.9, y: -r * width * 1.02))
        p.addQuadCurve(to: CGPoint(x: r * 0.94, y: r * 0.08), control: CGPoint(x: r * 0.86, y: 0))
        p.addCurve(to: .zero, control1: CGPoint(x: r * 0.9, y: r * width * 1.02), control2: CGPoint(x: r * 0.28, y: r * width))
        p.closeSubpath()
        return p
    }

    /// 5弁の小花。傾き(tilt)で楕円に潰して向きの変化を出す。
    static func drawFlower(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, rotation: CGFloat, tilt: CGFloat, lilac: Bool, detail d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(rotation))
        c.scaleBy(x: 1, y: 1 - tilt)
        let tipColor = lilac ? BotanicalPalette.petalLilac : BotanicalPalette.petal
        let baseColor = lilac ? BotanicalPalette.petalLilacBase : BotanicalPalette.petalRose
        let big = d.px(r) > 9
        // 花の下に落ちる薄い影で、葉や蔓の上に「載っている」重なりを作る
        c.fill(Celestial.disc(CGPoint(x: r * 0.06, y: r * 0.12), r * 1.02), with: .radialGradient(
            Gradient(colors: [RGB(0x1E4A3E).c(0.22), RGB(0x1E4A3E).c(0)]), center: CGPoint(x: r * 0.06, y: r * 0.12), startRadius: r * 0.5, endRadius: r * 1.05))
        for i in 0..<5 {
            let a = CGFloat(i) / 5 * 2 * .pi + rng.range(-0.1, 0.1)
            let pr = r * rng.range(0.9, 1.06)
            var pc = c
            pc.rotate(by: .radians(a))
            let petal = petalPath(pr, width: 0.54)
            pc.fill(petal, with: .radialGradient(
                Gradient(stops: [
                    .init(color: baseColor.c(0.95), location: 0),
                    .init(color: baseColor.mix(tipColor, 0.6).c(0.97), location: 0.38),
                    .init(color: tipColor.c(0.99), location: 1),
                ]),
                center: .zero, startRadius: 0, endRadius: pr))
            if big {
                var vein = Path()
                vein.move(to: CGPoint(x: pr * 0.18, y: 0))
                vein.addLine(to: CGPoint(x: pr * 0.62, y: 0))
                pc.stroke(vein, with: .color(baseColor.c(0.45)), lineWidth: d.w(0.035 * r, minPx: 0.3))
            }
            pc.stroke(petal, with: .color(baseColor.mix(RGB(0x8C6A72), 0.45).c(0.38)), lineWidth: d.w(0.025 * r, minPx: 0.3))
        }
        let cr = r * 0.21
        c.fill(Celestial.disc(.zero, cr),
               with: .radialGradient(Gradient(colors: [RGB(0xFBE3A3).c(), BotanicalPalette.flowerCenter.c(), RGB(0xB98236).c()]),
                                     center: CGPoint(x: -cr * 0.3, y: -cr * 0.3), startRadius: 0, endRadius: cr * 1.3))
        if big {
            for i in 0..<9 {
                let a = CGFloat(i) / 9 * 2 * .pi + 0.2
                let q = CGPoint.polar(r * 0.31, a)
                c.fill(Celestial.disc(q, r * 0.045), with: .color(RGB(0xC98F3C).c(0.85)))
            }
        }
    }

    /// 閉じた蕾＋萼。
    static func drawBud(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size s: CGFloat, detail d: Detail, lilac: Bool = false) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(angle))
        var bud = Path()
        bud.move(to: .zero)
        bud.addCurve(to: CGPoint(x: s, y: 0), control1: CGPoint(x: s * 0.1, y: -s * 0.55), control2: CGPoint(x: s * 0.85, y: -s * 0.32))
        bud.addCurve(to: .zero, control1: CGPoint(x: s * 0.85, y: s * 0.32), control2: CGPoint(x: s * 0.1, y: s * 0.55))
        let base = lilac ? BotanicalPalette.petalLilacBase : BotanicalPalette.petalRose
        c.fill(bud, with: .linearGradient(Gradient(colors: [base.c(), BotanicalPalette.petal.c()]),
                                          startPoint: .zero, endPoint: CGPoint(x: s, y: 0)))
        c.stroke(bud, with: .color(RGB(0xA06A7A).c(0.4)), lineWidth: d.w(0.04 * s, minPx: 0.3))
        for side in [CGFloat(-1), 1] {
            var sepal = Path()
            sepal.move(to: CGPoint(x: -s * 0.05, y: 0))
            sepal.addQuadCurve(to: CGPoint(x: s * 0.52, y: side * s * 0.16), control: CGPoint(x: s * 0.12, y: side * s * 0.38))
            sepal.addQuadCurve(to: CGPoint(x: -s * 0.05, y: 0), control: CGPoint(x: s * 0.2, y: side * s * 0.08))
            c.fill(sepal, with: .color(LeafTone.emerald.base.c(0.95)))
        }
    }

    static func drawBerry(_ ctx: GraphicsContext, at p: CGPoint, radius r: CGFloat, detail d: Detail) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(stops: [
                .init(color: RGB(0xF4F0FF).c(), location: 0),
                .init(color: BotanicalPalette.berry.c(), location: 0.35),
                .init(color: BotanicalPalette.berryDeep.c(), location: 1),
            ]),
            center: CGPoint(x: p.x - r * 0.38, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        if d.px(r) > 2.5 {
            let hr = r * 0.26
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5 - hr / 2, y: p.y - r * 0.5 - hr / 2, width: hr, height: hr)), with: .color(.white.opacity(0.85)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(RGB(0x5D4BA8).c(0.35)), lineWidth: d.w(0.06 * r, minPx: 0.3))
        }
    }

    /// 細い柄の先に実が数粒。
    static func drawBerrySpray(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size s: CGFloat, count: Int, detail d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        for i in 0..<count {
            let a = angle + (CGFloat(i) - CGFloat(count - 1) / 2) * 0.42 + rng.range(-0.12, 0.12)
            let len = s * rng.range(0.55, 1.0)
            let end = p + CGPoint.polar(len, a)
            var stalk = Path()
            stalk.move(to: p)
            stalk.addQuadCurve(to: end, control: p + CGPoint.polar(len * 0.5, a - 0.25))
            ctx.stroke(stalk, with: .color(BotanicalPalette.stemSage.c(0.85)), style: StrokeStyle(lineWidth: d.w(s * 0.035, minPx: 0.45), lineCap: .round))
            drawBerry(ctx, at: end, radius: s * rng.range(0.16, 0.21), detail: d)
        }
    }

    /// セリ科の小花序（レースフラワー）。細い放射と点の集まり。
    static func drawUmbel(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, size s: CGFloat, detail d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let stemEnd = p + CGPoint.polar(s * 0.55, angle)
        var stem = Path()
        stem.move(to: p)
        stem.addLine(to: stemEnd)
        ctx.stroke(stem, with: .color(BotanicalPalette.stemSage.c(0.8)), lineWidth: d.w(s * 0.03, minPx: 0.4))
        let rays = 9
        for i in 0..<rays {
            let a = angle + (CGFloat(i) / CGFloat(rays - 1) - 0.5) * 2.0
            let end = stemEnd + CGPoint.polar(s * rng.range(0.38, 0.5), a)
            var ray = Path()
            ray.move(to: stemEnd)
            ray.addLine(to: end)
            ctx.stroke(ray, with: .color(BotanicalPalette.stemSage.c(0.6)), lineWidth: d.w(s * 0.016, minPx: 0.3))
            for _ in 0..<4 {
                let q = end + CGPoint(x: rng.gauss() * s * 0.045, y: rng.gauss() * s * 0.045)
                let r = s * rng.range(0.024, 0.04)
                ctx.fill(Celestial.disc(q, d.w(r, minPx: 0.5)), with: .color((rng.chance(0.75) ? BotanicalPalette.petal : BotanicalPalette.petalRose).c(0.95)))
            }
        }
    }

    /// かすみ草のような細い分岐の先に小さな蕾が付く房。輪に空気感と細密さを足す。
    static func drawSpray(_ ctx: GraphicsContext, at p: CGPoint, angle: CGFloat, length L: CGFloat, detail d: Detail, seed: UInt64) {
        var rng = SeededRNG(seed)
        let end = p + CGPoint.polar(L, angle + rng.range(-0.25, 0.25))
        let ctrl = p + CGPoint.polar(L * 0.5, angle)
        var stalk = Path()
        stalk.move(to: p)
        stalk.addQuadCurve(to: end, control: ctrl)
        let stemW = d.w(L * 0.018, minPx: 0.4)
        ctx.stroke(stalk, with: .color(BotanicalPalette.stemSage.c(0.9)), style: StrokeStyle(lineWidth: stemW, lineCap: .round))
        let budColors = [BotanicalPalette.petal, BotanicalPalette.petal, BotanicalPalette.petalRose, BotanicalPalette.petalLilac, BotanicalPalette.pollen]
        var tips: [CGPoint] = [end]
        let branches = Int(rng.range(3, 6))
        for b in 0..<branches {
            let t = 0.3 + 0.6 * CGFloat(b) / CGFloat(branches)
            let q = quadPoint(p, ctrl, end, t)
            let tan = quadTangent(p, ctrl, end, t).angle
            let side: CGFloat = b % 2 == 0 ? 1 : -1
            let bl = L * rng.range(0.22, 0.38) * (1.1 - t * 0.5)
            let be = q + CGPoint.polar(bl, tan + side * rng.range(0.5, 0.9))
            var br = Path()
            br.move(to: q)
            br.addQuadCurve(to: be, control: q + CGPoint.polar(bl * 0.5, tan + side * 0.3))
            ctx.stroke(br, with: .color(BotanicalPalette.stemSage.c(0.8)), style: StrokeStyle(lineWidth: stemW * 0.75, lineCap: .round))
            tips.append(be)
        }
        for tip in tips {
            for _ in 0..<Int(rng.range(2, 4)) {
                let q = tip + CGPoint(x: rng.gauss() * L * 0.035, y: rng.gauss() * L * 0.035)
                let r = d.w(L * rng.range(0.03, 0.05), minPx: 0.55)
                let col = rng.pick(budColors)
                ctx.fill(Celestial.disc(q, r), with: .radialGradient(Gradient(colors: [RGB(0xFFFFFF).c(), col.c(), col.mix(RGB(0x8C6A72), 0.25).c()]),
                                                                    center: q - CGPoint(x: r * 0.3, y: r * 0.3), startRadius: 0, endRadius: r * 1.2))
            }
        }
    }

    /// 先細りの線（茎・蔓）。点列に沿って幅を補間しながら短い線分で描く。
    static func drawTaperedStroke(_ ctx: GraphicsContext, points: [CGPoint], widths: [CGFloat], color: RGB, alpha: Double) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            var seg = Path()
            seg.move(to: points[i])
            seg.addLine(to: points[i + 1])
            ctx.stroke(seg, with: .color(color.c(alpha)), style: StrokeStyle(lineWidth: (widths[i] + widths[i + 1]) / 2, lineCap: .round))
        }
    }

    enum Terminal { case leaf, bud, flower, berries, umbel }

    /// 茎＋葉（互生/対生）＋先端。フレームでもカード角でも同じ部品を使い、造形言語を揃える。
    static func sprigOps(origin: CGPoint, angle: CGFloat, length: CGFloat, curl: CGFloat, leafScale: CGFloat,
                         terminal: Terminal, tone: LeafTone, kind: LeafKind = .lance, z: Double, detail d: Detail, seed: UInt64,
                         alpha: Double = 1, leafCount: Int? = nil) -> [DrawOp] {
        var rng = SeededRNG(seed)
        var ops: [DrawOp] = []
        let end = origin + CGPoint.polar(length, angle + curl)
        let ctrl = origin + CGPoint.polar(length * 0.55, angle)
        var pts: [CGPoint] = [], ws: [CGFloat] = []
        for i in 0...12 {
            let t = CGFloat(i) / 12
            pts.append(quadPoint(origin, ctrl, end, t))
            ws.append(d.w(length * 0.026 * (1 - 0.65 * t), minPx: 0.5))
        }
        let stemColor = rng.chance(0.5) ? BotanicalPalette.stemSage : BotanicalPalette.stemTeal
        ops.append(DrawOp(z: z - 0.01) { c in
            var cc = c; cc.opacity = alpha
            drawTaperedStroke(cc, points: pts, widths: ws, color: stemColor, alpha: 0.92)
        })
        let opposite = kind == .round
        let spacing: CGFloat = kind == .willow ? 0.34 : (kind == .round ? 0.55 : 0.44)
        let count = leafCount ?? max(2, Int(length / (leafScale * spacing)))
        var side: CGFloat = rng.sign()
        for k in 0..<count {
            var t = 0.2 + 0.7 * CGFloat(k) / CGFloat(max(1, count - 1))
            t += rng.range(-0.05, 0.05)
            let p = quadPoint(origin, ctrl, end, t)
            let tan = quadTangent(origin, ctrl, end, t).angle
            let sides: [CGFloat] = opposite ? [-1, 1] : [side]
            for sd in sides {
                let spread = deg(kind == .willow ? rng.range(22, 38) : rng.range(32, 58))
                let a = tan + sd * spread
                let L = leafScale * (1.0 - 0.36 * t) * rng.range(0.8, 1.14)
                let spec = kind.spec(L, side: sd, rng: &rng)
                var leafTone = tone
                if rng.chance(0.4) { leafTone = tone.mixed(rng.pick(LeafTone.all), Double(rng.range(0.2, 0.6))) }
                if rng.chance(0.14) { leafTone = leafTone.underside }
                let zz = z + (rng.chance(0.3) ? -0.05 : 0.05) + Double(k) * 0.001
                ops.append(DrawOp(z: zz) { c in drawLeaf(c, at: p, angle: a, spec: spec, tone: leafTone, detail: d, alpha: alpha, stem: stemColor) })
            }
            side *= -1
        }
        let endTan = quadTangent(origin, ctrl, end, 1).angle
        let s2 = UInt64(rng.next())
        switch terminal {
        case .leaf:
            let spec = kind.spec(leafScale * 0.8, side: 0, rng: &rng)
            ops.append(DrawOp(z: z + 0.06) { c in drawLeaf(c, at: end, angle: endTan, spec: spec, tone: tone, detail: d, alpha: alpha, stem: stemColor) })
        case .bud:
            ops.append(DrawOp(z: z + 0.3) { c in drawBud(c, at: end, angle: endTan, size: leafScale * 0.42, detail: d, lilac: s2 % 3 == 0) })
        case .flower:
            let tilt = rng.range(0, 0.38)
            let rot = rng.range(0, 2 * .pi)
            ops.append(DrawOp(z: z + 0.4) { c in drawFlower(c, at: end, radius: leafScale * 0.34, rotation: rot, tilt: tilt, lilac: s2 % 4 == 0, detail: d, seed: s2) })
        case .berries:
            ops.append(DrawOp(z: z + 0.35) { c in drawBerrySpray(c, at: end, angle: endTan, size: leafScale * 0.46, count: 3, detail: d, seed: s2) })
        case .umbel:
            ops.append(DrawOp(z: z + 0.32) { c in drawUmbel(c, at: end, angle: endTan, size: leafScale * 0.62, detail: d, seed: s2) })
        }
        return ops
    }
}

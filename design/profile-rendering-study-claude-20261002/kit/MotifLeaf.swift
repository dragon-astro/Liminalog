// 葉隅：最初の試作の植物描画を移植し、テーマ（宵／曙）とカード土台に載せ替えた。
import SwiftUI

enum LeafMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        Botanical.toneScheme = s
        defer { Botanical.toneScheme = .daybreak }
        return LeafFrameBuilder.build(detail: d)
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        Botanical.toneScheme = s
        defer { Botanical.toneScheme = .daybreak }
        CardBase.drawGround(ctx, cc, seed: 0x1EAF)
        CardBase.drawRule(ctx, cc, gap: 30) { c, p, flip in finial(c, at: CGPoint(x: p.x, y: p.y + (flip ? -1.3 : 1.3) * k), k: k, flip: flip, s: s, pal: pal, d: d) }
        var ops: [DrawOp] = []
        ops += LeafCardParts.cluster(corner: CGPoint(x: cc.rect.minX + 5 * k, y: cc.rect.minY + 6 * k), into: CGPoint(x: 1, y: 0.92), k: k * 0.8, d: d,
                                     seed: 11, big: false, tiny: cc.tiny, bounds: cc.bounds)
        ops += LeafCardParts.cluster(corner: CGPoint(x: cc.rect.maxX - 5 * k, y: cc.rect.maxY - 6 * k), into: CGPoint(x: -1, y: -0.92), k: k, d: d,
                                     seed: 23, big: true, tiny: cc.tiny, bounds: cc.bounds)
        for op in ops.sorted(by: { $0.z < $1.z }) { op.draw(ctx) }
    }

    static func finial(_ ctx: GraphicsContext, at p: CGPoint, k: CGFloat, flip: Bool, s: DecoScheme, pal: ItemPalette, d: Detail) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        if flip { c.scaleBy(x: 1, y: -1) }
        for sgn in [CGFloat(-1), 1] {
            Botanical.drawLeaf(c, at: CGPoint(x: sgn * 1.4 * k, y: 0.4 * k), angle: sgn > 0 ? deg(-10) : deg(190),
                               spec: LeafSpec(length: 10 * k, width: 0.27, bend: -0.08 * sgn, asym: 0, widest: 0.42, tip: 0.06),
                               tone: LeafTone.all[0], detail: d)
        }
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -3.4 * k))
        drop.addQuadCurve(to: CGPoint(x: 0, y: 5.2 * k), control: CGPoint(x: 2.8 * k, y: 2 * k))
        drop.addQuadCurve(to: CGPoint(x: 0, y: -3.4 * k), control: CGPoint(x: -2.8 * k, y: 2 * k))
        c.fill(drop, with: .color(pal.line(s).c(0.85)))
        Botanical.drawBerry(c, at: CGPoint(x: 0, y: 8 * k), radius: 1.6 * k, detail: d)
    }
}

// MARK: - フレーム（最初の試作から移植）

enum LeafFrameBuilder {
    /// 角度は画面座標（y下向き）。カードの左上・右下の茂みと同じ対角に密度の山を置く。
    static func density(_ a: CGFloat) -> CGFloat {
        func bump(_ c: CGFloat, _ w: CGFloat) -> CGFloat {
            var dd = abs(a - deg(c)).truncatingRemainder(dividingBy: 2 * .pi)
            if dd > .pi { dd = 2 * .pi - dd }
            return exp(-(dd * dd) / (2 * deg(w) * deg(w)))
        }
        return 0.32 + 0.75 * bump(200, 40) + 0.62 * bump(38, 36) + 0.18 * bump(115, 28)
    }

    static let maxRadius: CGFloat = 1.28   // キャンバス端は 1.337
    static let minRadius: CGFloat = 0.9    // アバター境界(1.0)の内側にはここまでしか入らない

    /// 小枝の先端が外周・内周の制限に収まるまで長さを縮める。
    static func fit(origin: CGPoint, angle: CGFloat, curl: CGFloat, length: CGFloat, leaf: CGFloat) -> CGFloat {
        var len = length
        for _ in 0..<12 {
            let end = origin + CGPoint.polar(len, angle + curl * 0.6)
            let outer = end.length + leaf * 0.85
            let inner = end.length - leaf * 0.55
            if outer <= maxRadius && inner >= minRadius { break }
            len *= 0.86
        }
        return len
    }

    static func build(detail d: Detail) -> [DrawOp] {
        var rng = SeededRNG(0x1EAF_2026)
        var ops: [DrawOp] = []
        let q = d.quality
        let boost = 1 + 0.55 * (1 - q)        // 小さい表示ほど要素を大きく・少なく
        let keep = 0.36 + 0.64 * q

        // 1) 編み込まれた蔓：同じ周波数・位相違いの正弦で互いに潜り合う。奥の区間は暗く細く。
        struct Strand { var color: RGB; var width: CGFloat; var phase: CGFloat; var start: CGFloat; var span: CGFloat; var freq: CGFloat; var amp: CGFloat; var minQ: CGFloat }
        let strands: [Strand] = [
            Strand(color: BotanicalPalette.stemSage, width: 0.017, phase: 0.0, start: 96, span: 372, freq: 7, amp: 0.026, minQ: 0),
            Strand(color: BotanicalPalette.strandCeladon, width: 0.012, phase: 2.1, start: 90, span: 372, freq: 7, amp: 0.028, minQ: 0),
            Strand(color: BotanicalPalette.stemTeal, width: 0.014, phase: 4.2, start: 84, span: 372, freq: 7, amp: 0.024, minQ: 0),
            Strand(color: BotanicalPalette.strandGold, width: 0.0085, phase: 1.0, start: 120, span: 300, freq: 7, amp: 0.034, minQ: 0.3),
            Strand(color: BotanicalPalette.strandRose, width: 0.0065, phase: 3.1, start: 250, span: 250, freq: 7, amp: 0.03, minQ: 0.45),
            Strand(color: BotanicalPalette.strandCeladon, width: 0.007, phase: 5.2, start: 20, span: 320, freq: 7, amp: 0.032, minQ: 0.45),
            Strand(color: BotanicalPalette.stemSage, width: 0.0035, phase: 0.6, start: 150, span: 200, freq: 11, amp: 0.04, minQ: 0.7),
            Strand(color: BotanicalPalette.strandGold, width: 0.003, phase: 2.6, start: 330, span: 170, freq: 11, amp: 0.042, minQ: 0.7),
        ]
        let minStrandPx: CGFloat = q < 0.4 ? 0.9 : 0.6
        for (si, s) in strands.enumerated() where q >= s.minQ {
            let steps = Int(s.span * (q < 0.4 ? 0.6 : 1.4))
            var pts: [CGPoint] = [], ws: [CGFloat] = [], depth: [CGFloat] = []
            let wobble = rng.range(0, 6)
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let a = deg(s.start + s.span * t)
                let phase = s.freq * a + s.phase
                let r = 1.0 + s.amp * sin(phase) + 0.006 * sin(3 * a + wobble)
                pts.append(CGPoint.polar(r, a))
                depth.append(cos(phase))
                let taper = s.span < 360 ? min(1, min(t, 1 - t) * 9) : 1
                ws.append(d.w(s.width * boost * (0.3 + 0.7 * taper), minPx: minStrandPx))
            }
            let front = s.color.mix(.init(0xFFFFFF), 0.08)
            let back = s.color.mix(BotanicalPalette.strandShadow, 0.42)
            let hi = s.color.mix(.init(0xFFFFFF), 0.5)
            for passFront in [false, true] {
                ops.append(DrawOp(z: passFront ? 0.3 + Double(si) * 0.001 : -0.4 + Double(si) * 0.001) { c in
                    for i in 0..<(pts.count - 1) where (depth[i] >= 0) == passFront {
                        var seg = Path()
                        seg.move(to: pts[i]); seg.addLine(to: pts[i + 1])
                        let w = (ws[i] + ws[i + 1]) / 2 * (passFront ? 1 : 0.86)
                        c.stroke(seg, with: .color((passFront ? front : back).c()), style: StrokeStyle(lineWidth: w, lineCap: .round))
                    }
                    if passFront && q > 0.45 {
                        for i in 0..<(pts.count - 1) where depth[i] > 0.25 {
                            var seg = Path()
                            seg.move(to: pts[i] * 0.9985); seg.addLine(to: pts[i + 1] * 0.9985)
                            c.stroke(seg, with: .color(hi.c()), style: StrokeStyle(lineWidth: ws[i] * 0.32, lineCap: .round))
                        }
                    }
                })
            }
        }

        // 2) 巻きひげ（外へ跳ねる細い渦）
        if q > 0.35 {
            for (k, a0d) in [CGFloat(12), 148, 236, 284, 96].enumerated() where CGFloat(k) < 5 * keep {
                let a0 = deg(a0d)
                let base = CGPoint.polar(1.0, a0)
                let dir: CGFloat = k % 2 == 0 ? 1 : -1
                let len: CGFloat = rng.range(0.06, 0.09) * boost
                let center = CGPoint.polar(1.0 + len * 1.05, a0 + dir * 0.05)
                var pts: [CGPoint] = []
                for i in 0...48 {
                    let t = CGFloat(i) / 48
                    let rr = len * (1 - 0.85 * t)
                    let ang = a0 + .pi + dir * t * 1.6 * 2 * .pi * 0.75
                    pts.append(lerp(base, center + CGPoint.polar(rr, ang), min(1, t * 3)))
                }
                let ws = (0...48).map { i in d.w(0.0055 * (1 - CGFloat(i) / 60), minPx: 0.45) }
                ops.append(DrawOp(z: 0.05 + Double(k) * 0.001) { c in
                    drawTaperedStroke(c, points: pts, widths: ws, color: BotanicalPalette.stemSage, alpha: 1)
                })
            }
        }

        // 3) 小枝：古典的なリース構造（下から左右へ分かれて上で出会う）。輪に沿って寝かせる
        var a: CGFloat = 0
        let kinds: [LeafKind] = [.lance, .lance, .ovate, .ovate, .round, .willow]
        while a < 360 {
            let ang = deg(a + rng.range(-2, 2))
            let dens = density(ang)
            let prio = rng.unit()
            let flow: CGFloat = (ang > deg(90) && ang < deg(270)) ? 1 : -1
            let tangent = CGPoint(x: -sin(ang) * flow, y: cos(ang) * flow)
            let normal = CGPoint(x: cos(ang), y: sin(ang))
            let inward = rng.chance(0.2)
            let lift = deg(inward ? rng.range(4, 12) : rng.range(8, 34))
            let v = tangent * cos(lift) + normal * (sin(lift) * (inward ? -1 : 1))
            let crossSign: CGFloat = (v.x * tangent.y - v.y * tangent.x) >= 0 ? 1 : -1
            let curl = crossSign * lift * rng.range(0.6, 1.3)
            let kind = rng.pick(kinds)
            let leafScale = rng.range(0.085, 0.12) * boost * (kind == .willow ? 0.92 : 1)
            let origin = CGPoint.polar(1.0 + rng.range(-0.02, 0.02), ang)
            var length = rng.range(0.13, 0.24) * (0.8 + 0.3 * min(1, dens)) * sqrt(boost) * (inward ? 0.6 : 1)
            length = fit(origin: origin, angle: v.angle, curl: curl, length: length, leaf: leafScale)
            let roll = rng.unit()
            let terminal: Botanical.Terminal
            if roll < 0.12 { terminal = .flower }
            else if roll < 0.26 { terminal = .berries }
            else if roll < 0.36 && q > 0.5 { terminal = .umbel }
            else if roll < 0.48 { terminal = .bud }
            else { terminal = .leaf }
            let behind = rng.chance(0.38) || inward
            let z = behind ? -0.2 + Double(rng.unit()) * 0.4 : 1.0 + Double(rng.unit()) * 0.8
            let tone = rng.pick(LeafTone.all)
            let seed = rng.next()
            if prio < keep {
                ops += Botanical.sprigOps(origin: origin, angle: v.angle, length: length, curl: curl, leafScale: leafScale,
                                          terminal: terminal, tone: tone, kind: kind, z: z, detail: d, seed: seed,
                                          leafCount: q < 0.3 ? 2 : nil)
            }
            a += rng.range(7, 11) / max(0.35, dens) / sqrt(keep)
        }

        // 4) 輪に直接付く大きめの葉（シルエットの主役）
        let bigLeaves = Int(8 + 9 * q)
        for i in 0..<bigLeaves {
            var ang: CGFloat
            repeat { ang = deg(rng.range(0, 360)) } while rng.unit() > density(ang) * 0.9
            let flow: CGFloat = (ang > deg(90) && ang < deg(270)) ? 1 : -1
            let tangent = CGPoint(x: -sin(ang) * flow, y: cos(ang) * flow)
            let normal = CGPoint(x: cos(ang), y: sin(ang))
            let out = rng.chance(0.82)
            let lift = deg(rng.range(14, 48))
            let v = tangent * cos(lift) + normal * (sin(lift) * (out ? 1 : -0.4))
            var L = rng.range(0.15, 0.21) * boost * (out ? 1 : 0.7)
            let p = CGPoint.polar(1.0 + rng.range(-0.02, 0.02), ang)
            while (p + CGPoint.polar(L, v.angle)).length > maxRadius - 0.02 { L *= 0.9 }
            let kind = rng.pick([LeafKind.lance, .ovate, .ovate])
            let spec = kind.spec(L, side: rng.sign(), rng: &rng)
            var tone = rng.pick(LeafTone.all)
            if rng.chance(0.15) { tone = tone.underside }
            let z = out ? 0.6 + Double(i) * 0.002 : 0.1
            ops.append(DrawOp(z: z) { c in Botanical.drawLeaf(c, at: p, angle: v.angle, spec: spec, tone: tone, detail: d, stem: BotanicalPalette.stemSage) })
        }

        // 5) 対角の二つの茂み：同じ一点から扇状に開く花束（カード角の茂みと同じ構図）
        for (bi, center) in [CGFloat(200), CGFloat(38)].enumerated() {
            let ang = deg(center)
            let flow: CGFloat = (ang > deg(90) && ang < deg(270)) ? 1 : -1
            let tangent = CGPoint(x: -sin(ang) * flow, y: cos(ang) * flow)
            let normal = CGPoint(x: cos(ang), y: sin(ang))
            let origin = CGPoint.polar(1.0, ang - flow * deg(10))
            let fan = bi == 0 ? 6 : 5
            for j in 0..<fan {
                let lift = deg(6 + 62 * CGFloat(j) / CGFloat(fan - 1)) + rng.range(-0.06, 0.06)
                let v = tangent * cos(lift) + normal * sin(lift)
                let crossSign: CGFloat = (v.x * tangent.y - v.y * tangent.x) >= 0 ? 1 : -1
                let curl = crossSign * lift * rng.range(0.25, 0.6)
                let leafScale = rng.range(0.11, 0.14) * boost
                var length = rng.range(0.2, 0.3) * sqrt(boost)
                length = fit(origin: origin, angle: v.angle, curl: curl, length: length, leaf: leafScale)
                let terminal: Botanical.Terminal = j == fan - 1 ? .berries : (j % 2 == 0 ? .leaf : (q > 0.5 ? .umbel : .bud))
                let seed = rng.next()
                if CGFloat(j) < CGFloat(fan) * max(0.55, keep) {
                    ops += Botanical.sprigOps(origin: origin, angle: v.angle, length: length, curl: curl, leafScale: leafScale,
                                              terminal: terminal, tone: rng.pick(LeafTone.all), kind: rng.pick([LeafKind.lance, .ovate, .willow]),
                                              z: 0.8 + Double(j) * 0.05, detail: d, seed: seed, leafCount: q < 0.3 ? 2 : nil)
                }
            }
        }

        // 6) かすみ草の房（細密さ・空気感。縮小時は省く）
        if q > 0.45 {
            var placed = 0
            while placed < Int(26 * keep) {
                let ang = deg(rng.range(0, 360))
                guard rng.unit() < density(ang) * 0.85 else { continue }
                let flow: CGFloat = (ang > deg(90) && ang < deg(270)) ? 1 : -1
                let tangent = CGPoint(x: -sin(ang) * flow, y: cos(ang) * flow)
                let normal = CGPoint(x: cos(ang), y: sin(ang))
                let lift = deg(rng.range(18, 70))
                let v = tangent * cos(lift) + normal * sin(lift)
                let origin = CGPoint.polar(1.0 + rng.range(0, 0.03), ang)
                var L = rng.range(0.1, 0.17)
                while (origin + CGPoint.polar(L * 1.1, v.angle)).length > maxRadius { L *= 0.88 }
                let seed = rng.next()
                ops.append(DrawOp(z: rng.chance(0.5) ? -0.3 : 0.7) { c in Botanical.drawSpray(c, at: origin, angle: v.angle, length: L, detail: d, seed: seed) })
                placed += 1
            }
        }

        // 7) 焦点：茂みの山に花・蕾・実を意図して置く（ランダム任せにしない）
        enum Accent { case flower(CGFloat, Bool), bud(Bool), berries(Int), umbel, floret }
        let accents: [(CGFloat, CGFloat, Accent, CGFloat)] = [   // (角度, 半径, 種類, 優先度 0=必須)
            (198, 1.08, .flower(0.088, false), 0), (215, 1.13, .flower(0.06, true), 0.15), (184, 1.12, .bud(false), 0.3),
            (228, 1.07, .berries(4), 0.1), (176, 1.15, .floret, 0.6), (206, 1.19, .floret, 0.7),
            (38, 1.09, .flower(0.08, false), 0), (55, 1.12, .flower(0.052, false), 0.2), (22, 1.1, .berries(3), 0.1),
            (66, 1.15, .bud(true), 0.4), (28, 1.17, .floret, 0.7),
            (118, 1.08, .flower(0.05, true), 0.35), (131, 1.11, .bud(false), 0.6),
            (300, 1.08, .flower(0.042, false), 0.45), (318, 1.09, .berries(3), 0.5), (262, 1.1, .floret, 0.75),
            (160, 1.13, .floret, 0.8), (346, 1.12, .floret, 0.8), (86, 1.13, .floret, 0.85),
        ]
        for (i, acc) in accents.enumerated() where acc.3 <= keep {
            let (ad, rr, kind, _) = acc
            let ang = deg(ad)
            let p = CGPoint.polar(rr, ang)
            let seed = rng.next()
            let tilt = rng.range(0.0, 0.3)
            let rot = rng.range(0, 6.28)
            let z = 2.4 + Double(i) * 0.01
            switch kind {
            case .flower(let r, let lilac):
                let rr2 = min(r * boost, 0.12)
                ops.append(DrawOp(z: z) { c in Botanical.drawFlower(c, at: p, radius: rr2, rotation: rot, tilt: tilt, lilac: lilac, detail: d, seed: seed) })
            case .floret:
                ops.append(DrawOp(z: z) { c in Botanical.drawFlower(c, at: p, radius: 0.03 * boost, rotation: rot, tilt: tilt, lilac: false, detail: d, seed: seed) })
            case .berries(let n):
                let base = CGPoint.polar(1.0, ang)
                ops.append(DrawOp(z: z - 0.2) { c in Botanical.drawBerrySpray(c, at: base, angle: ang + 0.15, size: 0.12 * boost, count: n, detail: d, seed: seed) })
            case .bud(let lilac):
                let base = CGPoint.polar(1.02, ang)
                ops.append(DrawOp(z: z) { c in Botanical.drawBud(c, at: base, angle: ang + 0.45, size: 0.08 * boost, detail: d, lilac: lilac) })
            case .umbel:
                let base = CGPoint.polar(1.0, ang)
                ops.append(DrawOp(z: z - 1.5) { c in Botanical.drawUmbel(c, at: base, angle: ang, size: 0.13, detail: d, seed: seed) })
            }
        }

        // 8) 花粉のような小さな点（極小・グロー無し）
        if q > 0.55 {
            for _ in 0..<22 {
                let ang = deg(rng.range(0, 360))
                let p = CGPoint.polar(1.06 + abs(rng.gauss()) * 0.07, ang)
                let r = rng.range(0.004, 0.008)
                let col = rng.chance(0.5) ? BotanicalPalette.pollen : BotanicalPalette.petal
                ops.append(DrawOp(z: 3) { c in c.fill(disc(p, d.w(r, minPx: 0.6)), with: .color(col.c(0.9))) })
            }
        }
        return ops
    }
}


// MARK: - カードの角の茂み（最初の試作から移植）

enum LeafCardParts {
    /// 長さを縮めて、先端が描画可能範囲（カード＋にじみ代）に収まるようにする。
    static func fit(_ origin: CGPoint, _ angle: CGFloat, _ length: CGFloat, extra: CGFloat, bounds: CGRect) -> CGFloat {
        var len = length
        for _ in 0..<14 {
            let tip = origin + CGPoint.polar(len + extra, angle)
            if bounds.contains(tip) { break }
            len *= 0.88
        }
        return len
    }

    /// 角から内側へ扇状に伸びる茂み。frame と同じ sprig 部品を使う。
    static func cluster(corner: CGPoint, into dir: CGPoint, k: CGFloat, d: Detail, seed: UInt64, big: Bool, tiny: Bool, bounds: CGRect) -> [DrawOp] {
        var rng = SeededRNG(seed)
        var ops: [DrawOp] = []
        let base = atan2(dir.y, dir.x)
        let n = big ? 9 : 6
        let lod: CGFloat = tiny ? 1.55 : 1
        let kinds: [LeafKind] = [.lance, .ovate, .lance, .willow, .round, .ovate]
        if !tiny {
            // 背景の淡い葉（水彩の奥行き）
            for i in 0..<(big ? 8 : 4) {
                let a = base + rng.range(-0.8, 0.8)
                let p = corner + CGPoint.polar(rng.range(26, 72) * k, a)
                let spec = rng.pick([LeafKind.ovate, .lance]).spec(rng.range(22, 34) * k, side: rng.sign(), rng: &rng)
                let tone = rng.pick(LeafTone.all).faded(toward: Botanical.toneScheme.surface, 0.58)
                let ang = a + rng.range(-0.7, 0.7)
                ops.append(DrawOp(z: -1 + Double(i) * 0.01) { c in Botanical.drawLeaf(c, at: p, angle: ang, spec: spec, tone: tone, detail: d, alpha: 0.55) })
            }
        }
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            // 右下は上（本文側）へ伸ばしすぎず、空いている下辺側へ多く流す
            let spread = big ? deg(-64 + 100 * t) : (t - 0.5) * deg(106)
            let a = base + spread + rng.range(-0.08, 0.08)
            let alongEdge = abs(spread) > deg(36)
            let kind = rng.pick(kinds)
            let leafScale = rng.range(22, 31) * k * (alongEdge ? 0.84 : 1.08) * lod
            var length = (alongEdge ? rng.range(66, 100) : rng.range(32, 56)) * k * (big ? 1 : 0.85) * lod
            if big && spread > deg(20) { length *= 0.72 }
            if tiny { length *= 0.5 }  // 一覧サイズでは茎を短く、葉を寄せて「茂み」の塊として見せる
            let curl = -spread * rng.range(0.25, 0.5)
            let origin = corner + CGPoint.polar(rng.range(0, 8) * k, a + .pi)
            length = fit(origin, a + curl * 0.6, length, extra: leafScale * 0.9, bounds: bounds)
            let roll = rng.unit()
            let terminal: Botanical.Terminal = roll < 0.24 ? .berries : (roll < 0.34 ? .flower : (roll < 0.44 ? .bud : (roll < 0.5 && !tiny ? .umbel : .leaf)))
            ops += Botanical.sprigOps(origin: origin, angle: a, length: length, curl: curl,
                                      leafScale: leafScale, terminal: terminal, tone: rng.pick(LeafTone.all), kind: kind,
                                      z: Double(i % 3) * 0.3 + Double(rng.unit()), detail: d, seed: rng.next(), alpha: 0.93, leafCount: tiny ? 3 : nil)
        }
        // 角を覆い、パネルの縁からはみ出す大きな葉
        for j in 0..<(big ? 5 : 3) {
            let a = base + .pi + rng.range(-1.0, 1.0)
            let origin = corner + CGPoint.polar(rng.range(6, 16) * k, base)
            var L = rng.range(30, 44) * k * lod
            L = fit(origin, a, L, extra: 0, bounds: bounds)
            let kind = rng.pick([LeafKind.ovate, .lance])
            let spec = kind.spec(L, side: rng.sign(), rng: &rng)
            var tone = rng.pick(LeafTone.all)
            if j == 1 { tone = tone.underside }
            ops.append(DrawOp(z: 1.4 + Double(j) * 0.02) { c in Botanical.drawLeaf(c, at: origin, angle: a, spec: spec, tone: tone, detail: d, stem: BotanicalPalette.stemSage) })
        }
        // 花の焦点
        let fp = corner + CGPoint.polar((big ? 30 : 22) * k, base + rng.range(-0.3, 0.3))
        let seedF = rng.next()
        ops.append(DrawOp(z: 3) { c in Botanical.drawFlower(c, at: fp, radius: (big ? 8.5 : 6.8) * k * lod, rotation: 0.4, tilt: 0.16, lilac: false, detail: d, seed: seedF) })
        if big {
            let fp2 = corner + CGPoint.polar(56 * k, base + 0.55)
            let seedG = rng.next()
            ops.append(DrawOp(z: 3) { c in Botanical.drawFlower(c, at: fp2, radius: 5.8 * k * lod, rotation: 1.1, tilt: 0.32, lilac: true, detail: d, seed: seedG) })
            let fp3 = corner + CGPoint.polar(44 * k, base - 0.62)
            ops.append(DrawOp(z: 2.9) { c in Botanical.drawBud(c, at: fp3, angle: base - 0.9, size: 7 * k * lod, detail: d) })
        } else {
            let fp3 = corner + CGPoint.polar(40 * k, base + 0.5)
            ops.append(DrawOp(z: 2.9) { c in Botanical.drawBud(c, at: fp3, angle: base + 0.3, size: 6 * k * lod, detail: d, lilac: true) })
        }
        if !tiny {
            for _ in 0..<(big ? 12 : 7) {
                let p = corner + CGPoint.polar(rng.range(20, 95) * k, base + rng.range(-0.8, 0.8))
                let r = rng.range(0.5, 1.1) * k
                ops.append(DrawOp(z: 3.5) { c in c.fill(disc(p, r), with: .color(RGB(0xFFFDF4).c(0.85))) })
            }
        }
        return ops
    }
}

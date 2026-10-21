// 織目：平織りの帯（経糸と緯糸が交互に潜る）と、クロスステッチの図案。糸枠（撚り紐）とは「織る／刺す」で描き分ける。
import SwiftUI

enum Weave {
    static func colors(_ s: DecoScheme, _ pal: ItemPalette) -> (warp: RGB, weft: RGB, shade: RGB) {
        if s.isDark { return (pal.primary, pal.secondary.mix(.white, 0.25), RGB(0x1A1430)) }
        return (pal.primary.withLightness(0.6, saturationBoost: 0.85), pal.secondary.withLightness(0.84), RGB(0x8A6F80))
    }

    /// 一つのクロスステッチ（×）。上の糸がわずかに太く明るい
    static func xStitch(_ ctx: GraphicsContext, at p: CGPoint, size h: CGFloat, color: RGB, d: Detail) {
        var a = Path(); a.move(to: CGPoint(x: p.x - h, y: p.y + h)); a.addLine(to: CGPoint(x: p.x + h, y: p.y - h))
        var b = Path(); b.move(to: CGPoint(x: p.x - h, y: p.y - h)); b.addLine(to: CGPoint(x: p.x + h, y: p.y + h))
        let w = d.w(h * 0.62, minPx: 0.5)
        ctx.stroke(a, with: .color(color.mix(.black, 0.18).c(0.95)), style: StrokeStyle(lineWidth: w, lineCap: .round))
        ctx.stroke(b, with: .color(color.c()), style: StrokeStyle(lineWidth: w, lineCap: .round))
        ctx.stroke(b, with: .color(RGB.white.c(0.35)), style: StrokeStyle(lineWidth: w * 0.3, lineCap: .round))
    }

    /// 図案（文字列の格子：A=主色, B=副色, G=緑, .=空き）をクロスステッチで刺す
    static func pattern(_ ctx: GraphicsContext, _ rows: [String], origin: CGPoint, cell: CGFloat, colors: [Character: RGB], rotation: CGFloat = 0, d: Detail) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let col = colors[ch] else { continue }
                let p = origin + CGPoint(x: CGFloat(x) * cell, y: CGFloat(y) * cell).rotated(rotation)
                xStitch(ctx, at: p, size: cell * 0.36, color: col, d: d)
            }
        }
    }

    static let flower: [String] = [
        "..A.A..",
        ".AABAA.",
        "AABBBAA",
        ".ABBBA.",
        "AABBBAA",
        ".AABAA.",
        "..AGA..",
        "...G...",
        "..GGG..",
    ]
    static let diamond: [String] = [
        "...A...",
        "..ABA..",
        ".ABGBA.",
        "ABG.GBA",
        ".ABGBA.",
        "..ABA..",
        "...A...",
    ]
}

enum LinenMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let col = Weave.colors(s, pal)
        let inner: CGFloat = 0.965, outer: CGFloat = 1.065 + 0.02 * (1 - q)
        let rows = q < 0.4 ? 2 : 3
        let cols = q < 0.4 ? 36 : 60
        // 1) 平織りの帯
        ops.append(DrawOp(z: 0) { c in
            var band = Path(); band.addPath(disc(.zero, outer)); band.addPath(disc(.zero, inner))
            c.fill(band, with: .color(col.shade.c(s.isDark ? 0.6 : 0.25)), style: FillStyle(eoFill: true))
            let dr = (outer - inner) / CGFloat(rows)
            for j in 0..<rows {
                let r0 = inner + dr * CGFloat(j), r1 = r0 + dr
                for i in 0..<cols {
                    let a0 = CGFloat(i) / CGFloat(cols) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(cols) * 2 * .pi
                    let over = (i + j) % 2 == 0     // 経糸が上か
                    let gap = (a1 - a0) * 0.1, rgap = dr * 0.1
                    var cell = Path()
                    cell.addArc(center: .zero, radius: r1 - rgap, startAngle: .radians(a0 + gap), endAngle: .radians(a1 - gap), clockwise: false)
                    cell.addArc(center: .zero, radius: r0 + rgap, startAngle: .radians(a1 - gap), endAngle: .radians(a0 + gap), clockwise: true)
                    cell.closeSubpath()
                    let mid = CGPoint.polar((r0 + r1) / 2, (a0 + a1) / 2)
                    let base = over ? col.warp : col.weft
                    // 上を通る糸は膨らみ（中央が明るく、端が沈む）
                    let start = over ? CGPoint.polar((r0 + r1) / 2, a0) : CGPoint.polar(r0, (a0 + a1) / 2)
                    let end = over ? CGPoint.polar((r0 + r1) / 2, a1) : CGPoint.polar(r1, (a0 + a1) / 2)
                    c.fill(cell, with: .linearGradient(Gradient(stops: [
                        .init(color: base.mix(col.shade, 0.35).c(), location: 0), .init(color: base.mix(.white, 0.25).c(), location: 0.5),
                        .init(color: base.mix(col.shade, 0.35).c(), location: 1),
                    ]), startPoint: start, endPoint: end))
                    _ = mid
                }
            }
            // 耳（両端の縫い止め）
            c.stroke(disc(.zero, outer), with: .color(col.warp.mix(col.shade, 0.3).c()), lineWidth: d.w(0.004 * boost, minPx: 0.7))
            c.stroke(disc(.zero, inner), with: .color(col.warp.mix(col.shade, 0.3).c()), lineWidth: d.w(0.004 * boost, minPx: 0.7))
        })
        // 2) 外側のランニングステッチ
        if q > 0.3 {
            ops.append(DrawOp(z: 0.2) { c in
                c.stroke(disc(.zero, outer + 0.04), with: .color(col.weft.c(0.9)), style: StrokeStyle(lineWidth: d.w(0.006, minPx: 0.6), lineCap: .round, dash: [0.03, 0.02]))
            })
        }
        // 3) クロスステッチの小さな図案（対角に二つ）
        let green = s.isDark ? RGB(0x8FD9B6) : RGB(0x3E8E6E)
        let stitch: [Character: RGB] = ["A": s.isDark ? pal.primary : pal.line(s), "B": s.isDark ? RGB(0xFFB3C7) : RGB(0xD45C84), "G": green]
        for (i, ad) in [CGFloat(226), CGFloat(44)].enumerated() where q > 0.3 || i == 0 {
            let ang = deg(ad)
            let cell = 0.022 * (q < 0.4 ? 1.3 : 1)
            let center = CGPoint.polar(outer + 0.1 + cell * 0.5, ang)
            ops.append(DrawOp(z: 0.5) { c in
                // 図案の地（小さな刺繍布のパッチ）
                var patch = c
                patch.translateBy(x: center.x, y: center.y)
                patch.rotate(by: .radians(ang + .pi / 2))
                let w = cell * 7.6, h = cell * 7.6
                let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                patch.fill(Path(roundedRect: rect, cornerRadius: cell), with: .color((s.isDark ? RGB(0x241D3D) : RGB(0xFFFBF4)).c()))
                patch.stroke(Path(roundedRect: rect, cornerRadius: cell), with: .color(col.warp.c(0.8)),
                             style: StrokeStyle(lineWidth: d.w(0.004, minPx: 0.5), dash: [0.012, 0.008]))
                Weave.pattern(patch, Weave.diamond, origin: CGPoint(x: -cell * 3, y: -cell * 3), cell: cell, colors: stitch, d: d)
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let col = Weave.colors(s, pal)
        CardBase.drawGround(ctx, cc, seed: 0x1E)
        var inner = ctx
        inner.clip(to: cc.shape)
        // 麻布の織り目：細かな経緯の格子と、ところどころの太い節
        if !cc.tiny {
            var weave = Path()
            var x = cc.rect.minX
            var rng = SeededRNG(0x1F)
            while x < cc.rect.maxX { weave.move(to: CGPoint(x: x, y: cc.rect.minY)); weave.addLine(to: CGPoint(x: x, y: cc.rect.maxY)); x += 1.8 * k * rng.range(0.85, 1.15) }
            var y = cc.rect.minY
            while y < cc.rect.maxY { weave.move(to: CGPoint(x: cc.rect.minX, y: y)); weave.addLine(to: CGPoint(x: cc.rect.maxX, y: y)); y += 1.8 * k * rng.range(0.85, 1.15) }
            inner.stroke(weave, with: .color((s.isDark ? RGB.white : col.shade).c(s.isDark ? 0.04 : 0.06)), lineWidth: d.w(0.45 * k, minPx: 0.5))
            for _ in 0..<40 {
                let p = CGPoint(x: cc.rect.minX + rng.unit() * cc.rect.width, y: cc.rect.minY + rng.unit() * cc.rect.height)
                var slub = Path(); slub.move(to: p); slub.addLine(to: CGPoint(x: p.x + rng.range(6, 16) * k, y: p.y))
                inner.stroke(slub, with: .color((s.isDark ? RGB.white : col.shade).c(0.06)), lineWidth: d.w(0.8 * k, minPx: 0.5))
            }
        }
        // 下辺のクロスステッチの帯（本文の下を避けて左右に）
        let green = s.isDark ? RGB(0x8FD9B6) : RGB(0x3E8E6E)
        let stitch: [Character: RGB] = ["A": s.isDark ? pal.primary : pal.line(s), "B": s.isDark ? RGB(0xFFB3C7) : RGB(0xD45C84), "G": green]
        let cell = (cc.tiny ? 4.2 : 3.2) * k
        let bandY = cc.rect.maxY - 18 * k
        var bx = cc.rect.minX + 18 * k
        var i = 0
        while bx < cc.rect.maxX - 18 * k {
            let ch: Character = i % 4 == 0 ? "B" : (i % 2 == 0 ? "A" : "G")
            if !(bx > cc.rect.minX + 100 * k && bx < cc.rect.maxX - 110 * k) || cc.tiny {
                Weave.xStitch(ctx, at: CGPoint(x: bx, y: bandY + (i % 2 == 0 ? 0 : -cell)), size: cell * 0.36, color: stitch[ch]!, d: d)
            }
            bx += cell
            i += 1
        }
        // 角の図案
        Weave.pattern(ctx, Weave.flower, origin: CGPoint(x: cc.rect.maxX - 34 * k, y: cc.rect.maxY - 54 * k), cell: cell, colors: stitch, d: d)
        if !cc.tiny {
            Weave.pattern(ctx, Weave.diamond, origin: CGPoint(x: cc.rect.minX + 14 * k, y: cc.rect.minY + 14 * k), cell: cell * 0.8, colors: stitch, d: d)
            Weave.pattern(ctx, Weave.diamond, origin: CGPoint(x: cc.rect.maxX - 34 * k, y: cc.rect.minY + 14 * k), cell: cell * 0.8, colors: stitch, d: d)
        }
        // ステッチの枠
        let stitchRect = cc.rect.insetBy(dx: 12 * k, dy: 12 * k)
        ctx.stroke(Path(roundedRect: stitchRect, cornerRadius: max(2, cc.radius - 9 * k), style: .continuous),
                   with: .color(col.warp.mix(col.shade, s.isDark ? 0 : 0.2).c(0.9)), style: StrokeStyle(lineWidth: d.w(0.9 * k, minPx: 0.6), lineCap: .round, dash: [3.2 * k, 2.2 * k]))
        CardBase.drawRule(ctx, cc, gap: 20) { c, p, flip in
            Weave.xStitch(c, at: CGPoint(x: p.x, y: p.y + (flip ? -0.5 : 0.5) * k), size: 2.2 * k, color: stitch["B"]!, d: d)
        }
    }
}

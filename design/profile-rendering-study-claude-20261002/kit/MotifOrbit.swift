// 軌跡線：傾いた楕円軌道を走る小さな天体と、その後ろに伸びて消える光の軌跡。方眼と目盛りで「図」の静けさを足す。
import SwiftUI

enum Orbit {
    /// 楕円軌道上の点（回転 rot、半径 rx/ry）
    static func point(_ t: CGFloat, rx: CGFloat, ry: CGFloat, rot: CGFloat, center: CGPoint = .zero) -> CGPoint {
        center + CGPoint(x: rx * cos(t), y: ry * sin(t)).rotated(rot)
    }

    /// 軌道（細線）＋天体の後ろに伸びる軌跡（太く明るい→細く消える）＋天体
    static func trail(_ ctx: GraphicsContext, rx: CGFloat, ry: CGFloat, rot: CGFloat, center: CGPoint = .zero,
                      body: CGFloat, length: CGFloat, dir: CGFloat, width: CGFloat, bodyR: CGFloat,
                      color: RGB, glowColor: RGB, s: DecoScheme, d: Detail, orbitAlpha: Double, minPx: CGFloat = 0.5) {
        var orbit = Path()
        orbit.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        var oc = ctx
        oc.translateBy(x: center.x, y: center.y)
        oc.rotate(by: .radians(rot))
        oc.stroke(orbit, with: .color(color.c(orbitAlpha)), lineWidth: d.w(width * 0.28, minPx: minPx))
        // 軌跡
        let n = 60
        var pts: [CGPoint] = [], ws: [CGFloat] = [], als: [Double] = []
        for i in 0...n {
            let u = CGFloat(i) / CGFloat(n)          // 0=尾, 1=天体
            let t = body - dir * length * (1 - u)
            pts.append(point(t, rx: rx, ry: ry, rot: rot, center: center))
            ws.append(d.w(width * pow(u, 1.6), minPx: minPx * 0.6))
            als.append(Double(pow(u, 1.3)))
        }
        var tc = ctx
        if s.isDark { tc.blendMode = .plusLighter }
        tc.drawLayer { l in
            l.addFilter(.blur(radius: width * 0.9))
            drawVaryingStroke(l, points: pts, widths: ws.map { $0 * 2.6 }, alphas: als.map { $0 * (s.isDark ? 0.45 : 0.3) }, color: glowColor)
        }
        drawVaryingStroke(tc, points: pts, widths: ws, alphas: als.map { $0 * 0.9 }, color: color)
        drawVaryingStroke(tc, points: pts, widths: ws.map { $0 * 0.35 }, alphas: als.map { $0 * 0.9 }, color: s.isDark ? RGB.white : glowColor)
        // 天体
        let p = point(body, rx: rx, ry: ry, rot: rot, center: center)
        if s.isDark {
            tc.fill(disc(p, bodyR * 3), with: .radialGradient(Gradient(colors: [glowColor.c(0.45), glowColor.c(0)]), center: p, startRadius: 0, endRadius: bodyR * 3))
        }
        ctx.fill(disc(p, bodyR), with: .radialGradient(Gradient(colors: [RGB.white.c(), glowColor.c(), color.c()]),
                                                      center: p - CGPoint(x: bodyR * 0.3, y: bodyR * 0.3), startRadius: 0, endRadius: bodyR * 1.3))
        ctx.stroke(disc(p, bodyR), with: .color(color.mix(.black, 0.2).c(0.6)), lineWidth: d.w(bodyR * 0.12, minPx: 0.35))
    }
}

enum OrbitMotif: DecoMotif {
    static func frame(_ d: Detail, _ s: DecoScheme, _ pal: ItemPalette) -> [DrawOp] {
        var ops: [DrawOp] = []
        let q = d.quality, boost = d.boost
        let a = pal.line(s), b = pal.line2(s)
        let hiA = s.isDark ? pal.primary.mix(.white, 0.35) : pal.line(s).mix(.white, 0.2)
        let hiB = s.isDark ? pal.secondary.mix(.white, 0.35) : pal.line2(s).mix(.white, 0.2)

        // 1) 図の地：基準の輪・点線の外周・極座標の目盛り
        ops.append(DrawOp(z: 0) { c in
            c.stroke(disc(.zero, 1.0), with: .color(a.c(0.9)), lineWidth: d.w(0.007 * boost, minPx: 1.0))
            if q > 0.3 {
                c.stroke(disc(.zero, 0.955), with: .color(a.c(0.35)), lineWidth: d.w(0.002, minPx: 0.4))
                c.stroke(disc(.zero, 1.2), with: .color(b.c(0.5)), style: StrokeStyle(lineWidth: d.w(0.005, minPx: 0.7), lineCap: .round, dash: [0, 0.03]))
                var ticks = Path()
                for i in 0..<72 {
                    let ang = CGFloat(i) / 72 * 2 * .pi
                    let long = i % 6 == 0
                    ticks.move(to: CGPoint.polar(1.0, ang))
                    ticks.addLine(to: CGPoint.polar(1.0 + (long ? 0.04 : 0.018), ang))
                }
                c.stroke(ticks, with: .color(a.c(0.55)), lineWidth: d.w(0.0028, minPx: 0.45))
            }
        })
        // 2) 軌道と軌跡：三本。傾きを変えて交差させる
        let orbits: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [   // rx, ry, 回転, 天体の位置, 軌跡の長さ, 主色か
            (1.16, 0.965, deg(28), deg(205), 2.2, true), (1.13, 0.97, deg(-36), deg(40), 1.9, false), (1.24, 1.06, deg(80), deg(300), 1.4, true),
        ]
        for (i, o) in orbits.enumerated() where q > 0.35 || i < 2 {
            let (rx, ry, rot, body, len, primary) = o
            ops.append(DrawOp(z: 0.3 + Double(i) * 0.01) { c in
                var cc = c
                var clip = Path(); clip.addPath(disc(.zero, 1.32)); clip.addPath(disc(.zero, 0.94))
                cc.clip(to: clip, style: FillStyle(eoFill: true))
                Orbit.trail(cc, rx: rx, ry: ry, rot: rot, body: body, length: len, dir: i % 2 == 0 ? 1 : -1, width: 0.055 * boost,
                            bodyR: (i == 0 ? 0.07 : 0.055) * boost, color: primary ? a : b, glowColor: primary ? hiA : hiB, s: s, d: d,
                            orbitAlpha: q < 0.4 ? 0.7 : 0.55, minPx: q < 0.4 ? 0.9 : 0.6)
            })
        }
        // 3) 交点の印と小さな輪付き天体
        if q > 0.45 {
            ops.append(DrawOp(z: 0.8) { c in
                for ang in [CGFloat(118), 332] {
                    let p = CGPoint.polar(1.2, deg(ang))
                    c.fill(disc(p, 0.012), with: .color(b.c()))
                    var cc = c
                    cc.translateBy(x: p.x, y: p.y)
                    cc.rotate(by: .radians(deg(-20)))
                    cc.stroke(Path(ellipseIn: CGRect(x: -0.03, y: -0.008, width: 0.06, height: 0.016)), with: .color(a.c(0.8)), lineWidth: d.w(0.003, minPx: 0.4))
                }
                var cross = Path()
                for ang in [CGFloat(0), 90, 180, 270] {
                    let p = CGPoint.polar(1.0, deg(ang))
                    cross.addEllipse(in: CGRect(x: p.x - 0.012, y: p.y - 0.012, width: 0.024, height: 0.024))
                }
                c.fill(cross, with: .color((s.isDark ? RGB(0x17132A) : RGB.white).c()))
                c.stroke(cross, with: .color(a.c(0.9)), lineWidth: d.w(0.004, minPx: 0.5))
            })
        }
        return ops
    }

    static func card(_ ctx: GraphicsContext, _ cc: CardContext) {
        let k = cc.k, s = cc.scheme, pal = cc.pal, d = cc.d
        let a = pal.line(s), b = pal.line2(s)
        let hiA = s.isDark ? pal.primary.mix(.white, 0.35) : pal.line(s).mix(.white, 0.2)
        let hiB = s.isDark ? pal.secondary.mix(.white, 0.35) : pal.line2(s).mix(.white, 0.2)
        CardBase.drawGround(ctx, cc, seed: 0x0B)
        var inner = ctx
        inner.clip(to: cc.shape)
        // 方眼：角から現れて中央へ消える
        if !cc.tiny {
            inner.drawLayer { l in
                var grid = Path()
                let step = 9 * k
                var x = cc.rect.minX
                while x < cc.rect.maxX { grid.move(to: CGPoint(x: x, y: cc.rect.minY)); grid.addLine(to: CGPoint(x: x, y: cc.rect.maxY)); x += step }
                var y = cc.rect.minY
                while y < cc.rect.maxY { grid.move(to: CGPoint(x: cc.rect.minX, y: y)); grid.addLine(to: CGPoint(x: cc.rect.maxX, y: y)); y += step }
                l.stroke(grid, with: .color(a.c(s.isDark ? 0.22 : 0.2)), lineWidth: d.w(0.35 * k, minPx: 0.5))
                l.blendMode = .destinationIn
                l.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [RGB.white.c(1), RGB.white.c(0)]), center: cc.br, startRadius: 0, endRadius: 150 * k))
            }
            inner.drawLayer { l in
                var grid = Path()
                let step = 9 * k
                var x = cc.rect.minX
                while x < cc.rect.minX + 90 * k { grid.move(to: CGPoint(x: x, y: cc.rect.minY)); grid.addLine(to: CGPoint(x: x, y: cc.rect.minY + 90 * k)); x += step }
                var y = cc.rect.minY
                while y < cc.rect.minY + 90 * k { grid.move(to: CGPoint(x: cc.rect.minX, y: y)); grid.addLine(to: CGPoint(x: cc.rect.minX + 90 * k, y: y)); y += step }
                l.stroke(grid, with: .color(b.c(s.isDark ? 0.2 : 0.18)), lineWidth: d.w(0.35 * k, minPx: 0.5))
                l.blendMode = .destinationIn
                l.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [RGB.white.c(1), RGB.white.c(0)]), center: cc.tl, startRadius: 0, endRadius: 80 * k))
            }
        }
        // 右下を中心にした大きな軌道（本文列の手前で切れる）
        let center = CGPoint(x: cc.rect.maxX + 10 * k, y: cc.rect.maxY + 16 * k)
        var oc = inner
        oc.clip(to: Path(cc.rect.insetBy(dx: 4 * k, dy: 4 * k)))
        let orbits: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
            (120, 70, deg(-12), deg(240), 1.5, true), (92, 50, deg(-28), deg(250), 1.3, false), (150, 92, deg(-6), deg(228), 1.0, true),
        ]
        for (i, o) in orbits.enumerated() where !cc.tiny || i < 2 {
            let (rx, ry, rot, body, len, primary) = o
            Orbit.trail(oc, rx: rx * k, ry: ry * k, rot: rot, center: center, body: body, length: len, dir: 1, width: 4.2 * k,
                        bodyR: (i == 0 ? 5.6 : 4.2) * k, color: primary ? a : b, glowColor: primary ? hiA : hiB, s: s, d: d, orbitAlpha: 0.5)
        }
        // 左上の小さな軌道
        if !cc.tiny {
            Orbit.trail(inner, rx: 44 * k, ry: 26 * k, rot: deg(24), center: CGPoint(x: cc.rect.minX + 6 * k, y: cc.rect.minY + 4 * k), body: deg(70),
                        length: 1.3, dir: 1, width: 2.8 * k, bodyR: 3.4 * k, color: b, glowColor: hiB, s: s, d: d, orbitAlpha: 0.5)
        }
        CardBase.drawRule(ctx, cc, gap: 24) { c, p, flip in
            c.fill(disc(p, 2.2 * k), with: .color((s.isDark ? RGB(0x17132A) : RGB.white).c()))
            c.stroke(disc(p, 2.2 * k), with: .color(a.c()), lineWidth: d.w(0.8 * k, minPx: 0.7))
            var cc2 = c
            cc2.translateBy(x: p.x, y: p.y)
            cc2.rotate(by: .radians(deg(-20)))
            cc2.stroke(Path(ellipseIn: CGRect(x: -6 * k, y: -1.8 * k, width: 12 * k, height: 3.6 * k)), with: .color(b.c(0.8)), lineWidth: d.w(0.6 * k, minPx: 0.5))
        }
    }
}

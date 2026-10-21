// カードの共通土台：地・空気・粒・縁・二重罫・頂部/底部の飾り。全モチーフが同じ文法を使い、
// 「一つのコレクション」に見えるようにする。モチーフ固有の装飾はこの上に角と縁だけへ載せる。
import SwiftUI

struct CardContext {
    let size: CGSize
    let k: CGFloat
    let rect: CGRect        // パネル
    let radius: CGFloat
    let bleed: CGFloat
    let bounds: CGRect      // 描いてよい範囲（レイアウト＋にじみ代）
    let scheme: DecoScheme
    let pal: ItemPalette
    let d: Detail           // pt 座標で描くので pxPerUnit = displayScale
    let tiny: Bool          // 一覧サムネイル級
    let textScale: CGFloat  // Dynamic Type に応じた本文の大きさ（標準=1）

    /// ProfileHero の本文列（ID〜自己紹介2行）。装飾はここを避ける。
    /// 大きな文字でカードが縦に伸びた分だけ下へ伸ばす（伸びた本文が角の装飾と重ならないように）。
    /// さらに文字サイズ（Dynamic Type）に合わせて下へ伸ばす：画像では出来ない、コード描画ならではの調整。
    var textZone: CGRect {
        let extra = max(0, size.height - 222 * k)
        // 標準では下辺の装飾のために 40pt 残す。アクセシビリティサイズでは本文を優先し、下の罫の手前まで伸ばす
        let floor = textScale > 1.2 ? 14 * k : 40 * k
        let h = min(rect.maxY - floor - 34 * k, 138 * k * textScale + extra)
        return CGRect(x: 144 * k, y: 34 * k, width: 158 * k, height: h)
    }
    /// アバター＋操作ボタンの列
    var avatarZone: CGRect { CGRect(x: 28 * k, y: 16 * k, width: 112 * k, height: 150 * k) }
    var tl: CGPoint { CGPoint(x: rect.minX, y: rect.minY) }
    var tr: CGPoint { CGPoint(x: rect.maxX, y: rect.minY) }
    var bl: CGPoint { CGPoint(x: rect.minX, y: rect.maxY) }
    var br: CGPoint { CGPoint(x: rect.maxX, y: rect.maxY) }
    var dark: Bool { scheme.isDark }

    init(size: CGSize, scale: CGFloat, bleed: CGFloat, scheme: DecoScheme, pal: ItemPalette, textScale: CGFloat = 1) {
        self.size = size
        self.textScale = textScale
        k = min(size.width / 342, size.height / 222)
        let inset = max(2, 6 * k)
        rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        radius = max(4, 17 * k)
        self.bleed = bleed
        bounds = CGRect(origin: .zero, size: size).insetBy(dx: -bleed + 1, dy: -bleed + 1)
        self.scheme = scheme
        self.pal = pal
        d = Detail(pxPerUnit: scale)
        tiny = size.width < 160
    }

    var shape: Path { Path(roundedRect: rect, cornerRadius: radius, style: .continuous) }
}

enum CardBase {
    /// 地：影 → 面のグラデ → 角の空気（宵=発光の溜まり／曙=淡い顔料のにじみ）→ 粒 → 内縁 → 外縁とリム
    static func drawGround(_ ctx: GraphicsContext, _ cc: CardContext, seed: UInt64,
                           airAnchors: [(CGPoint, CGFloat, RGB, Double)]? = nil) {
        let k = cc.k
        let shape = cc.shape
        let s = cc.scheme

        // 影（曙：暖色で長く柔らかい golden hour の影／宵：わずかに浮かせる）
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: (s.isDark ? 8 : 7) * k))
            l.translateBy(x: 0, y: (s.isDark ? 4 : 3.5) * k)
            l.fill(shape, with: .color(s.shadow.c(s.isDark ? 0.45 : 0.24)))
        }

        // 地：テーマの面をアイテム色で染める（各カードを「別の色の薄明かりの空」にして、一覧で見分けられるようにする）
        if s.isDark {
            ctx.fill(shape, with: .linearGradient(Gradient(stops: [
                .init(color: s.surface.mix(cc.pal.primary, 0.26).c(), location: 0),
                .init(color: s.surface.mix(cc.pal.primary.mix(cc.pal.secondary, 0.5), 0.12).c(), location: 0.5),
                .init(color: s.elevated.mix(cc.pal.secondary, 0.22).c(), location: 1),
            ]), startPoint: CGPoint(x: cc.rect.minX, y: cc.rect.minY), endPoint: CGPoint(x: cc.rect.maxX, y: cc.rect.maxY)))
        } else {
            ctx.fill(shape, with: .linearGradient(Gradient(stops: [
                .init(color: s.surface.mix(cc.pal.primary, 0.14).c(), location: 0),
                .init(color: s.surface.mix(cc.pal.primary, 0.05).c(), location: 0.45),
                .init(color: s.cardBottom.mix(cc.pal.secondary, 0.16).c(), location: 1),
            ]), startPoint: CGPoint(x: cc.rect.minX, y: cc.rect.minY), endPoint: CGPoint(x: cc.rect.maxX, y: cc.rect.maxY)))
        }

        var inner = ctx
        inner.clip(to: shape)

        // 角の空気
        let anchors = airAnchors ?? [
            (cc.tl, 0.62, cc.pal.primary, s.isDark ? 0.24 : 0.16),
            (cc.br, 0.66, cc.pal.secondary, s.isDark ? 0.2 : 0.14),
        ]
        var rng = SeededRNG(seed)
        inner.drawLayer { l in
            l.addFilter(.blur(radius: max(1, (s.isDark ? 10 : 7) * k)))
            for (p, reach, color, alpha) in anchors {
                let R = cc.rect.width * reach
                l.fill(Path(cc.rect), with: .radialGradient(Gradient(colors: [color.c(alpha), color.c(alpha * 0.45), color.c(0)]),
                                                            center: p, startRadius: 0, endRadius: R * 0.62))
                // 形のある空気（不規則なにじみ）を少し
                for _ in 0..<(cc.tiny ? 2 : 6) {
                    let q = p + CGPoint(x: (p.x < cc.rect.midX ? 1 : -1) * rng.range(10, 120) * k,
                                        y: (p.y < cc.rect.midY ? 1 : -1) * rng.range(6, 70) * k)
                    let blob = organicBlob(radius: rng.range(18, 46) * k, rng: &rng, points: 12, roughness: rng.range(0.15, 0.3), center: q)
                    l.fill(blob, with: .color(color.c(alpha * Double(rng.range(0.35, 0.7)))))
                }
            }
        }

        // 上端のつや（宵＝ガラス、曙＝朝の光）
        inner.fill(Path(cc.rect), with: .linearGradient(Gradient(colors: [
            (s.isDark ? RGB.white : RGB(0xFFF4DE)).c(s.isDark ? 0.055 : 0.5), RGB.white.c(0),
        ]), startPoint: CGPoint(x: 0, y: cc.rect.minY), endPoint: CGPoint(x: 0, y: cc.rect.minY + cc.rect.height * 0.45)))

        // フィルムグレイン（doc13 §4：数%）
        if !cc.tiny {
            var g = SeededRNG(seed ^ 0x9E37)
            let px = 1 / cc.d.pxPerUnit
            let n = Int(cc.rect.width * cc.rect.height / 14)
            for _ in 0..<n {
                let p = CGPoint(x: cc.rect.minX + g.unit() * cc.rect.width, y: cc.rect.minY + g.unit() * cc.rect.height)
                let light = g.chance(0.5)
                let a = Double(g.range(0.025, 0.07)) * (s.isDark ? 1.0 : 0.6)
                inner.fill(disc(p, px * g.range(0.5, 1.1)), with: .color((light ? RGB.white : (s.isDark ? RGB.black : RGB(0x6B4A2E))).c(a)))
            }
        }

        // 内縁の陰（奥行き）
        let edgeTone = s.isDark ? RGB.black : cc.pal.line(s)
        inner.stroke(shape, with: .color(edgeTone.c(s.isDark ? 0.14 : 0.035)), lineWidth: 26 * k)
        inner.stroke(shape, with: .color(edgeTone.c(s.isDark ? 0.16 : 0.04)), lineWidth: 10 * k)

        // 外縁とリムライト
        if s.isDark {
            ctx.stroke(shape, with: .color(cc.pal.primary.mix(.white, 0.35).c(0.3)), lineWidth: cc.d.w(0.8 * k, minPx: 1))
        } else {
            ctx.stroke(shape, with: .color(s.divider.mix(cc.pal.line(s), 0.3).c()), lineWidth: cc.d.w(0.8 * k, minPx: 1))
        }
        var rim = Path()
        rim.addRoundedRect(in: cc.rect.insetBy(dx: 0.7 * k, dy: 0.7 * k), cornerSize: CGSize(width: cc.radius, height: cc.radius), style: .continuous)
        var rc = ctx
        rc.clip(to: Path(CGRect(x: cc.rect.minX, y: cc.rect.minY - 2, width: cc.rect.width, height: cc.radius + 4 * k)))
        rc.stroke(rim, with: .linearGradient(Gradient(colors: [s.rim.c(0), s.rim.c(s.isDark ? 0.22 : 0.6), s.rim.c(0)]),
                                             startPoint: CGPoint(x: cc.rect.minX, y: 0), endPoint: CGPoint(x: cc.rect.maxX, y: 0)),
                  lineWidth: cc.d.w(1.1 * k, minPx: 1))
    }

    /// 二重罫と頂部・底部の飾り。罫の色はアイテムの主線色。
    static func drawRule(_ ctx: GraphicsContext, _ cc: CardContext, gap: CGFloat = 30, inset: CGFloat = 7,
                         finial: ((GraphicsContext, CGPoint, Bool) -> Void)?) {
        let k = cc.k
        let line1 = cc.rect.insetBy(dx: inset * k, dy: inset * k)
        let line2 = cc.rect.insetBy(dx: (inset + 2.6) * k, dy: (inset + 2.6) * k)
        let p1 = Path(roundedRect: line1, cornerRadius: max(2, cc.radius - (inset - 1) * k), style: .continuous)
        let p2 = Path(roundedRect: line2, cornerRadius: max(2, cc.radius - (inset + 1.5) * k), style: .continuous)
        var lines = ctx
        if finial != nil {
            let gapW = gap * k
            var gaps = Path(cc.rect.insetBy(dx: -20, dy: -20))
            gaps.addRect(CGRect(x: cc.rect.midX - gapW / 2, y: cc.rect.minY - 4, width: gapW, height: (inset + 7) * k + 4))
            gaps.addRect(CGRect(x: cc.rect.midX - gapW / 2, y: cc.rect.maxY - (inset + 7) * k, width: gapW, height: (inset + 7) * k + 4))
            lines.clip(to: gaps, style: FillStyle(eoFill: true))
        }
        let c = cc.pal.line(cc.scheme)
        lines.stroke(p1, with: .color(c.c(cc.dark ? 0.6 : 0.55)), lineWidth: cc.d.w(1.0 * k, minPx: 0.8))
        lines.stroke(p2, with: .color(c.c(cc.dark ? 0.26 : 0.24)), lineWidth: cc.d.w(0.55 * k, minPx: 0.5))
        if let finial {
            finial(ctx, CGPoint(x: cc.rect.midX, y: line1.minY), false)
            finial(ctx, CGPoint(x: cc.rect.midX, y: line1.maxY), true)
        }
    }

    /// 長さを縮めて、先端が描画可能範囲に収まるようにする。
    static func fit(_ origin: CGPoint, _ angle: CGFloat, _ length: CGFloat, extra: CGFloat, bounds: CGRect) -> CGFloat {
        var len = length
        for _ in 0..<14 {
            let tip = origin + CGPoint.polar(len + extra, angle)
            if bounds.contains(tip) { break }
            len *= 0.88
        }
        return len
    }

    /// 読む場所：本文列の背後だけ、ぼかした面でテーマの地に戻す（doc13 §2.5 視認性 > 世界観）。
    /// 地の色味（アイテム色）は縁と角に残り、一覧では見分けられ、本文の下は静かになる。
    static func readingArea(_ ctx: GraphicsContext, _ cc: CardContext) {
        guard !cc.tiny else { return }
        let k = cc.k
        let zone = cc.textZone.insetBy(dx: -12 * k, dy: -8 * k)
        var inner = ctx
        inner.clip(to: cc.shape)
        inner.drawLayer { l in
            l.addFilter(.blur(radius: 12 * k))
            let big = cc.textScale > 1.2
            l.fill(Path(roundedRect: zone, cornerRadius: 26 * k), with: .color(cc.scheme.surface.c(cc.dark ? (big ? 0.9 : 0.8) : (big ? 0.84 : 0.72))))
        }
    }

    /// 控えめな発光（宵だけ）。主役の背後に一枚、ぼかしで。
    static func glow(_ ctx: GraphicsContext, _ cc: CardContext, path: Path, color: RGB, alpha: Double = 0.3, radius: CGFloat = 5) {
        guard cc.dark else { return }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: radius * cc.k))
            l.fill(path, with: .color(color.c(alpha)))
        }
    }
}

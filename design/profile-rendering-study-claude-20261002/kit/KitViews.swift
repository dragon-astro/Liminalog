// 公開ビュー。本体の `ProfileIconFrameView(size:)` / `ProfileDecoratedCardBackground` と同じ渡し方で差し替えられる形。
import SwiftUI

/// フレーム。本体と同じ `size`（アバター＋余白の正方形）を受け取り、`size × 1.12` に描く。
struct DecoFrameView: View {
    let id: DecorationID
    let size: CGFloat
    let scheme: DecoScheme
    var pixelScale: CGFloat? = nil
    /// 実用時は表示サイズごとに一度だけラスタライズして使い回す（Canvas の再実行を避ける）
    var cached = false
    @Environment(\.displayScale) private var envScale

    static let contentScale: CGFloat = 1.12
    static let unitRatio: CGFloat = 383.0 / 1024.0

    var body: some View {
        let side = size * Self.contentScale
        let scale = pixelScale ?? envScale
        Group {
            if cached, let image = DecoRasterCache.shared.frame(id: id, side: side, scale: scale, scheme: scheme) {
                Image(decorative: image, scale: scale).resizable().frame(width: side, height: side)
            } else {
                DecoFrameCanvas(id: id, side: side, pixelScale: scale, scheme: scheme)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

struct DecoFrameCanvas: View {
    let id: DecorationID
    let side: CGFloat
    let pixelScale: CGFloat
    let scheme: DecoScheme

    var body: some View {
        let unit = side * DecoFrameView.unitRatio
        let detail = Detail(pxPerUnit: unit * pixelScale)
        let ops = DecoCatalog.frameOps(id, detail: detail, scheme: scheme).sorted { $0.z < $1.z }
        // 半透明を何層も重ねるため、8bit の量子化で等高線が出ないよう浮動小数で合成する
        Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: false) { ctx, sz in
            var c = ctx
            c.translateBy(x: sz.width / 2, y: sz.height / 2)
            c.scaleBy(x: unit, y: unit)
            for op in ops { op.draw(c) }
        }
        .frame(width: side, height: side)
    }
}

/// カード背景。渡された矩形に描き、縁から少しだけはみ出せる（本体の画像も 1.08 倍で枠外へ出ている）。
struct DecoCardView: View {
    let id: DecorationID
    let scheme: DecoScheme
    var pixelScale: CGFloat? = nil
    var cached = false
    @Environment(\.displayScale) private var envScale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 本文の大きさの目安（標準 .large = 1）
    static func textScale(_ t: DynamicTypeSize) -> CGFloat {
        switch t {
        case .xSmall, .small, .medium, .large: return 1
        case .xLarge: return 1.08
        case .xxLarge: return 1.16
        case .xxxLarge: return 1.24
        case .accessibility1: return 1.42
        case .accessibility2: return 1.6
        case .accessibility3: return 1.8
        case .accessibility4: return 2.0
        default: return 2.2
        }
    }

    var body: some View {
        let scale = pixelScale ?? envScale
        GeometryReader { proxy in
            let size = proxy.size
            let bleed = (min(size.width / 342, size.height / 222) * 12).rounded(.up)
            let full = CGSize(width: size.width + bleed * 2, height: size.height + bleed * 2)
            let ts = Self.textScale(typeSize)
            Group {
                if cached, let image = DecoRasterCache.shared.card(id: id, size: size, bleed: bleed, scale: scale, scheme: scheme, textScale: ts) {
                    Image(decorative: image, scale: scale).resizable()
                } else {
                    DecoCardCanvas(id: id, size: size, bleed: bleed, scale: scale, scheme: scheme, textScale: ts)
                }
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -bleed, y: -bleed)
        }
        .allowsHitTesting(false)
    }
}

struct DecoCardCanvas: View {
    let id: DecorationID
    let size: CGSize
    let bleed: CGFloat
    let scale: CGFloat
    let scheme: DecoScheme
    var textScale: CGFloat = 1

    var body: some View {
        Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: false) { ctx, _ in
            var c = ctx
            c.translateBy(x: bleed, y: bleed)
            let cc = CardContext(size: size, scale: scale, bleed: bleed, scheme: scheme, pal: id.palette, textScale: textScale)
            DecoCatalog.drawCard(id, c, cc)
            CardBase.readingArea(c, cc)
        }
        .frame(width: size.width + bleed * 2, height: size.height + bleed * 2)
    }
}

/// 表示サイズ×スケール×テーマごとに一度だけ描いて保持する簡易キャッシュ（実用時の負荷対策の試作）。
@MainActor
final class DecoRasterCache {
    static let shared = DecoRasterCache()
    private var store: [String: CGImage] = [:]

    func frame(id: DecorationID, side: CGFloat, scale: CGFloat, scheme: DecoScheme) -> CGImage? {
        let key = "f|\(id.rawValue)|\(Int(side * 10))|\(scale)|\(scheme.rawValue)"
        if let hit = store[key] { return hit }
        let r = ImageRenderer(content: DecoFrameCanvas(id: id, side: side, pixelScale: scale, scheme: scheme))
        r.scale = scale
        let img = r.cgImage
        store[key] = img
        return img
    }

    func card(id: DecorationID, size: CGSize, bleed: CGFloat, scale: CGFloat, scheme: DecoScheme, textScale: CGFloat = 1) -> CGImage? {
        let key = "c|\(id.rawValue)|\(Int(size.width * 10))x\(Int(size.height * 10))|\(scale)|\(scheme.rawValue)|\(textScale)"
        if let hit = store[key] { return hit }
        let r = ImageRenderer(content: DecoCardCanvas(id: id, size: size, bleed: bleed, scale: scale, scheme: scheme, textScale: textScale))
        r.scale = scale
        let img = r.cgImage
        store[key] = img
        return img
    }
}

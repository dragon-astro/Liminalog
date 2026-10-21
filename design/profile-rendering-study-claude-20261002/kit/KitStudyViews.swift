// 確認用の擬似プロフィールUI（本体 ProfileHero / ProfilePhotoView の寸法を写した）と比較シート。
// 実用時の組み込みを想定し、文字はテーマのトークン色で描く（本体の生成カード用の差分合成は使わない）。
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum PNGReference {
    static var root: URL? = nil
    static func image(_ name: String, card: Bool) -> Image? {
        #if canImport(UIKit)
        if let path = Bundle.main.path(forResource: name, ofType: "png"), let img = UIImage(contentsOfFile: path) { return Image(uiImage: img) }
        #else
        if let root, let img = NSImage(contentsOf: root.appendingPathComponent(card ? "Cards" : "Frames").appendingPathComponent(name + ".png")) {
            return Image(nsImage: img)
        }
        #endif
        return nil
    }
}

enum AvatarKind: String, CaseIterable { case initial, photo }

struct PseudoPhoto: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [RGB(0x9CC3D9).c(), RGB(0xE9D3B4).c(), RGB(0x7C8E63).c()]), startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.08, width: w * 0.5, height: h * 0.5)), with: .color(RGB(0xFFF1D6).c(0.5)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.7, width: w * 0.76, height: h * 0.6)), with: .color(RGB(0x3E4A6E).c()))
            ctx.fill(Path(CGRect(x: w * 0.43, y: h * 0.55, width: w * 0.14, height: h * 0.2)), with: .color(RGB(0xD9A98A).c()))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.32, y: h * 0.24, width: w * 0.36, height: h * 0.42)), with: .color(RGB(0xEDC4A4).c()))
            var hair = Path()
            hair.move(to: CGPoint(x: w * 0.3, y: h * 0.48))
            hair.addCurve(to: CGPoint(x: w * 0.7, y: h * 0.46), control1: CGPoint(x: w * 0.22, y: h * 0.1), control2: CGPoint(x: w * 0.8, y: h * 0.1))
            hair.addQuadCurve(to: CGPoint(x: w * 0.36, y: h * 0.34), control: CGPoint(x: w * 0.55, y: h * 0.26))
            hair.closeSubpath()
            ctx.fill(hair, with: .color(RGB(0x3B2A24).c()))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.41, y: h * 0.42, width: w * 0.04, height: h * 0.03)), with: .color(RGB(0x3B2A24).c(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.55, y: h * 0.42, width: w * 0.04, height: h * 0.03)), with: .color(RGB(0x3B2A24).c(0.8)))
        }
    }
}

/// 本体 ProfilePhotoView 相当（hero は size+16、その他は Friends の size + max(7, size*0.16)）。
struct KitAvatar: View {
    let id: DecorationID
    let scheme: DecoScheme
    let size: CGFloat
    var kind: AvatarKind = .initial
    var heroRule = false
    var pixelScale: CGFloat? = nil
    var usePNG = false
    var cached = false
    var accent: RGB = RGB(0x8A7BE0)

    var frameSize: CGFloat { heroRule ? size + 16 : size + max(7, size * 0.16) }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [accent.c(), accent.mix(.black, 0.32).c()], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            if kind == .photo {
                PseudoPhoto().frame(width: size, height: size).clipShape(Circle())
            } else {
                Text("R").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
            }
            Circle().stroke(.white.opacity(0.75), lineWidth: size >= 60 ? 2 : 1).frame(width: size, height: size)
            if usePNG {
                if let img = PNGReference.image(id.pngFrameName, card: false) {
                    img.resizable().interpolation(.high).scaledToFit().frame(width: frameSize, height: frameSize).scaleEffect(1.12)
                }
            } else {
                DecoFrameView(id: id, size: frameSize, scheme: scheme, pixelScale: pixelScale, cached: cached)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .shadow(color: (scheme.isDark ? RGB.black : scheme.shadow).c(scheme.isDark ? 0.3 : 0.22), radius: size >= 60 ? 10 : 4, y: size >= 60 ? 8 : 2)
    }
}

struct KitHero: View {
    let id: DecorationID
    let scheme: DecoScheme
    var name = "Ryu"
    var bio = "朝の光で、今日のリズムを整える。"
    var kind: AvatarKind = .initial
    var textScale: CGFloat = 1
    var pixelScale: CGFloat? = nil
    var dynamicType = false
    var usePNG = false
    var cached = false

    private func font(_ style: Font, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        dynamicType ? style.weight(weight) : .system(size: size * textScale, weight: weight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                KitAvatar(id: id, scheme: scheme, size: 82, kind: kind, heroRule: true, pixelScale: pixelScale, usePNG: usePNG, cached: cached)
                HStack(spacing: 9) {
                    action("pencil")
                    action("square.and.arrow.up")
                }
            }
            .frame(width: 98, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                Text("@liminal_ryu  Lv.12")
                    .font(font(.caption, 12, .semibold))
                    .foregroundStyle(textColor(secondary: true))
                    .lineLimit(1).minimumScaleFactor(0.84)
                Text(name)
                    .font(font(.title2, 22, .bold))
                    .foregroundStyle(textColor(secondary: false))
                    .lineLimit(1).minimumScaleFactor(0.82)
                HStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                    Text("夜明けの記録者")
                }
                .font(font(.caption2, 11, .bold))
                .foregroundStyle(badge.c())
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(badge.c(0.14), in: Capsule())
                .lineLimit(1)
                Text(bio)
                    .font(font(.subheadline, 15))
                    .foregroundStyle(textColor(secondary: true))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
            .padding(.top, 10)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .topLeading)
        .background {
            if usePNG {
                GeometryReader { proxy in
                    if let img = PNGReference.image(id.pngCardName, card: true) {
                        img.resizable().interpolation(.high).scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.08).offset(y: -24)
                    }
                }
            } else {
                DecoCardView(id: id, scheme: scheme, pixelScale: pixelScale, cached: cached)
            }
        }
        .padding(.horizontal, 4)
    }

    private var badge: RGB { scheme.isDark ? RGB(0xFFC98A) : RGB(0xB8662A) }

    private func textColor(secondary: Bool) -> Color {
        if usePNG { return .black.opacity(secondary ? 0.6 : 0.85) }  // 既存PNGは明るい地なので参考表示では暗い文字
        return (secondary ? scheme.secondaryText : scheme.text).c()
    }

    private func action(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(dynamicType ? .footnote.weight(.semibold) : .system(size: 13 * min(textScale, 1.3), weight: .semibold))
            .foregroundStyle(scheme.isDark ? RGB.white.c() : scheme.text.c())
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(scheme.isDark ? RGB.black.c(0.26) : RGB.white.c(0.72))
                    .overlay { Circle().stroke(scheme.isDark ? RGB.white.c(0.3) : scheme.divider.c(), lineWidth: 1) }
            }
            .shadow(color: (scheme.isDark ? RGB.black : scheme.shadow).c(0.2), radius: 6, y: 3)
    }
}

// MARK: - Sheets

struct Caption: View {
    let text: String
    var color: Color = .secondary
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color) }
}

/// 1モチーフの確認シート：宵／曙 × ヒーロー・既存PNG参考・アバター実寸・一覧サイズ
struct KitMotifSheet: View {
    let id: DecorationID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(id.title)  \(id.rawValue)").font(.system(size: 15, weight: .bold))
                swatch(id.palette.primary); swatch(id.palette.secondary)
                Text("左: 宵（ダーク）／右: 曙（ライト）・@3x・実寸").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(DecoScheme.allCases) { s in
                    VStack(alignment: .leading, spacing: 10) {
                        Caption(text: "コード描画", color: s.secondaryText.c())
                        KitHero(id: id, scheme: s, kind: s.isDark ? .initial : .photo, pixelScale: 3).frame(width: 358)
                        HStack(alignment: .center, spacing: 14) {
                            ForEach([CGFloat(24), 32, 48], id: \.self) { sz in
                                KitAvatar(id: id, scheme: s, size: sz, kind: .initial, pixelScale: 3)
                            }
                            ForEach([CGFloat(24), 32, 48], id: \.self) { sz in
                                KitAvatar(id: id, scheme: s, size: sz, kind: .photo, pixelScale: 3)
                            }
                        }
                        .padding(.leading, 6)
                        HStack(alignment: .center, spacing: 12) {
                            DecoCardView(id: id, scheme: s, pixelScale: 3)
                                .frame(width: 120, height: 75)
                            DecoCardView(id: id, scheme: s, pixelScale: 3)
                                .frame(width: 74, height: 46)
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(s.surface.c()).frame(width: 74, height: 74)
                                Circle().fill(id.palette.primary.c(0.14)).frame(width: 40, height: 40)
                                DecoFrameView(id: id, size: 54, scheme: s, pixelScale: 3)
                            }
                        }
                        .padding(.leading, 6)
                        Caption(text: "参考：既存PNG（本体と同じ配置）", color: s.secondaryText.c())
                        KitHero(id: id, scheme: s, kind: .initial, pixelScale: 3, usePNG: true).frame(width: 358)
                    }
                    .padding(16)
                    .frame(width: 390, alignment: .topLeading)
                    .background(s.canvas.c())
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }

    private func swatch(_ c: RGB) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c.c()).frame(width: 16, height: 16)
    }
}

/// セット全体のヒーロー一覧（1テーマ）
struct KitLineupSheet: View {
    let scheme: DecoScheme
    let ids: [DecorationID]
    var columns = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("個性カード＋フレーム（コード描画）— \(scheme.title)  @2x")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(scheme.text.c())
            let rows = stride(from: 0, to: ids.count, by: columns).map { Array(ids[$0..<min($0 + columns, ids.count)]) }
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[r]) { id in
                        VStack(alignment: .leading, spacing: 4) {
                            Caption(text: "\(id.title)  \(id.rawValue)", color: scheme.secondaryText.c())
                            KitHero(id: id, scheme: scheme, name: id.title, kind: (r + rows[r].firstIndex(of: id)!) % 2 == 0 ? .initial : .photo, pixelScale: 2)
                                .frame(width: 358)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(scheme.canvas.c())
    }
}

/// コレクション一覧の想定サイズ（カード 74×46 / 詳細 228×142、フレーム 54）
struct KitGallerySheet: View {
    let scheme: DecoScheme
    let ids: [DecorationID]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一覧サイズ — \(scheme.title)  @3x").font(.system(size: 13, weight: .bold)).foregroundStyle(scheme.text.c())
            let rows = stride(from: 0, to: ids.count, by: 5).map { Array(ids[$0..<min($0 + 5, ids.count)]) }
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rows[r]) { id in
                        VStack(alignment: .leading, spacing: 6) {
                            DecoCardView(id: id, scheme: scheme, pixelScale: 3).frame(width: 140, height: 87)
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(id.palette.primary.c(0.14)).frame(width: 40, height: 40)
                                    DecoFrameView(id: id, size: 54, scheme: scheme, pixelScale: 3)
                                }
                                KitAvatar(id: id, scheme: scheme, size: 32, kind: .photo, pixelScale: 3)
                                Text(id.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(scheme.text.c())
                            }
                        }
                        .padding(8)
                        .background(scheme.surface.c(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(scheme.canvas.c())
    }
}

/// 20種の一覧比較：既存PNG（参考）｜コード描画・宵｜コード描画・曙。カード120×75とアバター48ptを同じ条件で並べる。
struct KitCompareGridSheet: View {
    let ids: [DecorationID]
    var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("既存PNG（参考）／コード描画・宵／コード描画・曙 — カード120×75pt・アバター48pt・@3x \(title)")
                .font(.system(size: 12, weight: .bold)).padding(10)
            HStack(spacing: 0) {
                Text("").frame(width: 70)
                column("既存PNG", RGB(0x2A2442), .white)
                column("コード・宵", DecoScheme.dusk.canvas, DecoScheme.dusk.text.c())
                column("コード・曙", DecoScheme.daybreak.canvas, DecoScheme.daybreak.text.c())
            }
            ForEach(ids) { id in
                HStack(spacing: 0) {
                    Text(id.title).font(.system(size: 12, weight: .bold)).frame(width: 70)
                    cell(bg: RGB(0x2A2442)) {
                        if let img = PNGReference.image(id.pngCardName, card: true) {
                            img.resizable().interpolation(.medium).scaledToFill().frame(width: 120, height: 75)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        KitAvatar(id: id, scheme: .dusk, size: 48, kind: .photo, pixelScale: 3, usePNG: true)
                    }
                    ForEach(DecoScheme.allCases) { s in
                        cell(bg: s.canvas) {
                            DecoCardView(id: id, scheme: s, pixelScale: 3).frame(width: 120, height: 75)
                            KitAvatar(id: id, scheme: s, size: 48, kind: .photo, pixelScale: 3)
                        }
                    }
                }
            }
        }
        .background(Color.white)
    }

    private func column(_ t: String, _ bg: RGB, _ fg: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(fg).frame(width: 230, height: 22).background(bg.c())
    }

    private func cell<V: View>(bg: RGB, @ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 18) { content() }
            .frame(width: 230, height: 96)
            .background(bg.c())
    }
}

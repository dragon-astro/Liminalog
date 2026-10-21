// 比較用の擬似プロフィールUI。本体 ProfileHero / ProfilePhotoView のレイアウト値を写し、
// 既存PNGとコード描画を「同じ条件」で並べる。macOS(書き出し)と iOS(プレビュー)で共用。
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum Variant: String, CaseIterable, Identifiable {
    case original, code, codex
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "既存PNG"
        case .code: return "Claude試作（コード）"
        case .codex: return "Codex先行試作（コード）"
        }
    }
    /// 通常の比較は既存PNGとこの試作の2列。Codex 列は比較用ビルドでのみ使う。
    static let compared: [Variant] = [.original, .code]
}

/// 先行試作など外部の描画を同じ擬似UIへ差し込むためのフック（比較用ビルドでのみ設定）。
enum ExternalArt {
    /// アバター直径を受け取り、そのアバターに合わせたフレームを返す
    static var frame: ((Motif, CGFloat) -> AnyView)? = nil
    static var card: ((Motif) -> AnyView)? = nil
}

enum OriginalArt {
    static var root: URL? = nil

    static func fileName(_ motif: Motif, card: Bool) -> String {
        switch (motif, card) {
        case (.leaf, false): return "profile_frame_free_leaf_corner"
        case (.leaf, true): return "profile_card_free_leaf_corner_panel"
        case (.star, false): return "profile_frame_free_constellation"
        case (.star, true): return "profile_card_free_constellation_panel"
        }
    }

    static func image(_ motif: Motif, card: Bool) -> Image {
        let name = fileName(motif, card: card)
        #if canImport(UIKit)
        if let path = Bundle.main.path(forResource: name, ofType: "png"), let img = UIImage(contentsOfFile: path) {
            return Image(uiImage: img)
        }
        #else
        if let root, let img = NSImage(contentsOf: root.appendingPathComponent(card ? "Cards" : "Frames").appendingPathComponent(name + ".png")) {
            return Image(nsImage: img)
        }
        #endif
        return Image(systemName: "questionmark.square.dashed")
    }
}

struct Backdrop {
    var dark: Bool
    var page: Color { dark ? RGB(0x14152E).c() : RGB(0xF6F1E7).c() }
    var text: Color { dark ? .white : RGB(0x26243A).c() }
    var secondary: Color { dark ? .white.opacity(0.6) : RGB(0x26243A).c(0.6) }
    var surface: Color { dark ? RGB(0x1F2142).c() : .white }
}

// MARK: - Avatar

enum AvatarKind: String, CaseIterable { case initial, photo }

struct PseudoPhoto: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [RGB(0x9CC3D9).c(), RGB(0xE9D3B4).c(), RGB(0x7C8E63).c()]), startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.08, width: w * 0.5, height: h * 0.5)), with: .color(RGB(0xFFF1D6).c(0.5)))
            // 肩
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.7, width: w * 0.76, height: h * 0.6)), with: .color(RGB(0x3E4A6E).c()))
            // 首と顔
            ctx.fill(Path(CGRect(x: w * 0.43, y: h * 0.55, width: w * 0.14, height: h * 0.2)), with: .color(RGB(0xD9A98A).c()))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.32, y: h * 0.24, width: w * 0.36, height: h * 0.42)), with: .color(RGB(0xEDC4A4).c()))
            // 髪
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
struct FramedAvatar: View {
    let variant: Variant
    let motif: Motif
    let size: CGFloat
    var kind: AvatarKind = .initial
    var name: String = "Ryu"
    var heroRule: Bool = false
    var showsFrame: Bool = true
    var pixelScale: CGFloat? = nil

    var frameSize: CGFloat { heroRule ? size + 16 : size + max(7, size * 0.16) }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [RGB(0x8A7BE0).c(), RGB(0x5C4FB8).c()], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
            if kind == .photo {
                PseudoPhoto().frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
            Circle().stroke(.white.opacity(0.75), lineWidth: size >= 60 ? 2 : 1).frame(width: size, height: size)
            if showsFrame {
                Group {
                    switch variant {
                    case .original:
                        OriginalArt.image(motif, card: false)
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: frameSize, height: frameSize)
                            .scaleEffect(1.12)
                    case .code:
                        CodeFrameView(motif: motif, size: frameSize, pixelScale: pixelScale)
                    case .codex:
                        ExternalArt.frame?(motif, size)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .shadow(color: .black.opacity(0.22), radius: size >= 60 ? 10 : 4, y: size >= 60 ? 8 : 2)
    }
}

// MARK: - Card background

struct CardBackground: View {
    let variant: Variant
    let motif: Motif
    var pixelScale: CGFloat? = nil
    /// 一覧サムネイル（Image(thumbnail).scaledToFill + clip）か、hero の背景（scale 1.08 / offset -24）か
    var thumbnail = false

    var body: some View {
        if variant == .code {
            CodeCardView(motif: motif, pixelScale: pixelScale)
        } else if variant == .codex {
            ExternalArt.card?(motif)
        } else if thumbnail {
            OriginalArt.image(motif, card: true).resizable().interpolation(.medium).scaledToFill()
        } else {
            GeometryReader { proxy in
                OriginalArt.image(motif, card: true)
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(proxy.size.height < 60 ? 1.18 : 1.08)
                    .offset(y: proxy.size.height < 60 ? -2 : -24)
            }
        }
    }
}

// MARK: - Hero mock

struct HeroMock: View {
    let variant: Variant
    let motif: Motif
    var name = "Ryu"
    var bio = "朝の光で、今日のリズムを整える。"
    var kind: AvatarKind = .initial
    var textScale: CGFloat = 1
    var pixelScale: CGFloat? = nil
    /// iOS プレビューでは本体と同じ Dynamic Type のテキストスタイルを使う
    var dynamicType = false

    private func font(_ style: Font, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        dynamicType ? style.weight(weight) : .system(size: size * textScale, weight: weight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                FramedAvatar(variant: variant, motif: motif, size: 82, kind: kind, name: name, heroRule: true, pixelScale: pixelScale)
                HStack(spacing: 9) {
                    action("pencil")
                    action("square.and.arrow.up")
                }
            }
            .frame(width: 98, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                Text("@liminal_ryu  Lv.12")
                    .font(font(.caption, 12, .semibold))
                    .lineLimit(1).minimumScaleFactor(0.84)
                    .foregroundStyle(.white).blendMode(.difference)
                    .opacity(0.82)
                Text(name)
                    .font(font(.title2, 22, .bold))
                    .foregroundStyle(.white).blendMode(.difference)
                    .lineLimit(1).minimumScaleFactor(0.82)
                    .padding(.trailing, 4)
                HStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                    Text("夜明けの記録者")
                }
                .font(font(.caption2, 11, .bold))
                .foregroundStyle(RGB(0xE08A3C).c())
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RGB(0xE08A3C).c(0.12), in: Capsule())
                .lineLimit(1)
                .frame(height: 23 * max(1, textScale * 0.9), alignment: .leading)
                Text(bio)
                    .font(font(.subheadline, 15))
                    .foregroundStyle(.white).blendMode(.difference)
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
        .background { CardBackground(variant: variant, motif: motif, pixelScale: pixelScale) }
        .padding(.horizontal, 4)
    }

    private func action(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(dynamicType ? .footnote.weight(.semibold) : .system(size: 13 * min(textScale, 1.3), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background { Circle().fill(.black.opacity(0.26)).overlay { Circle().stroke(.white.opacity(0.34), lineWidth: 1) } }
            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
    }
}

// MARK: - Sheets (macOS 書き出し用・iOS でも表示可)

struct Caption: View {
    let text: String
    var color: Color = .secondary
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color) }
}

struct MasterComparisonSheet: View {
    let motif: Motif
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("\(motif.title) — 原寸マスター比較（左: 既存PNG / 右: コード描画）").font(.system(size: 22, weight: .bold))
            HStack(spacing: 24) {
                ForEach([false, true], id: \.self) { dark in
                    HStack(spacing: 12) {
                        ForEach(Variant.compared) { v in
                            VStack(spacing: 6) {
                                ZStack {
                                    Backdrop(dark: dark).page
                                    if v == .original {
                                        OriginalArt.image(motif, card: false).resizable().scaledToFit().frame(width: 420, height: 420)
                                    } else {
                                        CodeFrameCanvas(motif: motif, side: 420, pixelScale: 2)
                                    }
                                }
                                .frame(width: 420, height: 420)
                                Caption(text: "\(v.label) · \(dark ? "暗背景" : "明背景")")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 24) {
                ForEach(Variant.compared) { v in
                    VStack(spacing: 6) {
                        ZStack {
                            Backdrop(dark: true).page
                            if v == .original {
                                OriginalArt.image(motif, card: true).resizable().scaledToFit().frame(width: 864, height: 540)
                            } else {
                                CodeCardView(motif: motif, pixelScale: 2).frame(width: 800, height: 500)
                            }
                        }
                        .frame(width: 864, height: 540)
                        Caption(text: v.label)
                    }
                }
            }
        }
        .padding(28)
        .background(Color.white)
    }
}

struct AvatarSizeSheet: View {
    let motif: Motif
    let sizes: [CGFloat] = [24, 32, 48, 82]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(motif.title) — 実寸アバター（24 / 32 / 48 / 82pt・@3x）").font(.system(size: 13, weight: .bold))
            HStack(spacing: 0) {
                ForEach([false, true], id: \.self) { dark in
                    let b = Backdrop(dark: dark)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Variant.compared) { v in
                            VStack(alignment: .leading, spacing: 4) {
                                Caption(text: v.label, color: b.secondary)
                                HStack(alignment: .center, spacing: 16) {
                                    ForEach(AvatarKind.allCases, id: \.self) { kind in
                                        ForEach(sizes, id: \.self) { s in
                                            FramedAvatar(variant: v, motif: motif, size: s, kind: kind, heroRule: s == 82, pixelScale: 3)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(14)
                    .background(b.page)
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }
}

struct ProfileSheet: View {
    let motif: Motif
    var body: some View {
        let cases: [(String, Bool, String, String, AvatarKind, CGFloat)] = [
            ("明背景・通常", false, "Ryu", "朝の光で、今日のリズムを整える。", .initial, 1),
            ("明背景・長い名前・写真", false, "Ryuga Yasuda Liminalog", "週末は川沿いを歩いて、季節の色を記録しています。長めの自己紹介の確認。", .photo, 1),
            ("明背景・大きな文字(約AX1相当)", false, "Ryu", "朝の光で、今日のリズムを整える。", .initial, 1.45),
            ("暗背景・通常", true, "Ryu", "朝の光で、今日のリズムを整える。", .initial, 1),
            ("暗背景・写真", true, "みなと", "夜の散歩と星の記録。", .photo, 1),
        ]
        VStack(alignment: .leading, spacing: 10) {
            Text("\(motif.title) — プロフィール装着（幅358pt / @3x）  左: 既存PNG  右: コード描画").font(.system(size: 13, weight: .bold))
            ForEach(cases.indices, id: \.self) { i in
                let c = cases[i]
                let b = Backdrop(dark: c.1)
                VStack(alignment: .leading, spacing: 4) {
                    Caption(text: c.0, color: b.secondary)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Variant.compared) { v in
                            HeroMock(variant: v, motif: motif, name: c.2, bio: c.3, kind: c.4, textScale: c.5, pixelScale: 3)
                                .frame(width: 358)
                        }
                    }
                }
                .padding(14)
                .background(b.page)
            }
        }
        .padding(12)
        .background(Color.white)
    }
}

struct ListSheet: View {
    let motif: Motif
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(motif.title) — 一覧サイズ（@3x）").font(.system(size: 13, weight: .bold))
            ForEach([false, true], id: \.self) { dark in
                let b = Backdrop(dark: dark)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Variant.compared) { v in
                        HStack(alignment: .center, spacing: 14) {
                            Caption(text: v.label, color: b.secondary).frame(width: 60, alignment: .leading)
                            CardBackground(variant: v, motif: motif, pixelScale: 3, thumbnail: true)
                                .frame(width: 120, height: 75).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            CardBackground(variant: v, motif: motif, pixelScale: 3, thumbnail: true)
                                .frame(width: 74, height: 46).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            CardBackground(variant: v, motif: motif, pixelScale: 3)
                                .frame(width: 58, height: 34)
                            // ギャラリーのフレームタイル(54) / 装備タイル(28)
                            ZStack {
                                Circle().fill(RGB(0x8A7BE0).c(0.14)).frame(width: 40, height: 40)
                                frame(v, 54)
                            }
                            ZStack {
                                Circle().fill(RGB(0x8A7BE0).c(0.14)).frame(width: 22, height: 22)
                                frame(v, 28)
                            }
                        }
                    }
                }
                .padding(14)
                .background(b.page)
            }
        }
        .padding(12)
        .background(Color.white)
    }

    @ViewBuilder
    private func frame(_ v: Variant, _ s: CGFloat) -> some View {
        if v == .original {
            OriginalArt.image(motif, card: false).resizable().scaledToFit().frame(width: s, height: s).scaleEffect(1.12)
        } else {
            CodeFrameView(motif: motif, size: s, pixelScale: 3)
        }
    }
}

struct OverviewSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Motif.allCases) { m in
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { dark in
                        HStack(spacing: 12) {
                            ForEach(Variant.compared) { v in
                                VStack(spacing: 4) {
                                    Caption(text: "\(m.title) · \(v.label)", color: Backdrop(dark: dark).secondary)
                                    HeroMock(variant: v, motif: m, pixelScale: 2).frame(width: 358)
                                }
                            }
                        }
                        .padding(14)
                        .background(Backdrop(dark: dark).page)
                    }
                }
            }
        }
        .background(Color.white)
    }
}

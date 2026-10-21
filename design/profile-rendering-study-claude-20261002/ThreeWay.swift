// 先行するCodex試作（design/profile-rendering-study-20261002/NativeDecorations.swift）を
// 読み取り専用でコンパイルに含め、同じ擬似プロフィールUI・同じ縮尺で3者を並べる。
// `./render.sh codex` のときだけ -D WITH_CODEX でビルドされる。先行試作のファイルは変更しない。
#if WITH_CODEX
import SwiftUI

enum CodexBridge {
    static func install() {
        // Codex 版は「主リング半径 = 幅の 38.2%」で描かれ、本人のプレビューも avatar / 0.764 の枠で表示している
        ExternalArt.frame = { motif, avatar in
            AnyView(NativeDecorationFrame(motif: motif == .leaf ? .botanical : .celestial)
                .frame(width: avatar / 0.764, height: avatar / 0.764))
        }
        ExternalArt.card = { motif in
            AnyView(NativeDecorationCard(motif: motif == .leaf ? .botanical : .celestial))
        }
    }
}

struct ThreeWaySheet: View {
    let motif: Motif
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(motif.title) — 3者比較（同じ擬似プロフィールUI・@3x）  左: 既存PNG / 中: Claude試作 / 右: Codex先行試作")
                .font(.system(size: 13, weight: .bold))
            ForEach([false, true], id: \.self) { dark in
                let b = Backdrop(dark: dark)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Variant.allCases) { v in
                            VStack(alignment: .leading, spacing: 4) {
                                Caption(text: "\(v.label) · \(dark ? "暗背景・写真" : "明背景・イニシャル")", color: b.secondary)
                                HeroMock(variant: v, motif: motif, name: "Ryuga Yasuda",
                                         bio: "週末は川沿いを歩いて、季節の色を記録しています。",
                                         kind: dark ? .photo : .initial, pixelScale: 3)
                                    .frame(width: 358)
                            }
                        }
                    }
                    HStack(alignment: .center, spacing: 16) {
                        ForEach(Variant.allCases) { v in
                            HStack(spacing: 12) {
                                ForEach([CGFloat(24), 32, 48], id: \.self) { s in
                                    FramedAvatar(variant: v, motif: motif, size: s, kind: dark ? .photo : .initial, pixelScale: 3)
                                }
                                CardBackground(variant: v, motif: motif, pixelScale: 3, thumbnail: true)
                                    .frame(width: 120, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .frame(width: 358, alignment: .leading)
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
#endif

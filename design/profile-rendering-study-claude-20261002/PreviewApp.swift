// 独立した iOS プレビュー（シミュレータ確認用）。本体アプリとは無関係の別バンドル。
// 起動引数: -motif leaf|star  -dark 0|1  -bigText 0|1  -page 0(プロフィール)|1(サイズ・一覧)
import SwiftUI

@main
struct ProfileDecorationStudyApp: App {
    var body: some Scene { WindowGroup { StudyRoot() } }
}

struct StudyRoot: View {
    @State private var motif: Motif
    @State private var dark: Bool
    @State private var bigText: Bool
    @State private var page: Int

    init() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        _motif = State(initialValue: value("-motif") == "star" ? .star : .leaf)
        _dark = State(initialValue: value("-dark") == "1")
        _bigText = State(initialValue: value("-bigText") == "1")
        _page = State(initialValue: Int(value("-page") ?? "0") ?? 0)
    }

    var body: some View {
        let b = Backdrop(dark: dark)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controls(b)
                if page == 0 {
                    ForEach(Variant.compared) { v in
                        Text(v.label).font(.caption.weight(.semibold)).foregroundStyle(b.secondary)
                        HeroMock(variant: v, motif: motif, name: bigText ? "Ryu" : "Ryuga Yasuda Liminalog",
                                 bio: "週末は川沿いを歩いて、季節の色を記録しています。", kind: v == .original ? .initial : .initial, dynamicType: true)
                    }
                    ForEach(Variant.compared) { v in
                        Text("\(v.label)・写真").font(.caption.weight(.semibold)).foregroundStyle(b.secondary)
                        HeroMock(variant: v, motif: motif, name: "みなと", bio: "夜の散歩と星の記録。", kind: .photo, dynamicType: true)
                    }
                } else {
                    sizes(b)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(b.page.ignoresSafeArea())
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(bigText ? .accessibility1 : .large)
    }

    private func controls(_ b: Backdrop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("コード描画 試作（葉隅・星図線）").font(.headline).foregroundStyle(b.text)
            Picker("モチーフ", selection: $motif) {
                ForEach(Motif.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("ページ", selection: $page) {
                Text("プロフィール").tag(0)
                Text("サイズ・一覧").tag(1)
            }
            .pickerStyle(.segmented)
            HStack {
                Toggle("暗背景", isOn: $dark)
                Toggle("大きな文字", isOn: $bigText)
            }
            .font(.footnote)
            .foregroundStyle(b.text)
        }
        .dynamicTypeSize(.large)
    }

    private func sizes(_ b: Backdrop) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Variant.compared) { v in
                Text(v.label).font(.caption.weight(.semibold)).foregroundStyle(b.secondary)
                ForEach(AvatarKind.allCases, id: \.self) { kind in
                    HStack(alignment: .center, spacing: 14) {
                        ForEach([CGFloat(24), 32, 48, 82], id: \.self) { s in
                            FramedAvatar(variant: v, motif: motif, size: s, kind: kind, heroRule: s == 82)
                        }
                    }
                }
                HStack(spacing: 12) {
                    CardBackground(variant: v, motif: motif, thumbnail: true)
                        .frame(width: 120, height: 75).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    CardBackground(variant: v, motif: motif, thumbnail: true)
                        .frame(width: 74, height: 46).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    ZStack {
                        Circle().fill(RGB(0x8A7BE0).c(0.14)).frame(width: 40, height: 40)
                        if v == .original {
                            OriginalArt.image(motif, card: false).resizable().scaledToFit().frame(width: 54, height: 54).scaleEffect(1.12)
                        } else {
                            CodeFrameView(motif: motif, size: 54)
                        }
                    }
                }
            }
        }
    }
}

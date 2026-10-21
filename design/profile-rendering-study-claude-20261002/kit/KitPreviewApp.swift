// 独立した iOS プレビュー（シミュレータ確認用）。本体アプリとは別バンドルで、本体のコードには触れない。
// 起動引数: -scheme dusk|daybreak  -bigText 0|1  -page 0(プロフィール)|1(コレクション一覧)|2(1種の詳細)  -start N  -motif <id>
import SwiftUI

@main
struct DecorationKitPreviewApp: App {
    var body: some Scene { WindowGroup { KitPreviewRoot() } }
}

struct KitPreviewRoot: View {
    @State private var scheme: DecoScheme
    @State private var bigText: Bool
    @State private var page: Int
    @State private var start: Int
    @State private var motif: DecorationID

    init() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        _scheme = State(initialValue: value("-scheme") == "daybreak" ? .daybreak : .dusk)
        _bigText = State(initialValue: value("-bigText") == "1")
        _page = State(initialValue: Int(value("-page") ?? "0") ?? 0)
        _start = State(initialValue: Int(value("-start") ?? "0") ?? 0)
        _motif = State(initialValue: DecorationID.allCases.first { $0.rawValue == value("-motif") || $0.rawValue == "free_" + (value("-motif") ?? "") } ?? .leafCorner)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                switch page {
                case 0: profiles
                case 1: gallery
                default: detail
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(scheme.canvas.c().ignoresSafeArea())
        .preferredColorScheme(scheme.isDark ? .dark : .light)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("装飾キット（コード描画・試作）").font(.headline).foregroundStyle(scheme.text.c())
            Picker("テーマ", selection: $scheme) { ForEach(DecoScheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("ページ", selection: $page) {
                Text("プロフィール").tag(0); Text("一覧").tag(1); Text("詳細").tag(2)
            }.pickerStyle(.segmented)
            Toggle("大きな文字（AX1）", isOn: $bigText).font(.footnote).foregroundStyle(scheme.text.c())
        }
        .dynamicTypeSize(.large)
    }

    /// プロフィール：20種を本体と同じ寸法のヒーローで並べる（表示はラスタキャッシュ経由）
    private var profiles: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(DecoCatalog.implemented.dropFirst(start).enumerated()), id: \.element.id) { i, id in
                VStack(alignment: .leading, spacing: 4) {
                    Text(id.title).font(.caption.weight(.semibold)).foregroundStyle(scheme.secondaryText.c())
                    KitHero(id: id, scheme: scheme, name: i % 3 == 1 ? "Ryuga Yasuda Liminalog" : "Ryu",
                            bio: i % 3 == 2 ? "週末は川沿いを歩いて、季節の色を記録しています。" : "朝の光で、今日のリズムを整える。",
                            kind: i % 2 == 0 ? .initial : .photo, dynamicType: true, cached: true)
                        .dynamicTypeSize(bigText ? .accessibility1 : .large)
                }
            }
        }
    }

    /// 一覧：本体コレクションと同じ3列グリッド（カード74×46・フレーム54）
    private var gallery: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(DecoCatalog.implemented) { id in
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        DecoCardView(id: id, scheme: scheme, cached: true).frame(width: 60, height: 38)
                        ZStack {
                            Circle().fill(id.palette.primary.c(0.14)).frame(width: 30, height: 30)
                            DecoFrameView(id: id, size: 40, scheme: scheme, cached: true)
                        }
                    }
                    Text(id.title).font(.caption2.weight(.semibold)).foregroundStyle(scheme.text.c())
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(scheme.surface.c(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    /// 詳細：1種を大きく（コレクションの詳細プレビュー 228×142 と、フレーム 164pt）
    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("モチーフ", selection: $motif) { ForEach(DecoCatalog.implemented) { Text($0.title).tag($0) } }
            HStack { Spacer(); DecoCardView(id: motif, scheme: scheme).frame(width: 228, height: 142); Spacer() }
            HStack { Spacer(); KitAvatar(id: motif, scheme: scheme, size: 148, kind: .photo); Spacer() }
            KitHero(id: motif, scheme: scheme, kind: .initial, dynamicType: true).dynamicTypeSize(bigText ? .accessibility1 : .large)
        }
    }
}

import SwiftUI
import Testing
@testable import Liminalog

/// 装飾デザインの方向性確認用に、代表フレーム/カードを PNG へ書き出す。
/// （プロダクトのテストではなく、目視レビュー用のレンダラ。）
@MainActor
struct CollectionMockupRenderTests {
    private let outputDir = URL(fileURLWithPath: "/tmp/liminal_mockups")
    private let accent = Color(hex: "#C9A7FF")

    @Test(.disabled("Design review renderer; run manually when refreshing /tmp/liminal_mockups assets."))
    func renderRepresentatives() throws {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try render(scheme: .dark, name: "collection_dark")
        try render(scheme: .light, name: "collection_light")
    }

    private func render(scheme: ColorScheme, name: String) throws {
        let canvas = scheme == .dark ? Color(hex: "#0D0B16") : Color(hex: "#FBF3E7")
        let content = VStack(alignment: .leading, spacing: 22) {
            Text("フレーム  iron / bronze / platinum")
                .font(.caption).foregroundStyle(scheme == .dark ? .white : .black)
            HStack(spacing: 28) {
                framePreview("free_instrument_iron")
                framePreview("free_instrument_bronze")
                framePreview("free_instrument_platinum")
            }
            Text("カード  dawn / thread / night")
                .font(.caption).foregroundStyle(scheme == .dark ? .white : .black)
            VStack(spacing: 18) {
                cardPreview("free_dawn_horizon_panel")
                cardPreview("free_thread_border_panel")
                cardPreview("free_night_bloom_panel")
            }
        }
        .padding(40)
        .frame(width: 540)
        .background(canvas)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            Issue.record("failed to render \(name)")
            return
        }
        let url = outputDir.appendingPathComponent("\(name).png")
        try data.write(to: url)
    }

    private func framePreview(_ id: String) -> some View {
        let style = ProfileIconFrameCatalog.item(for: id)
        return ZStack {
            Circle().fill(accent.gradient).frame(width: 92, height: 92)
            Text("R").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            ProfileIconFrameView(style: style, accentColor: accent, size: 108)
        }
        .frame(width: 124, height: 124)
    }

    private func cardPreview(_ id: String) -> some View {
        let style = ProfileCardStyleCatalog.item(for: id)
        return ProfileDecoratedCardBackground(style: style, accentColor: accent, cornerRadius: 8)
            .frame(width: 420, height: 120)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(style.title).font(.headline).foregroundStyle(style.textColor)
                    Text("予定と実績のあいだ").font(.subheadline).foregroundStyle(style.secondaryTextColor)
                }
                .padding(.leading, 22)
            }
            .padding(8)
    }
}

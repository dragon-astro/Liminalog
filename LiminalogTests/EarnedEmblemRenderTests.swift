import SwiftUI
import Testing
@testable import Liminalog

/// 獲得勲章フレーム（EarnedEmblemFrame）のティア格差を目視確認するためのレンダラ。
/// プロダクトのテストではなく、デザインレビュー用に /tmp/liminal_mockups/ へ PNG を書き出す。
@MainActor
struct EarnedEmblemRenderTests {
    private let outputDir = URL(fileURLWithPath: "/tmp/liminal_mockups")
    private let accent = Color(hex: "#C9A7FF")

    @Test
    func renderEarnedTiers() throws {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try render(scheme: .dark, name: "earned_emblems_dark")
        try render(scheme: .light, name: "earned_emblems_light")
    }

    private func render(scheme: ColorScheme, name: String) throws {
        let canvas = scheme == .dark ? Color(hex: "#0D0B16") : Color(hex: "#FBF3E7")
        let text = scheme == .dark ? Color.white : Color.black

        // 生成PNG＋liminalオーラ合成。素材ランク（行）×アーキタイプ（列）で全20種。
        let ids = ProfileIconFrameCatalog.freeItems.map(\.id)
        let materials: [(String, String)] = [("iron", "鉄"), ("bronze", "銅"), ("silver", "銀"), ("gold", "金"), ("platinum", "白金")]

        let content = VStack(alignment: .leading, spacing: 16) {
            ForEach(materials, id: \.0) { key, label in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.caption).bold().foregroundStyle(text)
                    HStack(spacing: 16) {
                        ForEach(ids.filter { $0.contains(key) }, id: \.self) { id in
                            framePreview(id)
                        }
                    }
                }
            }
        }
        .padding(36)
        .frame(width: 620)
        .background(canvas)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            Issue.record("failed to render \(name)")
            return
        }
        try data.write(to: outputDir.appendingPathComponent("\(name).png"))
    }

    private func framePreview(_ id: String) -> some View {
        let style = ProfileIconFrameCatalog.item(for: id)
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(accent.gradient).frame(width: 78, height: 78)
                Text("R").font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                ProfileIconFrameView(style: style, accentColor: accent, size: 96)
            }
            .frame(width: 108, height: 108)
            Text(style.title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

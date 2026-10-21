// macOS 上で SwiftUI の描画結果を PNG に書き出す確認用ツール。
// 使い方: ./render.sh [masters|sheets|all]
import AppKit
import SwiftUI

@MainActor
func writePNG<V: View>(_ view: V, scale: CGFloat, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { print("render failed: \(url.lastPathComponent)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
    print("wrote \(url.lastPathComponent) \(cg.width)x\(cg.height)")
}

@main
struct RenderMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        let studyDir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
        let mode = args.count > 2 ? args[2] : "all"
        let out = studyDir.appendingPathComponent("renders")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = studyDir.deletingLastPathComponent().deletingLastPathComponent()
        OriginalArt.root = repo.appendingPathComponent("decoration-masters")

        if mode == "masters" || mode == "all" {
            for m in Motif.allCases {
                writePNG(CodeFrameCanvas(motif: m, side: 1024, pixelScale: 1), scale: 1, to: out.appendingPathComponent("code-\(m.rawValue)-frame-1024.png"))
                writePNG(CodeCardView(motif: m, pixelScale: 2).frame(width: 920, height: 570).padding(.horizontal, 52).padding(.vertical, 35), scale: 2, to: out.appendingPathComponent("code-\(m.rawValue)-card-2048.png"))
            }
        }
        if mode == "sheets" || mode == "all" {
            for m in Motif.allCases {
                writePNG(MasterComparisonSheet(motif: m), scale: 1, to: out.appendingPathComponent("compare-master-\(m.rawValue).png"))
                writePNG(AvatarSizeSheet(motif: m), scale: 3, to: out.appendingPathComponent("avatar-sizes-\(m.rawValue).png"))
                writePNG(ProfileSheet(motif: m), scale: 3, to: out.appendingPathComponent("profile-\(m.rawValue).png"))
                writePNG(ListSheet(motif: m), scale: 3, to: out.appendingPathComponent("list-\(m.rawValue).png"))
            }
            writePNG(OverviewSheet(), scale: 2, to: out.appendingPathComponent("overview.png"))
        }
        if mode == "plain" || mode == "all" {
            // 数値検査用：文字を載せないカード背景（本体 hero と同じ 350×226・@3x）
            for m in Motif.allCases {
                for v in Variant.compared {
                    writePNG(CardBackground(variant: v, motif: m, pixelScale: 3).frame(width: 350, height: 226), scale: 3,
                             to: out.appendingPathComponent("plain-card-\(v.rawValue)-\(m.rawValue).png"))
                }
            }
        }
        if mode == "timing" {
            // 描画時間の目安（macOS・ImageRenderer。実機の描画時間ではない）
            func time<V: View>(_ label: String, _ view: V, scale: CGFloat) {
                func once() { let r = ImageRenderer(content: view); r.scale = scale; _ = r.cgImage }
                once()
                let n = 10
                let t0 = Date()
                for _ in 0..<n { once() }
                print(String(format: "%@: %.1f ms / render", label, Date().timeIntervalSince(t0) * 1000 / Double(n)))
            }
            for m in Motif.allCases {
                time("\(m.rawValue) frame 82pt@3x", CodeFrameView(motif: m, size: 98, pixelScale: 3), scale: 3)
                time("\(m.rawValue) frame 32pt@3x", CodeFrameView(motif: m, size: 39, pixelScale: 3), scale: 3)
                time("\(m.rawValue) card 350x226@3x", CodeCardView(motif: m, pixelScale: 3).frame(width: 350, height: 226), scale: 3)
                time("\(m.rawValue) card 120x75@3x", CodeCardView(motif: m, pixelScale: 3).frame(width: 120, height: 75), scale: 3)
                time("\(m.rawValue) PNG frame 82pt@3x (比較)", FramedAvatar(variant: .original, motif: m, size: 82, heroRule: true), scale: 3)
            }
        }
        #if WITH_CODEX
        if mode == "codex" {
            CodexBridge.install()
            for m in Motif.allCases {
                writePNG(ThreeWaySheet(motif: m), scale: 3, to: out.appendingPathComponent("compare-3way-\(m.rawValue).png"))
            }
        }
        #endif
    }
}

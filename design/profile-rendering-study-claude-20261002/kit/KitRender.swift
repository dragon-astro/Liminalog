// macOS 上で確認用PNGを書き出す。  ./render.sh [motif <id…>|lineup|masters|timing|all]
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
struct KitRender {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        let kitDir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
        let mode = args.count > 2 ? args[2] : "all"
        let extra = Array(args.dropFirst(3))
        let out = kitDir.appendingPathComponent("renders")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = kitDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        PNGReference.root = repo.appendingPathComponent("decoration-masters")

        let ids: [DecorationID] = extra.isEmpty ? DecoCatalog.implemented : extra.compactMap { e in
            DecorationID.allCases.first { $0.rawValue == e || $0.rawValue == "free_" + e }
        }

        if mode == "motif" || mode == "all" {
            for id in ids {
                writePNG(KitMotifSheet(id: id), scale: 3, to: out.appendingPathComponent("motif-\(id.rawValue.replacingOccurrences(of: "free_", with: "")).png"))
            }
        }
        if mode == "lineup" || mode == "all" {
            for s in DecoScheme.allCases {
                writePNG(KitLineupSheet(scheme: s, ids: DecoCatalog.implemented), scale: 2, to: out.appendingPathComponent("lineup-\(s.rawValue).png"))
                writePNG(KitGallerySheet(scheme: s, ids: DecoCatalog.implemented), scale: 3, to: out.appendingPathComponent("gallery-\(s.rawValue).png"))
            }
        }
        if mode == "grid" || mode == "all" {
            let all = DecoCatalog.implemented
            writePNG(KitCompareGridSheet(ids: Array(all.prefix(10)), title: "(1/2)"), scale: 3, to: out.appendingPathComponent("compare-grid-1.png"))
            writePNG(KitCompareGridSheet(ids: Array(all.dropFirst(10)), title: "(2/2)"), scale: 3, to: out.appendingPathComponent("compare-grid-2.png"))
        }
        if mode == "plain" || mode == "all" {
            // 数値検査用：文字を載せないカード背景（本体 hero と同じ 350×226・@3x）とフレーム原寸（1024px・透過）
            let plain = out.appendingPathComponent("plain")
            try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
            for id in ids {
                let name = id.rawValue.replacingOccurrences(of: "free_", with: "")
                for s in DecoScheme.allCases {
                    writePNG(DecoCardView(id: id, scheme: s, pixelScale: 3).frame(width: 350, height: 226), scale: 3,
                             to: plain.appendingPathComponent("card-\(name)-\(s.rawValue).png"))
                    writePNG(DecoFrameCanvas(id: id, side: 1024, pixelScale: 1, scheme: s), scale: 1,
                             to: plain.appendingPathComponent("frame-\(name)-\(s.rawValue).png"))
                }
            }
        }
        if mode == "masters" {
            for id in ids {
                for s in DecoScheme.allCases {
                    let name = id.rawValue.replacingOccurrences(of: "free_", with: "")
                    writePNG(ZStack { s.canvas.c(); DecoFrameCanvas(id: id, side: 1024, pixelScale: 1, scheme: s) }.frame(width: 1024, height: 1024),
                             scale: 1, to: out.appendingPathComponent("master-frame-\(name)-\(s.rawValue).png"))
                    writePNG(ZStack { s.canvas.c(); DecoCardView(id: id, scheme: s, pixelScale: 2).frame(width: 920, height: 570) }.frame(width: 1024, height: 640),
                             scale: 2, to: out.appendingPathComponent("master-card-\(name)-\(s.rawValue).png"))
                }
            }
        }
        if mode == "timing" {
            func time<V: View>(_ label: String, _ view: V, scale: CGFloat) {
                func once() { let r = ImageRenderer(content: view); r.scale = scale; _ = r.cgImage }
                once()
                let n = 6
                let t0 = Date()
                for _ in 0..<n { once() }
                print(String(format: "%@: %.1f ms", label, Date().timeIntervalSince(t0) * 1000 / Double(n)))
            }
            for id in ids {
                for s in DecoScheme.allCases {
                    time("\(id.rawValue) \(s.rawValue) frame 82pt@3x", DecoFrameView(id: id, size: 98, scheme: s, pixelScale: 3), scale: 3)
                    time("\(id.rawValue) \(s.rawValue) card 350x226@3x", DecoCardView(id: id, scheme: s, pixelScale: 3).frame(width: 350, height: 226), scale: 3)
                }
            }
            // キャッシュ経由（2回目以降は画像を貼るだけ）
            let id = DecorationID.leafCorner
            _ = DecoRasterCache.shared.frame(id: id, side: 98 * 1.12, scale: 3, scheme: .dusk)
            time("cached frame 82pt@3x (2回目以降)", DecoFrameView(id: id, size: 98, scheme: .dusk, pixelScale: 3, cached: true), scale: 3)
        }
    }
}

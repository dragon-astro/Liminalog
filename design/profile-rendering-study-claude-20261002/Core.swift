// Liminalog profile decoration — code-rendering study (Claude, 2026-10-02)
//
// 採用前の実験。本体コード・アセット・カタログとは無関係に、このフォルダの Swift だけで
// 「葉隅」「星図線」のプロフィールカード/アバターフレームを SwiftUI Canvas で描く。
// 装飾本体に画像生成・既存PNGの貼り込みは一切使わない（既存PNGは比較表示にのみ使う）。
//
// 座標系の約束（本体の画像アセットと同じジオメトリで差し替え比較できるようにする）
//  - フレーム: 本体 `ProfileIconFrameView(size: S)` と同じ `size` を受け取り、
//    S × 1.12（本体の contentScale）の正方形に描く。1024px マスターで
//    アバター半径 = 383px に相当する長さを「1 unit」とする。
//  - カード: 渡された矩形にそのまま描く（画像のような scaledToFill/offset 補正は不要）。
//  - LOD: 実ピクセル数（pt × displayScale）から細部の出し入れ・最小線幅を決める。

import SwiftUI

// MARK: - Deterministic random

struct SeededRNG {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0x632BE59BD9B4E019 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
    mutating func chance(_ p: CGFloat) -> Bool { unit() < p }
    mutating func sign() -> CGFloat { chance(0.5) ? 1 : -1 }
    mutating func gauss() -> CGFloat {
        let u1 = max(unit(), 1e-9), u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
    mutating func pick<T>(_ items: [T]) -> T { items[Int(unit() * CGFloat(items.count)) % items.count] }
}

// MARK: - Color

struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func c(_ a: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - Geometry helpers

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var length: CGFloat { sqrt(x * x + y * y) }
    var angle: CGFloat { atan2(y, x) }
    static func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: r * cos(a), y: r * sin(a)) }
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { a + (b - a) * t }
func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

/// Catmull-Rom を3次ベジェへ変換した滑らかな曲線。
func smoothPath(_ p: [CGPoint], closed: Bool, tension: CGFloat = 1) -> Path {
    var path = Path()
    guard p.count > 1 else { return path }
    let n = p.count
    path.move(to: p[0])
    let segs = closed ? n : n - 1
    for i in 0..<segs {
        let p0 = closed ? p[(i - 1 + n) % n] : p[max(i - 1, 0)]
        let p1 = p[i]
        let p2 = p[(i + 1) % n]
        let p3 = closed ? p[(i + 2) % n] : p[min(i + 2, n - 1)]
        let c1 = p1 + (p2 - p0) * (tension / 6)
        let c2 = p2 - (p3 - p1) * (tension / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    if closed { path.closeSubpath() }
    return path
}

func quadPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return a * (u * u) + c * (2 * u * t) + b * (t * t)
}

func quadTangent(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    (c - a) * (2 * (1 - t)) + (b - c) * (2 * t)
}

/// 描画順（z）付きの描画命令。重なりの前後関係を素材横断でソートするため。
struct DrawOp {
    var z: Double
    var draw: (GraphicsContext) -> Void
}

/// 線幅や細部の出し入れを決める解像度情報。
struct Detail {
    /// 1 unit が何 px になるか。
    var pxPerUnit: CGFloat
    func minWidth(_ px: CGFloat) -> CGFloat { px / pxPerUnit }
    func w(_ units: CGFloat, minPx: CGFloat = 0.6) -> CGFloat { max(units, minWidth(minPx)) }
    func px(_ units: CGFloat) -> CGFloat { units * pxPerUnit }
    /// フレーム用の詳細度。0 = 24pt級の極小表示、1 = 82pt hero(@3x)以上。
    var quality: CGFloat { max(0, min(1, (pxPerUnit - 38) / (118 - 38))) }
}

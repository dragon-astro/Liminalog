// Liminalog プロフィール装飾キット（コード描画・試作）— 共通の土台
//
// 採用前の実験。本体コード・アセット・カタログとは無関係で、このフォルダの Swift だけで描く。
// 装飾本体に画像生成・既存PNGは使わない（既存PNGは比較表示にのみ使う）。
//
// 座標の約束
//  - フレーム：本体 `ProfileIconFrameView(size: S)` と同じ S を受け取り、S × 1.12 の正方形に描く。
//    1024px マスターでのアバター半径 383px を「1 unit」とし、リング中心線をアバター境界(1.0)に置く。
//    描いてよい範囲は半径 0.86〜1.30（キャンバス端は 1.337）。
//  - カード：渡された矩形に直接描く（350×226 を k=1 の基準とする）。縁から 12k まではみ出してよい。
//  - LOD：実ピクセル密度から detail.quality（0=24pt級 … 1=82pt hero@3x）を出し、細部を出し入れする。

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
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(UInt32(s, radix: 16) ?? 0xFF00FF)
    }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func c(_ a: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    static let white = RGB(0xFFFFFF)
    static let black = RGB(0x000000)

    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h / 6, s, l)
    }

    init(h: Double, s: Double, l: Double) {
        func f(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if s == 0 { self.init(r: l, g: l, b: l); return }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(r: f(p, q, h + 1 / 3), g: f(p, q, h), b: f(p, q, h - 1 / 3))
    }

    /// 色相を保ったまま明度だけ置き換える（ライト地用の「墨色」を作る）。
    func withLightness(_ l: Double, saturationBoost: Double = 1) -> RGB {
        let v = hsl
        return RGB(h: v.h, s: min(1, v.s * saturationBoost), l: l)
    }

    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

// MARK: - Geometry

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var length: CGFloat { sqrt(x * x + y * y) }
    var angle: CGFloat { atan2(y, x) }
    var normalized: CGPoint { let l = max(length, 1e-9); return CGPoint(x: x / l, y: y / l) }
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }
    static func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: r * cos(a), y: r * sin(a)) }
    func rotated(_ a: CGFloat) -> CGPoint { CGPoint(x: x * cos(a) - y * sin(a), y: x * sin(a) + y * cos(a)) }
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { a + (b - a) * t }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { let t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t) }

/// 角度差（-π…π）
func angleDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

/// 角度 c を中心にした幅 w のガウス山
func angularBump(_ a: CGFloat, _ cDeg: CGFloat, _ wDeg: CGFloat) -> CGFloat {
    let dd = angleDelta(a, deg(cDeg))
    return exp(-(dd * dd) / (2 * deg(wDeg) * deg(wDeg)))
}

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

func disc(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }

/// 不規則な輪郭の閉曲線（しみ・雲・石）。完全な円は「コードで描いた」感が出るので使わない。
func organicBlob(radius R: CGFloat, rng: inout SeededRNG, points n: Int = 11, roughness: CGFloat = 0.22, center: CGPoint = .zero) -> Path {
    let ph1 = rng.range(0, 6), ph2 = rng.range(0, 6)
    var pts: [CGPoint] = []
    for i in 0..<n {
        let a = 2 * .pi * (CGFloat(i) + rng.range(-0.2, 0.2)) / CGFloat(n)
        let wobble = 0.6 * sin(2 * a + ph1) + 0.4 * sin(3 * a + ph2)
        let r = R * (1 + roughness * wobble + rng.range(-roughness, roughness) * 0.45)
        pts.append(center + CGPoint.polar(r, a))
    }
    return smoothPath(pts, closed: true)
}

/// 先細りの線。点列に沿って幅を補間しながら短い線分で描く（不透明色で使うと継ぎ目が出ない）。
func drawTaperedStroke(_ ctx: GraphicsContext, points: [CGPoint], widths: [CGFloat], color: RGB, alpha: Double) {
    guard points.count > 1 else { return }
    for i in 0..<(points.count - 1) {
        var seg = Path()
        seg.move(to: points[i])
        seg.addLine(to: points[i + 1])
        ctx.stroke(seg, with: .color(color.c(alpha)), style: StrokeStyle(lineWidth: (widths[i] + widths[i + 1]) / 2, lineCap: .round))
    }
}

/// 太さと濃さが変わる線（半透明でも継ぎ目に玉が出ないよう butt で繋ぐ）。
func drawVaryingStroke(_ ctx: GraphicsContext, points: [CGPoint], widths: [CGFloat], alphas: [Double], color: RGB) {
    guard points.count > 1 else { return }
    for i in 0..<(points.count - 1) {
        let a = (alphas[i] + alphas[i + 1]) / 2
        guard a > 0.01 else { continue }
        var seg = Path()
        seg.move(to: points[i])
        seg.addLine(to: points[i + 1])
        ctx.stroke(seg, with: .color(color.c(a)), style: StrokeStyle(lineWidth: (widths[i] + widths[i + 1]) / 2, lineCap: .butt))
    }
}

/// 太さが変わる帯を「面」として塗る（半透明でも継ぎ目が出ない先細り線）。
func ribbonPath(_ pts: [CGPoint], widths: [CGFloat]) -> Path {
    guard pts.count > 1 else { return Path() }
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0..<pts.count {
        let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
        let n = (b - a).normalized.perpendicular
        left.append(pts[i] + n * (widths[i] / 2))
        right.append(pts[i] - n * (widths[i] / 2))
    }
    var p = smoothPath(left, closed: false)
    for q in right.reversed() { p.addLine(to: q) }
    p.closeSubpath()
    return p
}

// MARK: - Draw ops / detail

/// 描画順（z）付きの描画命令。素材をまたいで前後関係をソートするため。
struct DrawOp {
    var z: Double
    var draw: (GraphicsContext) -> Void
}

/// 線幅や細部の出し入れを決める解像度情報。
struct Detail {
    var pxPerUnit: CGFloat
    func minWidth(_ px: CGFloat) -> CGFloat { px / pxPerUnit }
    func w(_ units: CGFloat, minPx: CGFloat = 0.6) -> CGFloat { max(units, minWidth(minPx)) }
    func px(_ units: CGFloat) -> CGFloat { units * pxPerUnit }
    /// フレームの詳細度。0 = 24pt級、1 = 82pt hero(@3x)以上。
    var quality: CGFloat { max(0, min(1, (pxPerUnit - 38) / (118 - 38))) }
    /// 小さい表示ほど要素を大きく・少なく
    var boost: CGFloat { 1 + 0.55 * (1 - quality) }
    var keep: CGFloat { 0.36 + 0.64 * quality }
}

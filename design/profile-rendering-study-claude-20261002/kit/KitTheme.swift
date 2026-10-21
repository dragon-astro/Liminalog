// テーマ（宵／曙）とアイテム固有色。値は本体の LiminalThemeDefinition / ProfileDecorations から写した。
import SwiftUI

/// 本体のデフォルト2テーマ。装飾はどちらでも「設計された見た目」になるよう、描画時に解決する。
enum DecoScheme: String, CaseIterable, Identifiable {
    case dusk, daybreak
    var id: String { rawValue }
    var title: String { self == .dusk ? "宵" : "曙" }
    var isDark: Bool { self == .dusk }

    // LiminalThemeCatalog.dusk / .daybreak の palette
    var canvas: RGB { isDark ? RGB(0x0D0B16) : RGB(0xFAF5EE) }
    var surface: RGB { isDark ? RGB(0x17132A) : RGB(0xFFFDF9) }
    var elevated: RGB { isDark ? RGB(0x1F1A38) : RGB(0xFFFFFF) }
    var cardBottom: RGB { isDark ? RGB(0x231B36) : RGB(0xFFF6EC) }
    var divider: RGB { isDark ? RGB(0x2A2442) : RGB(0xECE0D6) }
    var text: RGB { isDark ? RGB(0xECE8F5) : RGB(0x2F2A30) }
    var secondaryText: RGB { isDark ? RGB(0x9A93B5) : RGB(0x6B6166) }
    var reward: RGB { isDark ? RGB(0xFFE3A3) : RGB(0xE0A94E) }
    var dawn: RGB { isDark ? RGB(0xFFB3C7) : RGB(0xF9D2AE) }
    /// 曙は「暖かい光の地 × 暖色の柔らかい影 × 金のリム」（golden hour）
    var shadow: RGB { isDark ? RGB(0x000000) : RGB(0xA7774F) }
    var rim: RGB { isDark ? RGB(0xFFFFFF) : RGB(0xE0A94E) }
}

/// アイテム固有色（catalog の primaryHex / secondaryHex）。宵では発光色のまま、曙では同じ色相の深い墨色にする。
struct ItemPalette {
    let primary: RGB
    let secondary: RGB

    init(_ p: String, _ s: String) {
        primary = RGB(hex: p)
        secondary = RGB(hex: s)
    }

    private static func ink(_ c: RGB, l: Double) -> RGB {
        let v = c.hsl
        return RGB(h: v.h, s: min(v.s, 0.72), l: min(v.l, l))
    }

    /// 主線
    func line(_ s: DecoScheme) -> RGB { s.isDark ? primary : Self.ink(primary, l: 0.40) }
    /// 副線
    func line2(_ s: DecoScheme) -> RGB { s.isDark ? secondary : Self.ink(secondary, l: 0.46) }
    /// 面の主色（塗り）
    func fill(_ s: DecoScheme) -> RGB { s.isDark ? primary : Self.ink(primary, l: 0.56) }
    func fill2(_ s: DecoScheme) -> RGB { s.isDark ? secondary : Self.ink(secondary, l: 0.6) }
    /// 明るいハイライト
    func highlight(_ s: DecoScheme) -> RGB { s.isDark ? primary.mix(.white, 0.62) : RGB.white }
    /// 影・奥
    func deep(_ s: DecoScheme) -> RGB { s.isDark ? Self.ink(primary, l: 0.2) : Self.ink(primary, l: 0.28) }
    /// 控えめな発光（宵のみ。doc16 §3：下支えに留める）
    func glow(_ s: DecoScheme) -> (RGB, Double)? { s.isDark ? (primary, 0.34) : nil }
}

/// 個性（無料・かけら交換）カード／フレーム 20 対。ID・名前・色は ProfileDecorations.swift のまま。
enum DecorationID: String, CaseIterable, Identifiable {
    case dawnHorizon = "free_dawn_horizon"
    case rippleBorder = "free_ripple_border"
    case cloudVeil = "free_cloud_veil"
    case leafCorner = "free_leaf_corner"
    case frostEdge = "free_frost_edge"
    case threadBorder = "free_thread_border"
    case orbitGrid = "free_orbit_grid"
    case rain = "free_rain"
    case candle = "free_candle"
    case ink = "free_ink"
    case auroraTrace = "free_aurora_trace"
    case glassBead = "free_glass_bead"
    case linenStitch = "free_linen_stitch"
    case constellation = "free_constellation"
    case wave = "free_wave"
    case mist = "free_mist"
    case petalCorner = "free_petal_corner"
    case stonePath = "free_stone_path"
    case sunline = "free_sunline"
    case nightBloom = "free_night_bloom"

    var id: String { rawValue }

    var info: (title: String, primary: String, secondary: String) {
        switch self {
        case .dawnHorizon: return ("暁線", "#FFB3C7", "#FFC98A")
        case .rippleBorder: return ("水縁", "#39D5E8", "#7DD3FC")
        case .cloudVeil: return ("雲幕", "#9BDCF8", "#FFB3C7")
        case .leafCorner: return ("葉隅", "#5FE0A8", "#C9A7FF")
        case .frostEdge: return ("霜縁", "#8AB4FF", "#D8ECFF")
        case .threadBorder: return ("糸枠", "#C9A7FF", "#FFB3C7")
        case .orbitGrid: return ("軌跡線", "#7DD3FC", "#C9A7FF")
        case .rain: return ("雨粒", "#7DD3FC", "#39D5E8")
        case .candle: return ("灯影", "#FF8A5B", "#FFB3C7")
        case .ink: return ("墨縁", "#A78BFA", "#C9A7FF")
        case .auroraTrace: return ("極光線", "#5FE0A8", "#7DD3FC")
        case .glassBead: return ("硝子点", "#39D5E8", "#C9A7FF")
        case .linenStitch: return ("織目", "#C9A7FF", "#D8CEE8")
        case .constellation: return ("星図線", "#7DD3FC", "#FFE3A3")
        case .wave: return ("波端", "#39D5E8", "#8AB4FF")
        case .mist: return ("霧面", "#C9A7FF", "#D8ECFF")
        case .petalCorner: return ("花隅", "#FF8FB3", "#A78BFA")
        case .stonePath: return ("石径", "#5FE0A8", "#FFE3A3")
        case .sunline: return ("陽線", "#FFC98A", "#FF8FB3")
        case .nightBloom: return ("夜花", "#FF8FB3", "#C9A7FF")
        }
    }

    var title: String { info.title }
    var palette: ItemPalette { ItemPalette(info.primary, info.secondary) }
    var pngFrameName: String { "profile_frame_\(rawValue)" }
    var pngCardName: String { "profile_card_\(rawValue)_panel" }
}

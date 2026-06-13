import SwiftUI
import UIKit

struct ProfileBadgeModel: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: String
    let isUnlocked: Bool
    let progressText: String
}

enum ProfileBadgeCatalog {
    static let noneBadge = ProfileBadgeModel(
        id: ProfileDecorationUnlocks.noNameBadgeID,
        title: "なし",
        systemImage: "minus.circle",
        tint: "#8E879F",
        isUnlocked: true,
        progressText: "初期"
    )

    static let defaultBadge = ProfileBadgeModel(
        id: ProfileDecorationUnlocks.defaultNameBadgeID,
        title: "ルーキー",
        systemImage: "person.crop.circle.fill.badge.checkmark",
        tint: "#2F80ED",
        isUnlocked: true,
        progressText: "初期"
    )

    static func items(metrics: UnlockMetrics, unlockItems: [UnlockItem], includesLockedItems: Bool = false) -> [ProfileBadgeModel] {
        let unlockedIDs = ProfileDecorationUnlocks(
            unlockItems: unlockItems,
            includesLockedCatalogItems: includesLockedItems
        ).nameBadgeIDs
        let unlockBadges = unlockItems
            .filter { $0.kind == .nameBadge }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.key < $1.key
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map { item in
                ProfileBadgeModel(
                    id: item.targetID,
                    title: item.displayName,
                    systemImage: item.systemImageName,
                    tint: item.tintHex,
                    isUnlocked: unlockedIDs.contains(item.targetID),
                    progressText: progressText(metrics: metrics, item: item)
                )
            }
        return [noneBadge, defaultBadge] + unlockBadges
    }

    static func equippedBadge(id: String?, badges: [ProfileBadgeModel]) -> ProfileBadgeModel {
        if id == ProfileDecorationUnlocks.noNameBadgeID {
            return noneBadge
        }
        if let id, let selected = badges.first(where: { $0.id == id && $0.isUnlocked }) {
            return selected
        }
        return defaultBadge
    }

    private static func progressText(metrics: UnlockMetrics, item: UnlockItem) -> String {
        if item.unlockedAt != nil {
            return "達成"
        }
        guard item.requiredValue > 0 else { return "0%" }
        let percent = Int((UnlockRules.progress(metrics: metrics, toward: item) * 100).rounded(.down))
        return "\(percent)%"
    }
}

struct ProfileIconFrameStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let primaryHex: String
    let secondaryHex: String
    let lineWidth: CGFloat

    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
    var artworkAssetName: String { "profile_frame_\(id)" }

    var hasGeneratedArtwork: Bool {
        ProfileIconFrameCatalog.generatedArtworkIDs.contains(id)
    }
}

enum ProfileIconFrameCatalog {
    static let noneItem = ProfileIconFrameStyle(id: ProfileDecorationUnlocks.noIconFrameID, title: "なし", systemImage: "minus.circle", primaryHex: "#8E879F", secondaryHex: "#8E879F", lineWidth: 0)
    static let defaultID = ProfileDecorationUnlocks.defaultIconFrameID
    static let defaultItem = ProfileIconFrameStyle(id: defaultID, title: "澄空", systemImage: "circle", primaryHex: "#7DD3FC", secondaryHex: "#C9A7FF", lineWidth: 3)
    static let instrumentItems: [ProfileIconFrameStyle] = [
        instrument("iron", primaryHex: "#59606B", secondaryHex: "#8B6BFF", lineWidth: 3),
        instrument("bronze", primaryHex: "#B87545", secondaryHex: "#F0A2A2", lineWidth: 3),
        instrument("silver", primaryHex: "#D8DEE8", secondaryHex: "#39D5E8", lineWidth: 4),
        instrument("gold", primaryHex: "#F2C94C", secondaryHex: "#FFB3C7", lineWidth: 4),
        instrument("platinum", primaryHex: "#F2F4FF", secondaryHex: "#8AB4FF", lineWidth: 5),
        instrument("iron_seal", primaryHex: "#59606B", secondaryHex: "#8B6BFF", lineWidth: 3),
        instrument("bronze_seal", primaryHex: "#B87545", secondaryHex: "#F0A2A2", lineWidth: 3),
        instrument("silver_seal", primaryHex: "#D8DEE8", secondaryHex: "#39D5E8", lineWidth: 4),
        instrument("gold_seal", primaryHex: "#F2C94C", secondaryHex: "#FFB3C7", lineWidth: 4),
        instrument("platinum_seal", primaryHex: "#F2F4FF", secondaryHex: "#8AB4FF", lineWidth: 5),
        instrument("iron_orbit", primaryHex: "#59606B", secondaryHex: "#8B6BFF", lineWidth: 3),
        instrument("bronze_orbit", primaryHex: "#B87545", secondaryHex: "#F0A2A2", lineWidth: 3),
        instrument("silver_orbit", primaryHex: "#D8DEE8", secondaryHex: "#39D5E8", lineWidth: 4),
        instrument("gold_orbit", primaryHex: "#F2C94C", secondaryHex: "#FFB3C7", lineWidth: 4),
        instrument("platinum_orbit", primaryHex: "#F2F4FF", secondaryHex: "#8AB4FF", lineWidth: 5),
        instrument("iron_crest", primaryHex: "#59606B", secondaryHex: "#8B6BFF", lineWidth: 3),
        instrument("bronze_crest", primaryHex: "#B87545", secondaryHex: "#F0A2A2", lineWidth: 3),
        instrument("silver_crest", primaryHex: "#D8DEE8", secondaryHex: "#39D5E8", lineWidth: 4),
        instrument("gold_crest", primaryHex: "#F2C94C", secondaryHex: "#FFB3C7", lineWidth: 4),
        instrument("platinum_crest", primaryHex: "#F2F4FF", secondaryHex: "#8AB4FF", lineWidth: 5)
    ]

    static let personalityItems: [ProfileIconFrameStyle] = [
        personality(id: "free_dawn_horizon", title: "暁線", systemImage: "sunrise.fill", primaryHex: "#FFB3C7", secondaryHex: "#FFC98A"),
        personality(id: "free_ripple_border", title: "水縁", systemImage: "water.waves", primaryHex: "#39D5E8", secondaryHex: "#7DD3FC"),
        personality(id: "free_cloud_veil", title: "雲幕", systemImage: "cloud.fill", primaryHex: "#9BDCF8", secondaryHex: "#FFB3C7"),
        personality(id: "free_leaf_corner", title: "葉隅", systemImage: "leaf.fill", primaryHex: "#5FE0A8", secondaryHex: "#C9A7FF"),
        personality(id: "free_frost_edge", title: "霜縁", systemImage: "snowflake", primaryHex: "#8AB4FF", secondaryHex: "#D8ECFF"),
        personality(id: "free_thread_border", title: "糸枠", systemImage: "scribble.variable", primaryHex: "#C9A7FF", secondaryHex: "#FFB3C7"),
        personality(id: "free_orbit_grid", title: "軌跡線", systemImage: "scope", primaryHex: "#7DD3FC", secondaryHex: "#C9A7FF"),
        personality(id: "free_rain", title: "雨粒", systemImage: "cloud.rain.fill", primaryHex: "#7DD3FC", secondaryHex: "#39D5E8"),
        personality(id: "free_candle", title: "灯影", systemImage: "flame.fill", primaryHex: "#FF8A5B", secondaryHex: "#FFB3C7"),
        personality(id: "free_ink", title: "墨縁", systemImage: "paintbrush.pointed.fill", primaryHex: "#A78BFA", secondaryHex: "#C9A7FF"),
        personality(id: "free_aurora_trace", title: "極光線", systemImage: "sparkles", primaryHex: "#5FE0A8", secondaryHex: "#7DD3FC"),
        personality(id: "free_glass_bead", title: "硝子点", systemImage: "drop.circle.fill", primaryHex: "#39D5E8", secondaryHex: "#C9A7FF"),
        personality(id: "free_linen_stitch", title: "織目", systemImage: "circle.dashed", primaryHex: "#C9A7FF", secondaryHex: "#D8CEE8"),
        personality(id: "free_constellation", title: "星図線", systemImage: "scope", primaryHex: "#7DD3FC", secondaryHex: "#FFE3A3"),
        personality(id: "free_wave", title: "波端", systemImage: "water.waves", primaryHex: "#39D5E8", secondaryHex: "#8AB4FF"),
        personality(id: "free_mist", title: "霧面", systemImage: "circle.dotted", primaryHex: "#C9A7FF", secondaryHex: "#D8ECFF"),
        personality(id: "free_petal_corner", title: "花隅", systemImage: "camera.macro", primaryHex: "#FF8FB3", secondaryHex: "#A78BFA"),
        personality(id: "free_stone_path", title: "石径", systemImage: "point.topleft.down.curvedto.point.bottomright.up", primaryHex: "#5FE0A8", secondaryHex: "#FFE3A3"),
        personality(id: "free_sunline", title: "陽線", systemImage: "sunrise.fill", primaryHex: "#FFC98A", secondaryHex: "#FF8FB3"),
        personality(id: "free_night_bloom", title: "夜花", systemImage: "camera.macro", primaryHex: "#FF8FB3", secondaryHex: "#C9A7FF")
    ]

    static let freeItems: [ProfileIconFrameStyle] = instrumentItems + personalityItems

    static let legacyItems: [ProfileIconFrameStyle] = [
        ProfileIconFrameStyle(id: "cloud_veil", title: "雲間", systemImage: "cloud.fill", primaryHex: "#9BDCF8", secondaryHex: "#FFB3C7", lineWidth: 3),
        ProfileIconFrameStyle(id: "ripple_ring", title: "水紋", systemImage: "water.waves", primaryHex: "#39D5E8", secondaryHex: "#7DD3FC", lineWidth: 3),
        ProfileIconFrameStyle(id: "leaf_orbit", title: "若葉環", systemImage: "leaf.fill", primaryHex: "#5FE0A8", secondaryHex: "#C9A7FF", lineWidth: 3),
        ProfileIconFrameStyle(id: "dawn_pollen", title: "朝露", systemImage: "sunrise.fill", primaryHex: "#FF8FB3", secondaryHex: "#FFC98A", lineWidth: 3),
        ProfileIconFrameStyle(id: "frost_bloom", title: "霜晶", systemImage: "snowflake", primaryHex: "#8AB4FF", secondaryHex: "#D8ECFF", lineWidth: 3),
        ProfileIconFrameStyle(id: "thread_arc", title: "刺繍糸", systemImage: "scribble.variable", primaryHex: "#C9A7FF", secondaryHex: "#FFB3C7", lineWidth: 2),
        ProfileIconFrameStyle(id: "wisteria_loop", title: "藤環", systemImage: "camera.macro", primaryHex: "#A78BFA", secondaryHex: "#5FE0A8", lineWidth: 3),
        ProfileIconFrameStyle(id: "laurel_light", title: "月桂", systemImage: "leaf.circle.fill", primaryHex: "#5FE0A8", secondaryHex: "#FFE3A3", lineWidth: 3),
        ProfileIconFrameStyle(id: "astro_chart", title: "星図", systemImage: "scope", primaryHex: "#7DD3FC", secondaryHex: "#C9A7FF", lineWidth: 2),
        ProfileIconFrameStyle(id: "petal_wreath", title: "花輪", systemImage: "camera.macro", primaryHex: "#FF8FB3", secondaryHex: "#A78BFA", lineWidth: 3),
        ProfileIconFrameStyle(id: "aurora_wreath", title: "極光環", systemImage: "sparkles", primaryHex: "#5FE0A8", secondaryHex: "#D946EF", lineWidth: 4),
        ProfileIconFrameStyle(id: "kintsugi_ring", title: "金継ぎ", systemImage: "line.diagonal", primaryHex: "#FFC98A", secondaryHex: "#C9A7FF", lineWidth: 3),
        ProfileIconFrameStyle(id: "porcelain_halo", title: "白磁", systemImage: "circle.hexagongrid.fill", primaryHex: "#D8ECFF", secondaryHex: "#8AB4FF", lineWidth: 2),
        ProfileIconFrameStyle(id: "tideglass_ring", title: "潮硝子", systemImage: "drop.fill", primaryHex: "#39D5E8", secondaryHex: "#5FE0A8", lineWidth: 3),
        ProfileIconFrameStyle(id: "ember_vine", title: "灯蔓", systemImage: "flame.fill", primaryHex: "#FF8A5B", secondaryHex: "#FFB3C7", lineWidth: 3),
        ProfileIconFrameStyle(id: "prism_dew", title: "虹露", systemImage: "drop.circle.fill", primaryHex: "#C9A7FF", secondaryHex: "#5FE0A8", lineWidth: 3),
        ProfileIconFrameStyle(id: "snow_crest", title: "雪冠", systemImage: "snowflake", primaryHex: "#D8ECFF", secondaryHex: "#7DD3FC", lineWidth: 3),
        ProfileIconFrameStyle(id: "chrono_orbit", title: "時環", systemImage: "timer", primaryHex: "#7DD3FC", secondaryHex: "#FFE3A3", lineWidth: 3),
        ProfileIconFrameStyle(id: "lacquer_vein", title: "漆脈", systemImage: "seal.fill", primaryHex: "#FFC98A", secondaryHex: "#D946EF", lineWidth: 3),
        ProfileIconFrameStyle(id: "twilight_orbit", title: "薄明軌", systemImage: "sparkles", primaryHex: "#C9A7FF", secondaryHex: "#FFC98A", lineWidth: 4),
        ProfileIconFrameStyle(id: "horizon_wreath", title: "水平花", systemImage: "sunrise.fill", primaryHex: "#FFB3C7", secondaryHex: "#7DD3FC", lineWidth: 4)
    ]
    static let visibleItems: [ProfileIconFrameStyle] = [noneItem, defaultItem] + freeItems
    static let items: [ProfileIconFrameStyle] = visibleItems + legacyItems
    static let generatedArtworkIDs = Set((items.map(\.id)).filter { $0 != ProfileDecorationUnlocks.noIconFrameID })

    static func item(for id: String?) -> ProfileIconFrameStyle {
        items.first { $0.id == id } ?? defaultItem
    }

    private static func instrument(
        _ suffix: String,
        primaryHex: String,
        secondaryHex: String,
        lineWidth: CGFloat
    ) -> ProfileIconFrameStyle {
        let id = "free_instrument_\(suffix)"
        let category = instrumentCategory(for: id) ?? .ring
        let rank = instrumentRank(for: id) ?? 1
        return ProfileIconFrameStyle(
            id: id,
            title: "\(category.title) Rank \(rank)",
            systemImage: "circle",
            primaryHex: primaryHex,
            secondaryHex: secondaryHex,
            lineWidth: lineWidth
        )
    }

    private static func personality(
        id: String,
        title: String,
        systemImage: String,
        primaryHex: String,
        secondaryHex: String
    ) -> ProfileIconFrameStyle {
        ProfileIconFrameStyle(
            id: id,
            title: title,
            systemImage: systemImage,
            primaryHex: primaryHex,
            secondaryHex: secondaryHex,
            lineWidth: 3
        )
    }

    /// 獲得（instrument）フレームの系統。コレクションでは系統ごとに1スタックで表示する。
    static func instrumentCategory(for id: String?) -> InstrumentFrameCategory? {
        guard let id, id.hasPrefix("free_instrument_") else { return nil }
        if id.hasSuffix("_seal") { return .seal }
        if id.hasSuffix("_orbit") { return .orbit }
        if id.hasSuffix("_crest") { return .crest }
        return .ring
    }

    /// 獲得（instrument）フレームの達成ランク（1〜5）。IDの素材ランクから導く。
    static func instrumentRank(for id: String?) -> Int? {
        guard let id, id.hasPrefix("free_instrument_") else { return nil }
        if id.contains("iron") { return 1 }
        if id.contains("bronze") { return 2 }
        if id.contains("silver") { return 3 }
        if id.contains("gold") { return 4 }
        if id.contains("platinum") { return 5 }
        return nil
    }

    /// 獲得フレーム（継続で得る `free_*`）のfallback達成ティア。
    /// IDの素材ランクから導く。生成PNGがある場合は画像を優先する。
    /// プレミアム/レガシーは `nil`（＝勲章ベクターの対象外）。
    static func earnedTier(for id: String?) -> Int? {
        guard let id, freeItems.contains(where: { $0.id == id }) else { return nil }
        if id.contains("iron") { return 1 }
        if id.contains("bronze") { return 2 }
        if id.contains("silver") { return 3 }
        if id.contains("gold") { return 4 }
        if id.contains("platinum") { return 4 }
        return nil
    }
}

/// 獲得（instrument）フレームの系統。名前は形を説明する語に統一し、ランクは「Rank n」で表す。
enum InstrumentFrameCategory: String, CaseIterable, Identifiable {
    case ring
    case seal
    case orbit
    case crest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring:
            "光の輪"
        case .seal:
            "紋章"
        case .orbit:
            "星めぐり"
        case .crest:
            "かんむり"
        }
    }
}

struct ProfileStreakIconStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: String
}

enum ProfileStreakIconCatalog {
    static let noneItem = ProfileStreakIconStyle(id: ProfileDecorationUnlocks.noStreakIconID, title: "なし", systemImage: "calendar", tintHex: "#8E879F")
    static let defaultID = "flame"
    static let defaultItem = ProfileStreakIconStyle(id: "flame", title: "赤い炎", systemImage: "flame.fill", tintHex: "#EB5757")
    static let items: [ProfileStreakIconStyle] = [
        noneItem,
        defaultItem,
        ProfileStreakIconStyle(id: "orange_flame", title: "橙の炎", systemImage: "flame.fill", tintHex: "#F2994A"),
        ProfileStreakIconStyle(id: "yellow_flame", title: "黄色の炎", systemImage: "flame.fill", tintHex: "#F2C94C"),
        ProfileStreakIconStyle(id: "lime_flame", title: "黄緑の炎", systemImage: "flame.fill", tintHex: "#A3E635"),
        ProfileStreakIconStyle(id: "green_flame", title: "緑の炎", systemImage: "flame.fill", tintHex: "#27AE60"),
        ProfileStreakIconStyle(id: "blue_flame", title: "青い炎", systemImage: "flame.fill", tintHex: "#2F80ED"),
        ProfileStreakIconStyle(id: "purple_flame", title: "紫の炎", systemImage: "flame.fill", tintHex: "#6C5CE7")
    ]
    static let equippableItems = items.filter { $0.id != ProfileDecorationUnlocks.noStreakIconID }

    static func item(for id: String?) -> ProfileStreakIconStyle {
        items.first { $0.id == id } ?? defaultItem
    }
}

@MainActor
struct ProfileCardStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let lightBackgroundHex: String
    let darkBackgroundHex: String
    let markHex: String?
    let stripOpacity: Double
    let borderWidth: CGFloat
    var foregroundHex: String?
    var secondaryForegroundHex: String?

    var backgroundColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? lightBackgroundHex : darkBackgroundHex)
            }
        )
    }

    var textColor: Color {
        if let foregroundHex {
            return Color(hex: foregroundHex)
        }
        if hasGeneratedArtwork {
            return Color(hex: "#F7F2FF")
        }
        return Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#2A2440" : "#ECE8F5")
            }
        )
    }

    var secondaryTextColor: Color {
        if let secondaryForegroundHex {
            return Color(hex: secondaryForegroundHex)
        }
        if hasGeneratedArtwork {
            return Color(hex: "#D8CEE8")
        }
        return Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#6A6388" : "#C8C1DA")
            }
        )
    }

    func markColor(accentColor: Color) -> Color {
        markHex.map(Color.init(hex:)) ?? accentColor
    }

    func stripColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(stripOpacity)
    }

    func borderColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(borderWidth > 1 ? 0.55 : 0.18)
    }

    var artworkAssetName: String { "profile_card_\(id)" }
    var thumbnailAssetName: String { "profile_card_thumb_\(id)" }

    var hasGeneratedArtwork: Bool {
        ProfileCardStyleCatalog.generatedArtworkIDs.contains(id)
    }
}

enum ProfileCardStyleCatalog {
    static let noneItem = ProfileCardStyle(id: ProfileDecorationUnlocks.noCardStyleID, title: "なし", systemImage: "minus.rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: "#8E879F", stripOpacity: 0, borderWidth: 0)
    static let defaultID = ProfileDecorationUnlocks.defaultCardStyleID
    static let defaultItem = ProfileCardStyle(id: defaultID, title: "静空", systemImage: "rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: nil, stripOpacity: 0.34, borderWidth: 1)
    static let freeItems: [ProfileCardStyle] = [
        generated(id: "free_dawn_horizon_panel", title: "暁線", systemImage: "sunrise.fill", markHex: "#FFB3C7"),
        generated(id: "free_ripple_border_panel", title: "水縁", systemImage: "water.waves", markHex: "#39D5E8"),
        generated(id: "free_cloud_veil_panel", title: "雲幕", systemImage: "cloud.fill", markHex: "#9BDCF8"),
        generated(id: "free_leaf_corner_panel", title: "葉隅", systemImage: "leaf.fill", markHex: "#5FE0A8"),
        generated(id: "free_frost_edge_panel", title: "霜縁", systemImage: "snowflake", markHex: "#8AB4FF"),
        generated(id: "free_thread_border_panel", title: "糸枠", systemImage: "scribble.variable", markHex: "#C9A7FF"),
        generated(id: "free_orbit_grid_panel", title: "軌跡線", systemImage: "scope", markHex: "#7DD3FC"),
        generated(id: "free_rain_panel", title: "雨粒", systemImage: "cloud.rain.fill", markHex: "#7DD3FC"),
        generated(id: "free_candle_panel", title: "灯影", systemImage: "flame.fill", markHex: "#FF8A5B"),
        generated(id: "free_ink_panel", title: "墨縁", systemImage: "paintbrush.pointed.fill", markHex: "#A78BFA"),
        generated(id: "free_aurora_trace_panel", title: "極光線", systemImage: "sparkles", markHex: "#5FE0A8"),
        generated(id: "free_glass_bead_panel", title: "硝子点", systemImage: "drop.circle.fill", markHex: "#39D5E8"),
        generated(id: "free_linen_stitch_panel", title: "織目", systemImage: "circle.dashed", markHex: "#C9A7FF"),
        generated(id: "free_constellation_panel", title: "星図線", systemImage: "scope", markHex: "#7DD3FC"),
        generated(id: "free_wave_panel", title: "波端", systemImage: "water.waves", markHex: "#39D5E8"),
        generated(id: "free_mist_panel", title: "霧面", systemImage: "circle.dotted", markHex: "#C9A7FF"),
        generated(id: "free_petal_corner_panel", title: "花隅", systemImage: "camera.macro", markHex: "#FF8FB3"),
        generated(id: "free_stone_path_panel", title: "石径", systemImage: "point.topleft.down.curvedto.point.bottomright.up", markHex: "#5FE0A8"),
        generated(id: "free_sunline_panel", title: "陽線", systemImage: "sunrise.fill", markHex: "#FFC98A"),
        generated(id: "free_night_bloom_panel", title: "夜花", systemImage: "camera.macro", markHex: "#FF8FB3")
    ]

    static let legacyItems: [ProfileCardStyle] = [
        ProfileCardStyle(id: "aurora_panel", title: "極光幕", systemImage: "sparkles", lightBackgroundHex: "#F1FFF9", darkBackgroundHex: "#102D27", markHex: "#5FE0A8", stripOpacity: 0.44, borderWidth: 1),
        ProfileCardStyle(id: "kintsugi_panel", title: "金継ぎ", systemImage: "line.diagonal", lightBackgroundHex: "#FFF8EA", darkBackgroundHex: "#261D26", markHex: "#FFC98A", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "porcelain_panel", title: "白磁", systemImage: "circle.hexagongrid.fill", lightBackgroundHex: "#F8FBFF", darkBackgroundHex: "#172033", markHex: "#D8ECFF", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "tide_panel", title: "潮目", systemImage: "drop.fill", lightBackgroundHex: "#F0FFFD", darkBackgroundHex: "#122E34", markHex: "#39D5E8", stripOpacity: 0.42, borderWidth: 1)
    ]
    static let visibleItems: [ProfileCardStyle] = [noneItem, defaultItem] + freeItems
    static let items: [ProfileCardStyle] = visibleItems + legacyItems
    static let generatedArtworkIDs = Set((freeItems + legacyItems).map(\.id))

    static func item(for id: String?) -> ProfileCardStyle {
        items.first { $0.id == id } ?? defaultItem
    }

    private static func generated(id: String, title: String, systemImage: String, markHex: String) -> ProfileCardStyle {
        ProfileCardStyle(
            id: id,
            title: title,
            systemImage: systemImage,
            lightBackgroundHex: "#151126",
            darkBackgroundHex: "#151126",
            markHex: markHex,
            stripOpacity: 0.38,
            borderWidth: 1,
            foregroundHex: "#F7F2FF",
            secondaryForegroundHex: "#D8CEE8"
        )
    }
}

enum ProfileFormat {
    static func duration(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
    }
}

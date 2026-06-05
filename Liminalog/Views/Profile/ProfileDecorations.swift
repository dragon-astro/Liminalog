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
        id != ProfileDecorationUnlocks.noIconFrameID && UIImage(named: artworkAssetName) != nil
    }
}

enum ProfileIconFrameCatalog {
    static let noneItem = ProfileIconFrameStyle(id: ProfileDecorationUnlocks.noIconFrameID, title: "なし", systemImage: "minus.circle", primaryHex: "#8E879F", secondaryHex: "#8E879F", lineWidth: 0)
    static let defaultID = ProfileDecorationUnlocks.defaultIconFrameID
    static let defaultItem = ProfileIconFrameStyle(id: defaultID, title: "澄空", systemImage: "circle", primaryHex: "#7DD3FC", secondaryHex: "#C9A7FF", lineWidth: 3)
    static let items: [ProfileIconFrameStyle] = [
        noneItem,
        defaultItem,
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
        ProfileIconFrameStyle(id: "horizon_wreath", title: "水平花", systemImage: "sunrise.fill", primaryHex: "#FFB3C7", secondaryHex: "#7DD3FC", lineWidth: 4)
    ]

    static func item(for id: String?) -> ProfileIconFrameStyle {
        items.first { $0.id == id } ?? defaultItem
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
        ProfileStreakIconStyle(id: "bolt", title: "金の炎", systemImage: "flame.fill", tintHex: "#F2C94C"),
        ProfileStreakIconStyle(id: "sun", title: "橙の炎", systemImage: "flame.fill", tintHex: "#F2994A"),
        ProfileStreakIconStyle(id: "spark", title: "紫の炎", systemImage: "flame.fill", tintHex: "#6C5CE7")
    ]

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

    var backgroundColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? lightBackgroundHex : darkBackgroundHex)
            }
        )
    }

    var textColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#2A2440" : "#ECE8F5")
            }
        )
    }

    var secondaryTextColor: Color {
        Color(
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

    var hasGeneratedArtwork: Bool {
        id != ProfileDecorationUnlocks.noCardStyleID && UIImage(named: artworkAssetName) != nil
    }
}

enum ProfileCardStyleCatalog {
    static let noneItem = ProfileCardStyle(id: ProfileDecorationUnlocks.noCardStyleID, title: "なし", systemImage: "minus.rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: "#8E879F", stripOpacity: 0, borderWidth: 0)
    static let defaultID = ProfileDecorationUnlocks.defaultCardStyleID
    static let defaultItem = ProfileCardStyle(id: defaultID, title: "静空", systemImage: "rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: nil, stripOpacity: 0.34, borderWidth: 1)
    static let items: [ProfileCardStyle] = [
        noneItem,
        defaultItem,
        ProfileCardStyle(id: "cloud_panel", title: "雲影", systemImage: "cloud.fill", lightBackgroundHex: "#F6FBFF", darkBackgroundHex: "#18243A", markHex: "#9BDCF8", stripOpacity: 0.34, borderWidth: 1),
        ProfileCardStyle(id: "ripple_panel", title: "水面", systemImage: "water.waves", lightBackgroundHex: "#F1FDFF", darkBackgroundHex: "#102D35", markHex: "#39D5E8", stripOpacity: 0.34, borderWidth: 1),
        ProfileCardStyle(id: "leaf_panel", title: "葉脈", systemImage: "leaf.fill", lightBackgroundHex: "#F2FFF8", darkBackgroundHex: "#143229", markHex: "#5FE0A8", stripOpacity: 0.34, borderWidth: 1),
        ProfileCardStyle(id: "dawn_panel", title: "朝露", systemImage: "sunrise.fill", lightBackgroundHex: "#FFF5F8", darkBackgroundHex: "#2B1C35", markHex: "#FF8FB3", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "frost_panel", title: "氷面", systemImage: "snowflake", lightBackgroundHex: "#F4FAFF", darkBackgroundHex: "#14273E", markHex: "#8AB4FF", stripOpacity: 0.36, borderWidth: 1),
        ProfileCardStyle(id: "thread_panel", title: "縫い目", systemImage: "scribble.variable", lightBackgroundHex: "#FAF6FF", darkBackgroundHex: "#241B3A", markHex: "#C9A7FF", stripOpacity: 0.36, borderWidth: 1),
        ProfileCardStyle(id: "wisteria_panel", title: "藤棚", systemImage: "camera.macro", lightBackgroundHex: "#F8F5FF", darkBackgroundHex: "#21183A", markHex: "#A78BFA", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "laurel_panel", title: "月桂紙", systemImage: "leaf.circle.fill", lightBackgroundHex: "#F6FFF6", darkBackgroundHex: "#1A3024", markHex: "#5FE0A8", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "chart_panel", title: "星図面", systemImage: "scope", lightBackgroundHex: "#F5FAFF", darkBackgroundHex: "#171E36", markHex: "#7DD3FC", stripOpacity: 0.36, borderWidth: 1),
        ProfileCardStyle(id: "petal_panel", title: "花影", systemImage: "camera.macro", lightBackgroundHex: "#FFF4FA", darkBackgroundHex: "#2B1B35", markHex: "#FF8FB3", stripOpacity: 0.4, borderWidth: 1),
        ProfileCardStyle(id: "aurora_panel", title: "極光幕", systemImage: "sparkles", lightBackgroundHex: "#F1FFF9", darkBackgroundHex: "#102D27", markHex: "#5FE0A8", stripOpacity: 0.44, borderWidth: 1),
        ProfileCardStyle(id: "kintsugi_panel", title: "金継ぎ", systemImage: "line.diagonal", lightBackgroundHex: "#FFF8EA", darkBackgroundHex: "#261D26", markHex: "#FFC98A", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "porcelain_panel", title: "白磁", systemImage: "circle.hexagongrid.fill", lightBackgroundHex: "#F8FBFF", darkBackgroundHex: "#172033", markHex: "#D8ECFF", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "tide_panel", title: "潮目", systemImage: "drop.fill", lightBackgroundHex: "#F0FFFD", darkBackgroundHex: "#122E34", markHex: "#39D5E8", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "ember_vine_panel", title: "灯蔓", systemImage: "flame.fill", lightBackgroundHex: "#FFF3EE", darkBackgroundHex: "#321D24", markHex: "#FF8A5B", stripOpacity: 0.44, borderWidth: 1),
        ProfileCardStyle(id: "prism_dew_panel", title: "虹露", systemImage: "drop.circle.fill", lightBackgroundHex: "#F7F5FF", darkBackgroundHex: "#201936", markHex: "#C9A7FF", stripOpacity: 0.46, borderWidth: 1),
        ProfileCardStyle(id: "snow_crest_panel", title: "雪冠", systemImage: "snowflake", lightBackgroundHex: "#F7FCFF", darkBackgroundHex: "#16263A", markHex: "#D8ECFF", stripOpacity: 0.42, borderWidth: 2),
        ProfileCardStyle(id: "chrono_panel", title: "時軌", systemImage: "timer", lightBackgroundHex: "#F3FAFF", darkBackgroundHex: "#171F35", markHex: "#7DD3FC", stripOpacity: 0.44, borderWidth: 2),
        ProfileCardStyle(id: "lacquer_panel", title: "漆光", systemImage: "seal.fill", lightBackgroundHex: "#FFF5F1", darkBackgroundHex: "#231622", markHex: "#FFC98A", stripOpacity: 0.46, borderWidth: 2),
        ProfileCardStyle(id: "horizon_panel", title: "水平花", systemImage: "sunrise.fill", lightBackgroundHex: "#FFF6FB", darkBackgroundHex: "#211B3B", markHex: "#FFB3C7", stripOpacity: 0.48, borderWidth: 2)
    ]

    static func item(for id: String?) -> ProfileCardStyle {
        items.first { $0.id == id } ?? defaultItem
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

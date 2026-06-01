import Foundation

struct UnlockCatalogItem: Hashable, Identifiable {
    let key: String
    let kind: UnlockKind
    let requiredCumulativeScore: Int
    let displayName: String
    let systemImageName: String
    let tintHex: String
    let targetID: String
    let sortOrder: Int

    var id: String { key }
}

enum UnlockCatalog {
    static let scorePerPassingDay = 60
    static let releaseScheduleDays = [
        7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84,
        98, 112, 126, 140, 154, 168,
        182, 203, 224, 245, 266,
        300, 330, 365
    ]

    static let items: [UnlockCatalogItem] = definitions.enumerated().map { index, definition in
        UnlockCatalogItem(
            key: definition.key,
            kind: definition.kind,
            requiredCumulativeScore: releaseScheduleDays[index] * scorePerPassingDay,
            displayName: definition.displayName,
            systemImageName: definition.systemImageName,
            tintHex: definition.tintHex,
            targetID: definition.targetID,
            sortOrder: index
        )
    }

    private static let definitions: [(key: String, kind: UnlockKind, displayName: String, systemImageName: String, tintHex: String, targetID: String)] = [
        ("badge.first_record", .nameBadge, "はじめの記録", "sparkles", "#2F80ED", "first_record"),
        ("card.glass", .cardStyle, "Glass Card", "sparkle.magnifyingglass", "#2F80ED", "glass"),
        ("frame.signal", .iconFrame, "Signal Frame", "dot.radiowaves.left.and.right", "#00A8A8", "signal"),
        ("streak.gold_flame", .streakIcon, "金の炎", "flame.fill", "#F2C94C", "bolt"),
        ("badge.three_days", .nameBadge, "3日記録", "calendar.badge.checkmark", "#27AE60", "three_days"),
        ("theme.akane", .theme, "茜 / Akane", "sunset.fill", "#D9664A", "akane"),
        ("card.dawn", .cardStyle, "Dawn Card", "sunrise.fill", "#F2994A", "dawn"),
        ("frame.focus", .iconFrame, "Focus Frame", "scope", "#EB5757", "focus"),
        ("badge.ten_hours", .nameBadge, "10時間", "clock.fill", "#6C5CE7", "ten_hours"),
        ("streak.orange_flame", .streakIcon, "橙の炎", "flame.fill", "#F2994A", "sun"),
        ("stamp.daybreak", .stamp, "Daybreak Stamp", "sun.max.fill", "#F2C94C", "daybreak"),
        ("badge.morning", .nameBadge, "朝の記録", "sunrise.fill", "#F2994A", "morning"),
        ("card.mint", .cardStyle, "Mint Card", "leaf.fill", "#27AE60", "mint"),
        ("frame.crown", .iconFrame, "Crown Frame", "crown.fill", "#F2C94C", "crown"),
        ("theme.oboro", .theme, "朧 / Oboro", "moon.haze.fill", "#9A93B5", "oboro"),
        ("badge.seven_streak", .nameBadge, "7日連続", "flame.fill", "#EB5757", "seven_streak"),
        ("bar.gradient", .barStyle, "Gradient Bar", "chart.bar.fill", "#C9A7FF", "gradient"),
        ("stamp.twilight", .stamp, "Twilight Stamp", "sparkles", "#C9A7FF", "twilight"),
        ("app_icon.dusk", .appIcon, "Dusk Icon", "app.fill", "#6B3FA0", "dusk"),
        ("theme.tsukishiro", .theme, "月白 / Tsukishiro", "moon.stars.fill", "#D8ECFF", "tsukishiro"),
        ("card_template.mist", .cardTemplate, "Mist Card", "rectangle.on.rectangle.angled", "#8AB4FF", "mist"),
        ("streak.purple_flame", .streakIcon, "紫の炎", "flame.fill", "#6C5CE7", "spark"),
        ("theme.zansho", .theme, "残照 / Zansho", "sunset.circle.fill", "#FFE3A3", "zansho"),
        ("app_icon.daybreak", .appIcon, "Daybreak Icon", "app.badge.fill", "#F2994A", "daybreak"),
        ("theme.hisui", .theme, "翡翠 / Hisui", "leaf.circle.fill", "#00A8A8", "hisui"),
        ("theme.ruri", .theme, "瑠璃 / Ruri", "circle.hexagongrid.fill", "#4C6FFF", "ruri")
    ]
}

enum UnlockRules {
    static func unlockedKeys(
        cumulativeScore: Int,
        catalog: [UnlockCatalogItem] = UnlockCatalog.items
    ) -> Set<String> {
        guard cumulativeScore > 0 else { return [] }
        return Set(
            catalog
                .filter { $0.requiredCumulativeScore <= cumulativeScore }
                .map(\.key)
        )
    }

    static func itemsToUnlock(
        cumulativeScore: Int,
        items: [UnlockItem]
    ) -> [UnlockItem] {
        guard cumulativeScore > 0 else { return [] }
        return items
            .filter { $0.unlockedAt == nil && $0.requiredCumulativeScore <= cumulativeScore }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.key < $1.key
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func nextLockedItem(
        cumulativeScore: Int,
        items: [UnlockItem]
    ) -> UnlockItem? {
        items
            .filter { $0.unlockedAt == nil && $0.requiredCumulativeScore > cumulativeScore }
            .sorted {
                if $0.requiredCumulativeScore == $1.requiredCumulativeScore {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.requiredCumulativeScore < $1.requiredCumulativeScore
            }
            .first
    }

    static func progress(
        cumulativeScore: Int,
        toward item: UnlockItem
    ) -> Double {
        guard item.requiredCumulativeScore > 0 else { return 1 }
        return min(max(Double(cumulativeScore) / Double(item.requiredCumulativeScore), 0), 1)
    }
}

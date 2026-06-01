import Foundation

enum UnlockRequirementKind: String, Codable, CaseIterable, Identifiable {
    case cumulativeScore
    case recordedDays
    case recordedHours
    case streakDays
    case earlyRecordDays
    case lateNightRecordDays
    case distinctCategoryCount

    var id: String { rawValue }

    var unitLabel: String {
        switch self {
        case .cumulativeScore:
            "pt"
        case .recordedDays:
            "日"
        case .recordedHours:
            "時間"
        case .streakDays:
            "日連続"
        case .earlyRecordDays:
            "朝"
        case .lateNightRecordDays:
            "深夜"
        case .distinctCategoryCount:
            "種類"
        }
    }
}

struct UnlockMetrics: Equatable {
    var cumulativeScore: Int = 0
    var recordedDays: Int = 0
    var recordedHours: Int = 0
    var streakDays: Int = 0
    var earlyRecordDays: Int = 0
    var lateNightRecordDays: Int = 0
    var distinctCategoryCount: Int = 0

    static func score(_ cumulativeScore: Int) -> UnlockMetrics {
        UnlockMetrics(cumulativeScore: cumulativeScore)
    }

    func value(for kind: UnlockRequirementKind) -> Int {
        switch kind {
        case .cumulativeScore:
            cumulativeScore
        case .recordedDays:
            recordedDays
        case .recordedHours:
            recordedHours
        case .streakDays:
            streakDays
        case .earlyRecordDays:
            earlyRecordDays
        case .lateNightRecordDays:
            lateNightRecordDays
        case .distinctCategoryCount:
            distinctCategoryCount
        }
    }
}

struct UnlockRequirement: Hashable {
    let kind: UnlockRequirementKind
    let value: Int

    static func cumulativeScore(_ value: Int) -> UnlockRequirement {
        UnlockRequirement(kind: .cumulativeScore, value: value)
    }
}

struct UnlockCatalogItem: Hashable, Identifiable {
    let key: String
    let kind: UnlockKind
    let requiredCumulativeScore: Int
    let requirementKind: UnlockRequirementKind
    let requiredValue: Int
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
    static let legacyKeyReplacements: [String: String] = [
        "stamp.daybreak": "icon_set.daybreak",
        "stamp.twilight": "icon_set.twilight",
        "app_icon.dusk": "month_art.dusk",
        "app_icon.daybreak": "month_art.daybreak",
        "card_template.mist": "card.mist"
    ]

    static let items: [UnlockCatalogItem] = definitions.enumerated().map { index, definition in
        UnlockCatalogItem(
            key: definition.key,
            kind: definition.kind,
            requiredCumulativeScore: releaseScheduleDays[index] * scorePerPassingDay,
            requirementKind: definition.requirement?.kind ?? .cumulativeScore,
            requiredValue: definition.requirement?.value ?? releaseScheduleDays[index] * scorePerPassingDay,
            displayName: definition.displayName,
            systemImageName: definition.systemImageName,
            tintHex: definition.tintHex,
            targetID: definition.targetID,
            sortOrder: index
        )
    }

    private static let definitions: [(key: String, kind: UnlockKind, displayName: String, systemImageName: String, tintHex: String, targetID: String, requirement: UnlockRequirement?)] = [
        ("badge.first_record", .nameBadge, "はじめの記録", "sparkles", "#2F80ED", "first_record", .init(kind: .recordedDays, value: 1)),
        ("card.glass", .cardStyle, "Glass Card", "sparkle.magnifyingglass", "#2F80ED", "glass", nil),
        ("frame.signal", .iconFrame, "Signal Frame", "dot.radiowaves.left.and.right", "#00A8A8", "signal", .init(kind: .distinctCategoryCount, value: 3)),
        ("streak.gold_flame", .streakIcon, "金の炎", "flame.fill", "#F2C94C", "bolt", .init(kind: .streakDays, value: 7)),
        ("badge.three_days", .nameBadge, "3日記録", "calendar.badge.checkmark", "#27AE60", "three_days", .init(kind: .recordedDays, value: 3)),
        ("theme.akane", .theme, "茜 / Akane", "sunset.fill", "#D9664A", "akane", nil),
        ("card.dawn", .cardStyle, "Dawn Card", "sunrise.fill", "#F2994A", "dawn", .init(kind: .earlyRecordDays, value: 3)),
        ("frame.focus", .iconFrame, "Focus Frame", "scope", "#EB5757", "focus", nil),
        ("badge.ten_hours", .nameBadge, "10時間", "clock.fill", "#6C5CE7", "ten_hours", .init(kind: .recordedHours, value: 10)),
        ("streak.orange_flame", .streakIcon, "橙の炎", "flame.fill", "#F2994A", "sun", .init(kind: .streakDays, value: 14)),
        ("icon_set.daybreak", .iconSet, "Daybreak Icons", "sun.max.fill", "#F2C94C", "daybreak", .init(kind: .earlyRecordDays, value: 7)),
        ("badge.morning", .nameBadge, "朝の記録", "sunrise.fill", "#F2994A", "morning", .init(kind: .earlyRecordDays, value: 1)),
        ("card.mint", .cardStyle, "Mint Card", "leaf.fill", "#27AE60", "mint", nil),
        ("frame.crown", .iconFrame, "Crown Frame", "crown.fill", "#F2C94C", "crown", nil),
        ("theme.oboro", .theme, "朧 / Oboro", "moon.haze.fill", "#9A93B5", "oboro", .init(kind: .lateNightRecordDays, value: 3)),
        ("badge.seven_streak", .nameBadge, "7日連続", "flame.fill", "#EB5757", "seven_streak", .init(kind: .streakDays, value: 7)),
        ("bar.gradient", .barStyle, "Gradient Bar", "chart.bar.fill", "#C9A7FF", "gradient", .init(kind: .distinctCategoryCount, value: 5)),
        ("icon_set.twilight", .iconSet, "Twilight Icons", "sparkles", "#C9A7FF", "twilight", .init(kind: .lateNightRecordDays, value: 7)),
        ("month_art.dusk", .monthArt, "Dusk Month Art", "moon.stars.fill", "#6B3FA0", "dusk", nil),
        ("theme.tsukishiro", .theme, "月白 / Tsukishiro", "moon.stars.fill", "#D8ECFF", "tsukishiro", nil),
        ("card.mist", .cardStyle, "Mist Card", "rectangle.on.rectangle.angled", "#8AB4FF", "mist", nil),
        ("streak.purple_flame", .streakIcon, "紫の炎", "flame.fill", "#6C5CE7", "spark", .init(kind: .streakDays, value: 30)),
        ("theme.zansho", .theme, "残照 / Zansho", "sunset.circle.fill", "#FFE3A3", "zansho", nil),
        ("month_art.daybreak", .monthArt, "Daybreak Month Art", "sunrise.fill", "#F2994A", "daybreak", nil),
        ("theme.hisui", .theme, "翡翠 / Hisui", "leaf.circle.fill", "#00A8A8", "hisui", nil),
        ("theme.ruri", .theme, "瑠璃 / Ruri", "circle.hexagongrid.fill", "#4C6FFF", "ruri", nil)
    ]
}

enum UnlockRules {
    static func isUnlocked(
        _ item: UnlockCatalogItem,
        metrics: UnlockMetrics
    ) -> Bool {
        guard item.requiredValue > 0 else { return true }
        return metrics.value(for: item.requirementKind) >= item.requiredValue
    }

    static func isUnlocked(
        _ item: UnlockItem,
        metrics: UnlockMetrics
    ) -> Bool {
        guard item.requiredValue > 0 else { return true }
        return metrics.value(for: item.requirementKind) >= item.requiredValue
    }

    static func unlockedKeys(
        cumulativeScore: Int,
        catalog: [UnlockCatalogItem] = UnlockCatalog.items
    ) -> Set<String> {
        unlockedKeys(metrics: .score(cumulativeScore), catalog: catalog)
    }

    static func unlockedKeys(
        metrics: UnlockMetrics,
        catalog: [UnlockCatalogItem] = UnlockCatalog.items
    ) -> Set<String> {
        return Set(
            catalog
                .filter { isUnlocked($0, metrics: metrics) }
                .map(\.key)
        )
    }

    static func itemsToUnlock(
        cumulativeScore: Int,
        items: [UnlockItem]
    ) -> [UnlockItem] {
        itemsToUnlock(metrics: .score(cumulativeScore), items: items)
    }

    static func itemsToUnlock(
        metrics: UnlockMetrics,
        items: [UnlockItem]
    ) -> [UnlockItem] {
        return items
            .filter { $0.unlockedAt == nil && isUnlocked($0, metrics: metrics) }
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
        nextLockedItem(metrics: .score(cumulativeScore), items: items)
    }

    static func nextLockedItem(
        metrics: UnlockMetrics,
        items: [UnlockItem]
    ) -> UnlockItem? {
        items
            .filter { $0.unlockedAt == nil && !isUnlocked($0, metrics: metrics) }
            .sorted {
                let lhsProgress = progress(metrics: metrics, toward: $0)
                let rhsProgress = progress(metrics: metrics, toward: $1)
                if lhsProgress != rhsProgress {
                    return lhsProgress > rhsProgress
                }
                let lhsRemaining = remainingValue(metrics: metrics, toward: $0)
                let rhsRemaining = remainingValue(metrics: metrics, toward: $1)
                if lhsRemaining == rhsRemaining {
                    return $0.sortOrder < $1.sortOrder
                }
                return lhsRemaining < rhsRemaining
            }
            .first
    }

    static func progress(
        cumulativeScore: Int,
        toward item: UnlockItem
    ) -> Double {
        progress(metrics: .score(cumulativeScore), toward: item)
    }

    static func progress(
        metrics: UnlockMetrics,
        toward item: UnlockItem
    ) -> Double {
        guard item.requiredValue > 0 else { return 1 }
        let currentValue = metrics.value(for: item.requirementKind)
        return min(max(Double(currentValue) / Double(item.requiredValue), 0), 1)
    }

    static func remainingValue(
        metrics: UnlockMetrics,
        toward item: UnlockItem
    ) -> Int {
        max(item.requiredValue - metrics.value(for: item.requirementKind), 0)
    }
}

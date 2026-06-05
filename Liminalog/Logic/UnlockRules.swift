import Foundation

enum UnlockRequirementKind: String, Codable, CaseIterable, Identifiable {
    case cumulativeScore
    case recordedDays
    case recordedHours
    case streakDays
    case earlyRecordDays
    case lateNightRecordDays
    case distinctCategoryCount
    case planMatchedDays
    case chargeDays
    case morningPersonaDays
    case nightPersonaDays
    case recordingHabitDays
    case personalBestDays
    case returnAfterGapDays
    case firstRecordDays
    case balancedDays
    case focusedDays
    case changeSignalDays

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
        case .planMatchedDays, .chargeDays, .morningPersonaDays, .nightPersonaDays,
             .recordingHabitDays, .personalBestDays, .returnAfterGapDays, .firstRecordDays,
             .balancedDays, .focusedDays, .changeSignalDays:
            "回"
        }
    }

    var conditionTitle: String {
        switch self {
        case .cumulativeScore:
            "継続XP"
        case .recordedDays:
            "記録日数"
        case .recordedHours:
            "累計記録時間"
        case .streakDays:
            "連続記録"
        case .earlyRecordDays:
            "朝の記録"
        case .lateNightRecordDays:
            "深夜の記録"
        case .distinctCategoryCount:
            "カテゴリ種類"
        case .planMatchedDays:
            "有言実行の日"
        case .chargeDays:
            "充電の日"
        case .morningPersonaDays:
            "朝型の日"
        case .nightPersonaDays:
            "夜型の日"
        case .recordingHabitDays:
            "記録ストリークの日"
        case .personalBestDays:
            "自己最長の日"
        case .returnAfterGapDays:
            "復帰の日"
        case .firstRecordDays:
            "初記録の日"
        case .balancedDays:
            "バランス日"
        case .focusedDays:
            "一点集中の日"
        case .changeSignalDays:
            "変化を作った日"
        }
    }

    var progressUnit: String {
        switch self {
        case .cumulativeScore:
            "pt"
        case .recordedDays:
            "日"
        case .recordedHours:
            "時間"
        case .streakDays:
            "日"
        case .earlyRecordDays, .lateNightRecordDays,
             .planMatchedDays, .chargeDays, .morningPersonaDays, .nightPersonaDays,
             .recordingHabitDays, .personalBestDays, .returnAfterGapDays, .firstRecordDays,
             .balancedDays, .focusedDays, .changeSignalDays:
            "回"
        case .distinctCategoryCount:
            "種類"
        }
    }

    func requirementText(requiredValue: Int) -> String {
        "\(conditionTitle) \(requiredValue.formatted())\(progressUnit)"
    }

    func progressText(currentValue: Int, requiredValue: Int, progress: Double) -> String {
        let visibleCurrent = min(max(currentValue, 0), max(requiredValue, 0))
        let percent = Int((min(max(progress, 0), 1) * 100).rounded(.down))
        return "\(visibleCurrent.formatted()) / \(requiredValue.formatted())\(progressUnit)・\(percent)%"
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
    var planMatchedDays: Int = 0
    var chargeDays: Int = 0
    var morningPersonaDays: Int = 0
    var nightPersonaDays: Int = 0
    var recordingHabitDays: Int = 0
    var personalBestDays: Int = 0
    var returnAfterGapDays: Int = 0
    var firstRecordDays: Int = 0
    var balancedDays: Int = 0
    var focusedDays: Int = 0
    var changeSignalDays: Int = 0

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
        case .planMatchedDays:
            planMatchedDays
        case .chargeDays:
            chargeDays
        case .morningPersonaDays:
            morningPersonaDays
        case .nightPersonaDays:
            nightPersonaDays
        case .recordingHabitDays:
            recordingHabitDays
        case .personalBestDays:
            personalBestDays
        case .returnAfterGapDays:
            returnAfterGapDays
        case .firstRecordDays:
            firstRecordDays
        case .balancedDays:
            balancedDays
        case .focusedDays:
            focusedDays
        case .changeSignalDays:
            changeSignalDays
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

private struct UnlockCatalogDefinition {
    let key: String
    let kind: UnlockKind
    let displayName: String
    let systemImageName: String
    let tintHex: String
    let targetID: String
    let requirement: UnlockRequirement?
}

enum UnlockCatalog {
    static let scorePerPassingDay = 60
    static let releaseScheduleDays = [
        7, 14, 21, 28, 35, 42, 49, 56, 63, 70, 77, 84,
        98, 112, 126, 140, 154, 168,
        182, 203, 224, 245, 266,
        300, 330, 365
    ]
    static let legacyKeyReplacements: [String: String] = [:]

    static let items: [UnlockCatalogItem] = definitions.enumerated().map { index, definition in
        let scheduledScore = releaseDay(for: index) * scorePerPassingDay
        let requiredCumulativeScore = definition.requirement?.kind == .cumulativeScore
            ? (definition.requirement?.value ?? scheduledScore)
            : scheduledScore
        return UnlockCatalogItem(
            key: definition.key,
            kind: definition.kind,
            requiredCumulativeScore: requiredCumulativeScore,
            requirementKind: definition.requirement?.kind ?? .cumulativeScore,
            requiredValue: definition.requirement?.value ?? scheduledScore,
            displayName: definition.displayName,
            systemImageName: definition.systemImageName,
            tintHex: definition.tintHex,
            targetID: definition.targetID,
            sortOrder: index
        )
    }

    private static func releaseDay(for index: Int) -> Int {
        guard !releaseScheduleDays.isEmpty else { return 1 }
        return releaseScheduleDays[min(max(index, 0), releaseScheduleDays.count - 1)]
    }

    // テーマ/炎は既存軸を維持し、カード/フレーム/バッジだけを新カタログへ置き換える。
    private static let definitions: [UnlockCatalogDefinition] =
        frameDefinitions
        + cardDefinitions
        + badgeDefinitions
        + retainedThemeAndStreakDefinitions

    private static let frameDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "frame.cloud_veil", kind: .iconFrame, displayName: "雲間", systemImageName: "cloud.fill", tintHex: "#9BDCF8", targetID: "cloud_veil", requirement: .cumulativeScore(300)),
        .init(key: "frame.ripple_ring", kind: .iconFrame, displayName: "水紋", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "ripple_ring", requirement: .cumulativeScore(600)),
        .init(key: "frame.leaf_orbit", kind: .iconFrame, displayName: "若葉環", systemImageName: "leaf.fill", tintHex: "#5FE0A8", targetID: "leaf_orbit", requirement: .cumulativeScore(900)),
        .init(key: "frame.dawn_pollen", kind: .iconFrame, displayName: "朝露", systemImageName: "sunrise.fill", tintHex: "#FF8FB3", targetID: "dawn_pollen", requirement: .cumulativeScore(1_200)),
        .init(key: "frame.frost_bloom", kind: .iconFrame, displayName: "霜晶", systemImageName: "snowflake", tintHex: "#8AB4FF", targetID: "frost_bloom", requirement: .cumulativeScore(1_800)),
        .init(key: "frame.thread_arc", kind: .iconFrame, displayName: "刺繍糸", systemImageName: "scribble.variable", tintHex: "#C9A7FF", targetID: "thread_arc", requirement: .cumulativeScore(2_400)),
        .init(key: "frame.wisteria_loop", kind: .iconFrame, displayName: "藤環", systemImageName: "camera.macro", tintHex: "#A78BFA", targetID: "wisteria_loop", requirement: .cumulativeScore(3_000)),
        .init(key: "frame.laurel_light", kind: .iconFrame, displayName: "月桂", systemImageName: "leaf.circle.fill", tintHex: "#5FE0A8", targetID: "laurel_light", requirement: .cumulativeScore(3_600)),
        .init(key: "frame.astro_chart", kind: .iconFrame, displayName: "星図", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "astro_chart", requirement: .cumulativeScore(4_500)),
        .init(key: "frame.petal_wreath", kind: .iconFrame, displayName: "花輪", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "petal_wreath", requirement: .cumulativeScore(5_400)),
        .init(key: "frame.aurora_wreath", kind: .iconFrame, displayName: "極光環", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "aurora_wreath", requirement: .cumulativeScore(6_300)),
        .init(key: "frame.kintsugi_ring", kind: .iconFrame, displayName: "金継ぎ", systemImageName: "line.diagonal", tintHex: "#FFC98A", targetID: "kintsugi_ring", requirement: .cumulativeScore(7_200)),
        .init(key: "frame.porcelain_halo", kind: .iconFrame, displayName: "白磁", systemImageName: "circle.hexagongrid.fill", tintHex: "#D8ECFF", targetID: "porcelain_halo", requirement: .cumulativeScore(8_400)),
        .init(key: "frame.tideglass_ring", kind: .iconFrame, displayName: "潮硝子", systemImageName: "drop.fill", tintHex: "#39D5E8", targetID: "tideglass_ring", requirement: .cumulativeScore(9_600)),
        .init(key: "frame.ember_vine", kind: .iconFrame, displayName: "灯蔓", systemImageName: "flame.fill", tintHex: "#FF8A5B", targetID: "ember_vine", requirement: .cumulativeScore(10_800)),
        .init(key: "frame.prism_dew", kind: .iconFrame, displayName: "虹露", systemImageName: "drop.circle.fill", tintHex: "#C9A7FF", targetID: "prism_dew", requirement: .cumulativeScore(12_600)),
        .init(key: "frame.snow_crest", kind: .iconFrame, displayName: "雪冠", systemImageName: "snowflake", tintHex: "#D8ECFF", targetID: "snow_crest", requirement: .cumulativeScore(14_400)),
        .init(key: "frame.chrono_orbit", kind: .iconFrame, displayName: "時環", systemImageName: "timer", tintHex: "#7DD3FC", targetID: "chrono_orbit", requirement: .cumulativeScore(16_200)),
        .init(key: "frame.lacquer_vein", kind: .iconFrame, displayName: "漆脈", systemImageName: "seal.fill", tintHex: "#FFC98A", targetID: "lacquer_vein", requirement: .cumulativeScore(18_600)),
        .init(key: "frame.horizon_wreath", kind: .iconFrame, displayName: "水平花", systemImageName: "sunrise.fill", tintHex: "#FFB3C7", targetID: "horizon_wreath", requirement: .cumulativeScore(21_900))
    ]

    private static let cardDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "card.cloud_panel", kind: .cardStyle, displayName: "雲影", systemImageName: "cloud.fill", tintHex: "#9BDCF8", targetID: "cloud_panel", requirement: .cumulativeScore(450)),
        .init(key: "card.ripple_panel", kind: .cardStyle, displayName: "水面", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "ripple_panel", requirement: .cumulativeScore(750)),
        .init(key: "card.leaf_panel", kind: .cardStyle, displayName: "葉脈", systemImageName: "leaf.fill", tintHex: "#5FE0A8", targetID: "leaf_panel", requirement: .cumulativeScore(1_050)),
        .init(key: "card.dawn_panel", kind: .cardStyle, displayName: "朝露", systemImageName: "sunrise.fill", tintHex: "#FF8FB3", targetID: "dawn_panel", requirement: .cumulativeScore(1_500)),
        .init(key: "card.frost_panel", kind: .cardStyle, displayName: "氷面", systemImageName: "snowflake", tintHex: "#8AB4FF", targetID: "frost_panel", requirement: .cumulativeScore(2_100)),
        .init(key: "card.thread_panel", kind: .cardStyle, displayName: "縫い目", systemImageName: "scribble.variable", tintHex: "#C9A7FF", targetID: "thread_panel", requirement: .cumulativeScore(2_700)),
        .init(key: "card.wisteria_panel", kind: .cardStyle, displayName: "藤棚", systemImageName: "camera.macro", tintHex: "#A78BFA", targetID: "wisteria_panel", requirement: .cumulativeScore(3_300)),
        .init(key: "card.laurel_panel", kind: .cardStyle, displayName: "月桂紙", systemImageName: "leaf.circle.fill", tintHex: "#5FE0A8", targetID: "laurel_panel", requirement: .cumulativeScore(3_900)),
        .init(key: "card.chart_panel", kind: .cardStyle, displayName: "星図面", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "chart_panel", requirement: .cumulativeScore(4_800)),
        .init(key: "card.petal_panel", kind: .cardStyle, displayName: "花影", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "petal_panel", requirement: .cumulativeScore(5_700)),
        .init(key: "card.aurora_panel", kind: .cardStyle, displayName: "極光幕", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "aurora_panel", requirement: .cumulativeScore(6_600)),
        .init(key: "card.kintsugi_panel", kind: .cardStyle, displayName: "金継ぎ", systemImageName: "line.diagonal", tintHex: "#FFC98A", targetID: "kintsugi_panel", requirement: .cumulativeScore(7_800)),
        .init(key: "card.porcelain_panel", kind: .cardStyle, displayName: "白磁", systemImageName: "circle.hexagongrid.fill", tintHex: "#D8ECFF", targetID: "porcelain_panel", requirement: .cumulativeScore(9_000)),
        .init(key: "card.tide_panel", kind: .cardStyle, displayName: "潮目", systemImageName: "drop.fill", tintHex: "#39D5E8", targetID: "tide_panel", requirement: .cumulativeScore(10_200)),
        .init(key: "card.ember_vine_panel", kind: .cardStyle, displayName: "灯蔓", systemImageName: "flame.fill", tintHex: "#FF8A5B", targetID: "ember_vine_panel", requirement: .cumulativeScore(11_400)),
        .init(key: "card.prism_dew_panel", kind: .cardStyle, displayName: "虹露", systemImageName: "drop.circle.fill", tintHex: "#C9A7FF", targetID: "prism_dew_panel", requirement: .cumulativeScore(13_200)),
        .init(key: "card.snow_crest_panel", kind: .cardStyle, displayName: "雪冠", systemImageName: "snowflake", tintHex: "#D8ECFF", targetID: "snow_crest_panel", requirement: .cumulativeScore(15_000)),
        .init(key: "card.chrono_panel", kind: .cardStyle, displayName: "時軌", systemImageName: "timer", tintHex: "#7DD3FC", targetID: "chrono_panel", requirement: .cumulativeScore(16_800)),
        .init(key: "card.lacquer_panel", kind: .cardStyle, displayName: "漆光", systemImageName: "seal.fill", tintHex: "#FFC98A", targetID: "lacquer_panel", requirement: .cumulativeScore(19_200)),
        .init(key: "card.horizon_panel", kind: .cardStyle, displayName: "水平花", systemImageName: "sunrise.fill", tintHex: "#FFB3C7", targetID: "horizon_panel", requirement: .cumulativeScore(21_600))
    ]

    private static let badgeDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "badge.planner", kind: .nameBadge, displayName: "計画派", systemImageName: "checkmark.seal.fill", tintHex: "#2F80ED", targetID: "planner", requirement: .init(kind: .planMatchedDays, value: 5)),
        .init(key: "badge.executor", kind: .nameBadge, displayName: "実行者", systemImageName: "checkmark.seal.fill", tintHex: "#2F80ED", targetID: "executor", requirement: .init(kind: .planMatchedDays, value: 15)),
        .init(key: "badge.promise_keeper", kind: .nameBadge, displayName: "約束の人", systemImageName: "checkmark.seal.fill", tintHex: "#5FE0A8", targetID: "promise_keeper", requirement: .init(kind: .planMatchedDays, value: 30)),
        .init(key: "badge.restorer", kind: .nameBadge, displayName: "整え上手", systemImageName: "battery.100percent", tintHex: "#27AE60", targetID: "restorer", requirement: .init(kind: .chargeDays, value: 5)),
        .init(key: "badge.recovery_master", kind: .nameBadge, displayName: "回復名人", systemImageName: "battery.100percent.bolt", tintHex: "#27AE60", targetID: "recovery_master", requirement: .init(kind: .chargeDays, value: 15)),
        .init(key: "badge.morning_type", kind: .nameBadge, displayName: "朝型", systemImageName: "sunrise.fill", tintHex: "#F2994A", targetID: "morning_type", requirement: .init(kind: .morningPersonaDays, value: 5)),
        .init(key: "badge.morning_person", kind: .nameBadge, displayName: "朝の人", systemImageName: "sun.max.fill", tintHex: "#F2C94C", targetID: "morning_person", requirement: .init(kind: .morningPersonaDays, value: 15)),
        .init(key: "badge.night_walker", kind: .nameBadge, displayName: "夜渡り", systemImageName: "moon.stars.fill", tintHex: "#8AB4FF", targetID: "night_walker", requirement: .init(kind: .nightPersonaDays, value: 5)),
        .init(key: "badge.night_person", kind: .nameBadge, displayName: "夜の人", systemImageName: "moon.haze.fill", tintHex: "#AEB4DD", targetID: "night_person", requirement: .init(kind: .nightPersonaDays, value: 15)),
        .init(key: "badge.recorder", kind: .nameBadge, displayName: "記録家", systemImageName: "book.closed.fill", tintHex: "#6C5CE7", targetID: "recorder", requirement: .init(kind: .recordingHabitDays, value: 5)),
        .init(key: "badge.observer", kind: .nameBadge, displayName: "継続観測者", systemImageName: "eye.fill", tintHex: "#9B8CFF", targetID: "observer", requirement: .init(kind: .recordingHabitDays, value: 15)),
        .init(key: "badge.updater", kind: .nameBadge, displayName: "更新者", systemImageName: "arrow.up.right.circle.fill", tintHex: "#EB5757", targetID: "updater", requirement: .init(kind: .personalBestDays, value: 3)),
        .init(key: "badge.best_crafter", kind: .nameBadge, displayName: "自己ベスト職人", systemImageName: "crown.fill", tintHex: "#F2C94C", targetID: "best_crafter", requirement: .init(kind: .personalBestDays, value: 10)),
        .init(key: "badge.comeback", kind: .nameBadge, displayName: "復帰上手", systemImageName: "hand.wave.fill", tintHex: "#5FE0A8", targetID: "comeback", requirement: .init(kind: .returnAfterGapDays, value: 3)),
        .init(key: "badge.resetter", kind: .nameBadge, displayName: "立て直し屋", systemImageName: "arrow.counterclockwise.circle.fill", tintHex: "#00A8A8", targetID: "resetter", requirement: .init(kind: .returnAfterGapDays, value: 8)),
        .init(key: "badge.pioneer", kind: .nameBadge, displayName: "開拓者", systemImageName: "sparkles", tintHex: "#D946EF", targetID: "pioneer", requirement: .init(kind: .firstRecordDays, value: 5)),
        .init(key: "badge.curious", kind: .nameBadge, displayName: "好奇心型", systemImageName: "sparkle.magnifyingglass", tintHex: "#C9A7FF", targetID: "curious", requirement: .init(kind: .firstRecordDays, value: 12)),
        .init(key: "badge.balancer", kind: .nameBadge, displayName: "バランサー", systemImageName: "scale.3d", tintHex: "#27AE60", targetID: "balancer", requirement: .init(kind: .balancedDays, value: 5)),
        .init(key: "badge.single_focus", kind: .nameBadge, displayName: "一点集中", systemImageName: "scope", tintHex: "#EB5757", targetID: "single_focus", requirement: .init(kind: .focusedDays, value: 5)),
        .init(key: "badge.change_maker", kind: .nameBadge, displayName: "変化を作る人", systemImageName: "arrow.left.arrow.right.circle.fill", tintHex: "#F2994A", targetID: "change_maker", requirement: .init(kind: .changeSignalDays, value: 10))
    ]

    private static let retainedThemeAndStreakDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "streak.gold_flame", kind: .streakIcon, displayName: "金の炎", systemImageName: "flame.fill", tintHex: "#F2C94C", targetID: "bolt", requirement: .init(kind: .streakDays, value: 7)),
        .init(key: "theme.aurora", kind: .theme, displayName: "極光", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "aurora", requirement: .init(kind: .recordedDays, value: 7)),
        .init(key: "streak.orange_flame", kind: .streakIcon, displayName: "橙の炎", systemImageName: "flame.fill", tintHex: "#F2994A", targetID: "sun", requirement: .init(kind: .streakDays, value: 14)),
        .init(key: "theme.akatsuki", kind: .theme, displayName: "暁", systemImageName: "sunrise.fill", tintHex: "#9B8CFF", targetID: "akatsuki", requirement: .init(kind: .earlyRecordDays, value: 14)),
        .init(key: "theme.akane", kind: .theme, displayName: "茜", systemImageName: "sunset.fill", tintHex: "#D9664A", targetID: "akane", requirement: .init(kind: .earlyRecordDays, value: 21)),
        .init(key: "theme.oboro", kind: .theme, displayName: "朧", systemImageName: "moon.haze.fill", tintHex: "#AEB4DD", targetID: "oboro", requirement: .init(kind: .lateNightRecordDays, value: 14)),
        .init(key: "streak.purple_flame", kind: .streakIcon, displayName: "紫の炎", systemImageName: "flame.fill", tintHex: "#6C5CE7", targetID: "spark", requirement: .init(kind: .streakDays, value: 30)),
        .init(key: "theme.zansho", kind: .theme, displayName: "残照", systemImageName: "sunset.circle.fill", tintHex: "#FFC98A", targetID: "zansho", requirement: .init(kind: .recordedHours, value: 200)),
        .init(key: "theme.tsukishiro", kind: .theme, displayName: "月白", systemImageName: "moon.stars.fill", tintHex: "#D8ECFF", targetID: "tsukishiro", requirement: .init(kind: .streakDays, value: 60))
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

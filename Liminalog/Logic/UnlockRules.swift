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
    case sleepCategoryDays
    case workCategoryDays
    case studyCategoryDays
    case hobbyPlayCategoryDays
    case exerciseCategoryDays
    case householdCategoryDays
    /// ひかりのかけら交換（doc 16 §12.0.1）。指標では絶対に自動解放されず、
    /// ユーザーの交換操作だけが unlockedAt を立てる。
    case exchange

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
             .balancedDays, .focusedDays, .changeSignalDays, .sleepCategoryDays,
             .workCategoryDays, .studyCategoryDays, .hobbyPlayCategoryDays,
             .exerciseCategoryDays, .householdCategoryDays:
            "回"
        case .exchange:
            "枚"
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
        case .sleepCategoryDays:
            "睡眠の日"
        case .workCategoryDays:
            "仕事の日"
        case .studyCategoryDays:
            "勉強の日"
        case .hobbyPlayCategoryDays:
            "趣味・遊びの日"
        case .exerciseCategoryDays:
            "運動の日"
        case .householdCategoryDays:
            "家事・生活の日"
        case .exchange:
            "ひかりのかけら"
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
             .balancedDays, .focusedDays, .changeSignalDays, .sleepCategoryDays,
             .workCategoryDays, .studyCategoryDays, .hobbyPlayCategoryDays,
             .exerciseCategoryDays, .householdCategoryDays:
            "回"
        case .distinctCategoryCount:
            "種類"
        case .exchange:
            "枚"
        }
    }

    func requirementText(requiredValue: Int) -> String {
        if self == .exchange {
            return "ひかりのかけら \(requiredValue.formatted())枚と交換"
        }
        return "\(conditionTitle) \(requiredValue.formatted())\(progressUnit)"
    }

    func progressText(currentValue: Int, requiredValue: Int, progress: Double) -> String {
        if self == .exchange {
            return progress >= 1 ? "交換済み" : "交換で入手"
        }
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
    var sleepCategoryDays: Int = 0
    var workCategoryDays: Int = 0
    var studyCategoryDays: Int = 0
    var hobbyPlayCategoryDays: Int = 0
    var exerciseCategoryDays: Int = 0
    var householdCategoryDays: Int = 0

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
        case .sleepCategoryDays:
            sleepCategoryDays
        case .workCategoryDays:
            workCategoryDays
        case .studyCategoryDays:
            studyCategoryDays
        case .hobbyPlayCategoryDays:
            hobbyPlayCategoryDays
        case .exerciseCategoryDays:
            exerciseCategoryDays
        case .householdCategoryDays:
            householdCategoryDays
        case .exchange:
            // 交換は指標で満たされない（ユーザー操作のみ）
            0
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
        + personalityFrameDefinitions
        + cardDefinitions
        + badgeDefinitions
        + retainedThemeAndStreakDefinitions

    private static let frameDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "frame.free_instrument_iron", kind: .iconFrame, displayName: "黒鉄計", systemImageName: "circle", tintHex: "#59606B", targetID: "free_instrument_iron", requirement: .init(kind: .recordedDays, value: 3)),
        .init(key: "frame.free_instrument_bronze", kind: .iconFrame, displayName: "銅計", systemImageName: "circle", tintHex: "#B87545", targetID: "free_instrument_bronze", requirement: .init(kind: .recordedDays, value: 7)),
        .init(key: "frame.free_instrument_silver", kind: .iconFrame, displayName: "銀計", systemImageName: "circle", tintHex: "#D8DEE8", targetID: "free_instrument_silver", requirement: .init(kind: .recordedDays, value: 30)),
        .init(key: "frame.free_instrument_gold", kind: .iconFrame, displayName: "金計", systemImageName: "circle", tintHex: "#F2C94C", targetID: "free_instrument_gold", requirement: .init(kind: .recordedDays, value: 100)),
        .init(key: "frame.free_instrument_platinum", kind: .iconFrame, displayName: "白金計", systemImageName: "circle", tintHex: "#F2F4FF", targetID: "free_instrument_platinum", requirement: .init(kind: .recordedDays, value: 365)),
        .init(key: "frame.free_instrument_iron_seal", kind: .iconFrame, displayName: "黒鉄封環", systemImageName: "circle", tintHex: "#59606B", targetID: "free_instrument_iron_seal", requirement: .cumulativeScore(1_500)),
        .init(key: "frame.free_instrument_bronze_seal", kind: .iconFrame, displayName: "銅封環", systemImageName: "circle", tintHex: "#B87545", targetID: "free_instrument_bronze_seal", requirement: .cumulativeScore(3_900)),
        .init(key: "frame.free_instrument_silver_seal", kind: .iconFrame, displayName: "銀封環", systemImageName: "circle", tintHex: "#D8DEE8", targetID: "free_instrument_silver_seal", requirement: .cumulativeScore(7_800)),
        .init(key: "frame.free_instrument_gold_seal", kind: .iconFrame, displayName: "金封環", systemImageName: "circle", tintHex: "#F2C94C", targetID: "free_instrument_gold_seal", requirement: .cumulativeScore(13_200)),
        .init(key: "frame.free_instrument_platinum_seal", kind: .iconFrame, displayName: "白金封環", systemImageName: "circle", tintHex: "#F2F4FF", targetID: "free_instrument_platinum_seal", requirement: .cumulativeScore(21_600)),
        .init(key: "frame.free_instrument_iron_orbit", kind: .iconFrame, displayName: "黒鉄遺環", systemImageName: "circle", tintHex: "#59606B", targetID: "free_instrument_iron_orbit", requirement: .init(kind: .recordedHours, value: 50)),
        .init(key: "frame.free_instrument_bronze_orbit", kind: .iconFrame, displayName: "銅遺環", systemImageName: "circle", tintHex: "#B87545", targetID: "free_instrument_bronze_orbit", requirement: .init(kind: .recordedHours, value: 150)),
        .init(key: "frame.free_instrument_silver_orbit", kind: .iconFrame, displayName: "銀遺環", systemImageName: "circle", tintHex: "#D8DEE8", targetID: "free_instrument_silver_orbit", requirement: .init(kind: .recordedHours, value: 1_000)),
        .init(key: "frame.free_instrument_gold_orbit", kind: .iconFrame, displayName: "金遺環", systemImageName: "circle", tintHex: "#F2C94C", targetID: "free_instrument_gold_orbit", requirement: .init(kind: .recordedHours, value: 2_500)),
        .init(key: "frame.free_instrument_platinum_orbit", kind: .iconFrame, displayName: "白金遺環", systemImageName: "circle", tintHex: "#F2F4FF", targetID: "free_instrument_platinum_orbit", requirement: .init(kind: .recordedHours, value: 8_000)),
        .init(key: "frame.free_instrument_iron_crest", kind: .iconFrame, displayName: "黒鉄冠環", systemImageName: "circle", tintHex: "#59606B", targetID: "free_instrument_iron_crest", requirement: .init(kind: .planMatchedDays, value: 3)),
        .init(key: "frame.free_instrument_bronze_crest", kind: .iconFrame, displayName: "銅冠環", systemImageName: "circle", tintHex: "#B87545", targetID: "free_instrument_bronze_crest", requirement: .init(kind: .planMatchedDays, value: 7)),
        .init(key: "frame.free_instrument_silver_crest", kind: .iconFrame, displayName: "銀冠環", systemImageName: "circle", tintHex: "#D8DEE8", targetID: "free_instrument_silver_crest", requirement: .init(kind: .planMatchedDays, value: 30)),
        .init(key: "frame.free_instrument_gold_crest", kind: .iconFrame, displayName: "金冠環", systemImageName: "circle", tintHex: "#F2C94C", targetID: "free_instrument_gold_crest", requirement: .init(kind: .planMatchedDays, value: 100)),
        .init(key: "frame.free_instrument_platinum_crest", kind: .iconFrame, displayName: "白金冠環", systemImageName: "circle", tintHex: "#F2F4FF", targetID: "free_instrument_platinum_crest", requirement: .init(kind: .planMatchedDays, value: 365))
    ]

    private static let personalityFrameDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "frame.free_dawn_horizon", kind: .iconFrame, displayName: "暁線", systemImageName: "sunrise.fill", tintHex: "#FFB3C7", targetID: "free_dawn_horizon", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_ripple_border", kind: .iconFrame, displayName: "水縁", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "free_ripple_border", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_cloud_veil", kind: .iconFrame, displayName: "雲幕", systemImageName: "cloud.fill", tintHex: "#9BDCF8", targetID: "free_cloud_veil", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_leaf_corner", kind: .iconFrame, displayName: "葉隅", systemImageName: "leaf.fill", tintHex: "#5FE0A8", targetID: "free_leaf_corner", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_frost_edge", kind: .iconFrame, displayName: "霜縁", systemImageName: "snowflake", tintHex: "#8AB4FF", targetID: "free_frost_edge", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_thread_border", kind: .iconFrame, displayName: "糸枠", systemImageName: "scribble.variable", tintHex: "#C9A7FF", targetID: "free_thread_border", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_orbit_grid", kind: .iconFrame, displayName: "軌跡線", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "free_orbit_grid", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_rain", kind: .iconFrame, displayName: "雨粒", systemImageName: "cloud.rain.fill", tintHex: "#7DD3FC", targetID: "free_rain", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_candle", kind: .iconFrame, displayName: "灯影", systemImageName: "flame.fill", tintHex: "#FF8A5B", targetID: "free_candle", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_ink", kind: .iconFrame, displayName: "墨縁", systemImageName: "paintbrush.pointed.fill", tintHex: "#A78BFA", targetID: "free_ink", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_aurora_trace", kind: .iconFrame, displayName: "極光線", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "free_aurora_trace", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_glass_bead", kind: .iconFrame, displayName: "硝子点", systemImageName: "drop.circle.fill", tintHex: "#39D5E8", targetID: "free_glass_bead", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_linen_stitch", kind: .iconFrame, displayName: "織目", systemImageName: "circle.dashed", tintHex: "#C9A7FF", targetID: "free_linen_stitch", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_constellation", kind: .iconFrame, displayName: "星図線", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "free_constellation", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_wave", kind: .iconFrame, displayName: "波端", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "free_wave", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_mist", kind: .iconFrame, displayName: "霧面", systemImageName: "circle.dotted", tintHex: "#C9A7FF", targetID: "free_mist", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_petal_corner", kind: .iconFrame, displayName: "花隅", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "free_petal_corner", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_stone_path", kind: .iconFrame, displayName: "石径", systemImageName: "point.topleft.down.curvedto.point.bottomright.up", tintHex: "#5FE0A8", targetID: "free_stone_path", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_sunline", kind: .iconFrame, displayName: "陽線", systemImageName: "sunrise.fill", tintHex: "#FFC98A", targetID: "free_sunline", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "frame.free_night_bloom", kind: .iconFrame, displayName: "夜花", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "free_night_bloom", requirement: .init(kind: .exchange, value: 1))
    ]

    private static let cardDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "card.free_dawn_horizon_panel", kind: .cardStyle, displayName: "暁線", systemImageName: "sunrise.fill", tintHex: "#FFB3C7", targetID: "free_dawn_horizon_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_ripple_border_panel", kind: .cardStyle, displayName: "水縁", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "free_ripple_border_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_cloud_veil_panel", kind: .cardStyle, displayName: "雲幕", systemImageName: "cloud.fill", tintHex: "#9BDCF8", targetID: "free_cloud_veil_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_leaf_corner_panel", kind: .cardStyle, displayName: "葉隅", systemImageName: "leaf.fill", tintHex: "#5FE0A8", targetID: "free_leaf_corner_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_frost_edge_panel", kind: .cardStyle, displayName: "霜縁", systemImageName: "snowflake", tintHex: "#8AB4FF", targetID: "free_frost_edge_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_thread_border_panel", kind: .cardStyle, displayName: "糸枠", systemImageName: "scribble.variable", tintHex: "#C9A7FF", targetID: "free_thread_border_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_orbit_grid_panel", kind: .cardStyle, displayName: "軌跡線", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "free_orbit_grid_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_rain_panel", kind: .cardStyle, displayName: "雨粒", systemImageName: "cloud.rain.fill", tintHex: "#7DD3FC", targetID: "free_rain_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_candle_panel", kind: .cardStyle, displayName: "灯影", systemImageName: "flame.fill", tintHex: "#FF8A5B", targetID: "free_candle_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_ink_panel", kind: .cardStyle, displayName: "墨縁", systemImageName: "paintbrush.pointed.fill", tintHex: "#A78BFA", targetID: "free_ink_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_aurora_trace_panel", kind: .cardStyle, displayName: "極光線", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "free_aurora_trace_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_glass_bead_panel", kind: .cardStyle, displayName: "硝子点", systemImageName: "drop.circle.fill", tintHex: "#39D5E8", targetID: "free_glass_bead_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_linen_stitch_panel", kind: .cardStyle, displayName: "織目", systemImageName: "circle.dashed", tintHex: "#C9A7FF", targetID: "free_linen_stitch_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_constellation_panel", kind: .cardStyle, displayName: "星図線", systemImageName: "scope", tintHex: "#7DD3FC", targetID: "free_constellation_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_wave_panel", kind: .cardStyle, displayName: "波端", systemImageName: "water.waves", tintHex: "#39D5E8", targetID: "free_wave_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_mist_panel", kind: .cardStyle, displayName: "霧面", systemImageName: "circle.dotted", tintHex: "#C9A7FF", targetID: "free_mist_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_petal_corner_panel", kind: .cardStyle, displayName: "花隅", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "free_petal_corner_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_stone_path_panel", kind: .cardStyle, displayName: "石径", systemImageName: "point.topleft.down.curvedto.point.bottomright.up", tintHex: "#5FE0A8", targetID: "free_stone_path_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_sunline_panel", kind: .cardStyle, displayName: "陽線", systemImageName: "sunrise.fill", tintHex: "#FFC98A", targetID: "free_sunline_panel", requirement: .init(kind: .exchange, value: 1)),
        .init(key: "card.free_night_bloom_panel", kind: .cardStyle, displayName: "夜花", systemImageName: "camera.macro", tintHex: "#FF8FB3", targetID: "free_night_bloom_panel", requirement: .init(kind: .exchange, value: 1))
    ]

    private static let badgeDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "badge.planner", kind: .nameBadge, displayName: "予定実行型", systemImageName: "checkmark.seal.fill", tintHex: "#2F80ED", targetID: "planner", requirement: .init(kind: .planMatchedDays, value: 5)),
        .init(key: "badge.executor", kind: .nameBadge, displayName: "予定実行習慣型", systemImageName: "checkmark.seal.fill", tintHex: "#2F80ED", targetID: "executor", requirement: .init(kind: .planMatchedDays, value: 15)),
        .init(key: "badge.promise_keeper", kind: .nameBadge, displayName: "予定安定型", systemImageName: "checkmark.seal.fill", tintHex: "#5FE0A8", targetID: "promise_keeper", requirement: .init(kind: .planMatchedDays, value: 30)),
        .init(key: "badge.restorer", kind: .nameBadge, displayName: "回復優先型", systemImageName: "battery.100percent", tintHex: "#27AE60", targetID: "restorer", requirement: .init(kind: .chargeDays, value: 5)),
        .init(key: "badge.recovery_master", kind: .nameBadge, displayName: "しっかり充電型", systemImageName: "battery.100percent.bolt", tintHex: "#27AE60", targetID: "recovery_master", requirement: .init(kind: .chargeDays, value: 15)),
        .init(key: "badge.morning_type", kind: .nameBadge, displayName: "朝活型", systemImageName: "sunrise.fill", tintHex: "#F2994A", targetID: "morning_type", requirement: .init(kind: .morningPersonaDays, value: 5)),
        .init(key: "badge.morning_person", kind: .nameBadge, displayName: "朝習慣型", systemImageName: "sun.max.fill", tintHex: "#F2C94C", targetID: "morning_person", requirement: .init(kind: .morningPersonaDays, value: 15)),
        .init(key: "badge.night_walker", kind: .nameBadge, displayName: "夜集中型", systemImageName: "moon.stars.fill", tintHex: "#8AB4FF", targetID: "night_walker", requirement: .init(kind: .nightPersonaDays, value: 5)),
        .init(key: "badge.night_person", kind: .nameBadge, displayName: "深夜稼働型", systemImageName: "moon.haze.fill", tintHex: "#AEB4DD", targetID: "night_person", requirement: .init(kind: .nightPersonaDays, value: 15)),
        .init(key: "badge.recorder", kind: .nameBadge, displayName: "記録習慣型", systemImageName: "book.closed.fill", tintHex: "#6C5CE7", targetID: "recorder", requirement: .init(kind: .recordingHabitDays, value: 5)),
        .init(key: "badge.observer", kind: .nameBadge, displayName: "記録定着型", systemImageName: "eye.fill", tintHex: "#9B8CFF", targetID: "observer", requirement: .init(kind: .recordingHabitDays, value: 15)),
        .init(key: "badge.updater", kind: .nameBadge, displayName: "自己ベスト更新型", systemImageName: "arrow.up.right.circle.fill", tintHex: "#EB5757", targetID: "updater", requirement: .init(kind: .personalBestDays, value: 3)),
        .init(key: "badge.best_crafter", kind: .nameBadge, displayName: "更新上手型", systemImageName: "crown.fill", tintHex: "#F2C94C", targetID: "best_crafter", requirement: .init(kind: .personalBestDays, value: 10)),
        .init(key: "badge.comeback", kind: .nameBadge, displayName: "復帰上手型", systemImageName: "hand.wave.fill", tintHex: "#5FE0A8", targetID: "comeback", requirement: .init(kind: .returnAfterGapDays, value: 3)),
        .init(key: "badge.resetter", kind: .nameBadge, displayName: "立て直し型", systemImageName: "arrow.counterclockwise.circle.fill", tintHex: "#00A8A8", targetID: "resetter", requirement: .init(kind: .returnAfterGapDays, value: 8)),
        .init(key: "badge.pioneer", kind: .nameBadge, displayName: "新規開拓型", systemImageName: "sparkles", tintHex: "#D946EF", targetID: "pioneer", requirement: .init(kind: .firstRecordDays, value: 5)),
        .init(key: "badge.curious", kind: .nameBadge, displayName: "探索習慣型", systemImageName: "sparkle.magnifyingglass", tintHex: "#C9A7FF", targetID: "curious", requirement: .init(kind: .firstRecordDays, value: 12)),
        .init(key: "badge.balancer", kind: .nameBadge, displayName: "マルチ活動型", systemImageName: "scale.3d", tintHex: "#27AE60", targetID: "balancer", requirement: .init(kind: .balancedDays, value: 5)),
        .init(key: "badge.single_focus", kind: .nameBadge, displayName: "一点集中型", systemImageName: "scope", tintHex: "#EB5757", targetID: "single_focus", requirement: .init(kind: .focusedDays, value: 5)),
        .init(key: "badge.change_maker", kind: .nameBadge, displayName: "変化多め型", systemImageName: "arrow.left.arrow.right.circle.fill", tintHex: "#F2994A", targetID: "change_maker", requirement: .init(kind: .changeSignalDays, value: 10)),
        .init(key: "badge.sleep_rhythm", kind: .nameBadge, displayName: "睡眠リズム型", systemImageName: "moon.fill", tintHex: "#9B51E0", targetID: "sleep_rhythm", requirement: .init(kind: .sleepCategoryDays, value: 5)),
        .init(key: "badge.sleep_habit", kind: .nameBadge, displayName: "睡眠習慣型", systemImageName: "bed.double.fill", tintHex: "#A78BFA", targetID: "sleep_habit", requirement: .init(kind: .sleepCategoryDays, value: 15)),
        .init(key: "badge.work_driver", kind: .nameBadge, displayName: "仕事推進型", systemImageName: "briefcase.fill", tintHex: "#6C5CE7", targetID: "work_driver", requirement: .init(kind: .workCategoryDays, value: 5)),
        .init(key: "badge.work_habit", kind: .nameBadge, displayName: "仕事習慣型", systemImageName: "briefcase.circle.fill", tintHex: "#8B6BFF", targetID: "work_habit", requirement: .init(kind: .workCategoryDays, value: 15)),
        .init(key: "badge.study_focus", kind: .nameBadge, displayName: "勉強集中型", systemImageName: "book.closed.fill", tintHex: "#2F80ED", targetID: "study_focus", requirement: .init(kind: .studyCategoryDays, value: 5)),
        .init(key: "badge.study_habit", kind: .nameBadge, displayName: "勉強習慣型", systemImageName: "graduationcap.fill", tintHex: "#39D5E8", targetID: "study_habit", requirement: .init(kind: .studyCategoryDays, value: 15)),
        .init(key: "badge.hobby_rich", kind: .nameBadge, displayName: "趣味充実型", systemImageName: "sparkles", tintHex: "#EB5757", targetID: "hobby_rich", requirement: .init(kind: .hobbyPlayCategoryDays, value: 5)),
        .init(key: "badge.hobby_habit", kind: .nameBadge, displayName: "趣味習慣型", systemImageName: "gamecontroller.fill", tintHex: "#F2994A", targetID: "hobby_habit", requirement: .init(kind: .hobbyPlayCategoryDays, value: 15)),
        .init(key: "badge.exercise_action", kind: .nameBadge, displayName: "運動実行型", systemImageName: "figure.run", tintHex: "#27AE60", targetID: "exercise_action", requirement: .init(kind: .exerciseCategoryDays, value: 5)),
        .init(key: "badge.exercise_habit", kind: .nameBadge, displayName: "運動習慣型", systemImageName: "figure.strengthtraining.traditional", tintHex: "#5FE0A8", targetID: "exercise_habit", requirement: .init(kind: .exerciseCategoryDays, value: 15)),
        .init(key: "badge.household_keeper", kind: .nameBadge, displayName: "生活整備型", systemImageName: "house.fill", tintHex: "#56CCF2", targetID: "household_keeper", requirement: .init(kind: .householdCategoryDays, value: 5)),
        .init(key: "badge.household_habit", kind: .nameBadge, displayName: "生活習慣型", systemImageName: "checklist", tintHex: "#7DD3FC", targetID: "household_habit", requirement: .init(kind: .householdCategoryDays, value: 15))
    ]

    // 獲得テーマは極光のみ（docs/17 マネタイズ方針：テーマは課金カタログの主力とし、
    // 無料の入口として1つだけ残す）。暁・茜・朧・残照・月白は課金候補として温存のため
    // カタログから除外。除外した built-in 行は UnlockStore.removeRetiredBuiltInItems が掃除する。
    private static let retainedThemeAndStreakDefinitions: [UnlockCatalogDefinition] = [
        .init(key: "streak.orange_flame", kind: .streakIcon, displayName: "橙の炎", systemImageName: "flame.fill", tintHex: "#F2994A", targetID: "orange_flame", requirement: .init(kind: .streakDays, value: 3)),
        .init(key: "theme.aurora", kind: .theme, displayName: "極光", systemImageName: "sparkles", tintHex: "#5FE0A8", targetID: "aurora", requirement: .init(kind: .recordedDays, value: 7)),
        .init(key: "streak.yellow_flame", kind: .streakIcon, displayName: "黄色の炎", systemImageName: "flame.fill", tintHex: "#F2C94C", targetID: "yellow_flame", requirement: .init(kind: .streakDays, value: 7)),
        .init(key: "streak.lime_flame", kind: .streakIcon, displayName: "黄緑の炎", systemImageName: "flame.fill", tintHex: "#A3E635", targetID: "lime_flame", requirement: .init(kind: .streakDays, value: 14)),
        .init(key: "streak.green_flame", kind: .streakIcon, displayName: "緑の炎", systemImageName: "flame.fill", tintHex: "#27AE60", targetID: "green_flame", requirement: .init(kind: .streakDays, value: 30)),
        .init(key: "streak.blue_flame", kind: .streakIcon, displayName: "青い炎", systemImageName: "flame.fill", tintHex: "#2F80ED", targetID: "blue_flame", requirement: .init(kind: .streakDays, value: 60)),
        .init(key: "streak.purple_flame", kind: .streakIcon, displayName: "紫の炎", systemImageName: "flame.fill", tintHex: "#6C5CE7", targetID: "purple_flame", requirement: .init(kind: .streakDays, value: 90))
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
            // 交換アイテムは「次に解放」の予告対象にしない（ユーザーが選んで交換するもの）
            .filter { $0.unlockedAt == nil && $0.requirementKind != .exchange && !isUnlocked($0, metrics: metrics) }
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

import Foundation

struct ProfileUnlockTarget: Identifiable, Equatable {
    let id: String
    let key: String
    let kind: UnlockKind
    let displayName: String
    let systemImageName: String
    let tintHex: String
    let requiredCumulativeScore: Int
    let requirementKind: UnlockRequirementKind
    let requiredValue: Int
    let currentValue: Int
    let remainingValue: Int
    let progress: Double
    let sortOrder: Int

    var progressPercent: Int {
        Int((progress * 100).rounded(.down))
    }

    var kindTitle: String {
        switch kind {
        case .theme:
            return "テーマ"
        case .iconFrame:
            return "フレーム"
        case .nameBadge:
            return "バッジ"
        case .streakIcon:
            return "ストリーク"
        case .cardStyle:
            return "カード"
        case .appIcon:
            return "アイコン"
        case .stamp:
            return "スタンプ"
        case .barStyle:
            return "バー"
        case .cardTemplate:
            return "カード"
        }
    }

    var remainingText: String {
        guard remainingValue > 0 else { return "受け取り待ち" }
        switch requirementKind {
        case .cumulativeScore:
            return "あと \(remainingValue.formatted())pt"
        case .recordedDays:
            return "あと \(remainingValue.formatted())日"
        case .recordedHours:
            return "あと \(remainingValue.formatted())時間"
        case .streakDays:
            return "あと \(remainingValue.formatted())日連続"
        case .earlyRecordDays:
            return "あと \(remainingValue.formatted())回 朝記録"
        case .lateNightRecordDays:
            return "あと \(remainingValue.formatted())回 深夜記録"
        case .distinctCategoryCount:
            return "あと \(remainingValue.formatted())種類"
        }
    }
}

enum ProfileUnlockTargetCatalog {
    static func targets(
        cumulativeScore: Int,
        unlockItems: [UnlockItem],
        limit: Int = 3
    ) -> [ProfileUnlockTarget] {
        targets(metrics: .score(cumulativeScore), unlockItems: unlockItems, limit: limit)
    }

    static func targets(
        metrics: UnlockMetrics,
        unlockItems: [UnlockItem],
        limit: Int = 3
    ) -> [ProfileUnlockTarget] {
        guard limit > 0 else { return [] }

        return unlockItems
            .filter { $0.unlockedAt == nil && !$0.targetID.isEmpty }
            .map { item in
                let currentValue = metrics.value(for: item.requirementKind)
                return ProfileUnlockTarget(
                    id: item.key,
                    key: item.key,
                    kind: item.kind,
                    displayName: item.displayName,
                    systemImageName: item.systemImageName,
                    tintHex: item.tintHex,
                    requiredCumulativeScore: item.requiredCumulativeScore,
                    requirementKind: item.requirementKind,
                    requiredValue: item.requiredValue,
                    currentValue: currentValue,
                    remainingValue: UnlockRules.remainingValue(metrics: metrics, toward: item),
                    progress: UnlockRules.progress(metrics: metrics, toward: item),
                    sortOrder: item.sortOrder
                )
            }
            .sorted {
                if $0.progress != $1.progress {
                    return $0.progress > $1.progress
                }
                if $0.remainingValue == $1.remainingValue {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.remainingValue < $1.remainingValue
            }
            .prefix(limit)
            .map { $0 }
    }
}

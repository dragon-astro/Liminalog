import Foundation

struct ProfileUnlockTarget: Identifiable, Equatable {
    let id: String
    let key: String
    let kind: UnlockKind
    let displayName: String
    let systemImageName: String
    let tintHex: String
    let requiredCumulativeScore: Int
    let remainingScore: Int
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
}

enum ProfileUnlockTargetCatalog {
    static func targets(
        cumulativeScore: Int,
        unlockItems: [UnlockItem],
        limit: Int = 3
    ) -> [ProfileUnlockTarget] {
        guard limit > 0 else { return [] }
        let currentScore = max(cumulativeScore, 0)

        return unlockItems
            .filter { $0.unlockedAt == nil && !$0.targetID.isEmpty }
            .map { item in
                let remainingScore = max(item.requiredCumulativeScore - currentScore, 0)
                return ProfileUnlockTarget(
                    id: item.key,
                    key: item.key,
                    kind: item.kind,
                    displayName: item.displayName,
                    systemImageName: item.systemImageName,
                    tintHex: item.tintHex,
                    requiredCumulativeScore: item.requiredCumulativeScore,
                    remainingScore: remainingScore,
                    progress: UnlockRules.progress(cumulativeScore: currentScore, toward: item),
                    sortOrder: item.sortOrder
                )
            }
            .sorted {
                if $0.remainingScore == $1.remainingScore {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.remainingScore < $1.remainingScore
            }
            .prefix(limit)
            .map { $0 }
    }
}

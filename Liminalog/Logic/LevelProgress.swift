import Foundation

/// 個性装飾の入手経済（doc 16 §12.0.1）。
///
/// - レベルは累積スコアからの純粋な導出値。一方向にしか動かず絶対に減らない。
/// - ひかりのかけら（交換チケット）はレベルアップごとに1枚。
///   残高 = 獲得かけら(到達レベル − 1) − 交換済みアイテム数 の導出値で、永続データは持たない。
/// - かけらは課金で売らない。プレミアム装飾はかけらで交換できない（経済の完全分離）。
enum LiminalLevel {
    /// レベル n 到達に必要な累積スコア。増分は 30(n−1) の等差＝序盤は速く、後半ゆっくり。
    /// Lv.2=30（初日）、Lv.10=1,350、Lv.21=6,300、Lv.40=23,400（約1年強）。
    static func requiredScore(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        return 15 * level * (level - 1)
    }

    /// 累積スコアから現在レベル（1始まり）を導く。
    static func level(forScore score: Int) -> Int {
        guard score > 0 else { return 1 }
        // 15n(n−1) <= score を満たす最大の n（閉形式＋境界補正）
        var level = max(1, Int((1 + (1 + 4 * Double(score) / 15).squareRoot()) / 2))
        while requiredScore(for: level + 1) <= score {
            level += 1
        }
        while level > 1 && requiredScore(for: level) > score {
            level -= 1
        }
        return level
    }

    /// 次のレベルまでの進捗。current/required はレベル区間内の相対値。
    static func progressToNextLevel(score: Int) -> (current: Int, required: Int, fraction: Double) {
        let current = level(forScore: score)
        let base = requiredScore(for: current)
        let span = max(requiredScore(for: current + 1) - base, 1)
        let value = min(max(score - base, 0), span)
        return (value, span, Double(value) / Double(span))
    }

    /// これまでに獲得したかけら総数（レベルアップ1回につき1枚。Lv.1は0枚）。
    static func earnedFragments(forScore score: Int) -> Int {
        level(forScore: score) - 1
    }

    /// かけら残高。交換済み数は UnlockItem の requirementKind == .exchange かつ
    /// unlockedAt != nil の件数を渡す。
    static func fragmentBalance(score: Int, exchangedCount: Int) -> Int {
        max(0, earnedFragments(forScore: score) - max(exchangedCount, 0))
    }

    /// 交換済みアイテム数（unlockItems から導出するヘルパ）。
    static func exchangedCount(in unlockItems: [UnlockItem]) -> Int {
        unlockItems.filter { $0.requirementKind == .exchange && $0.unlockedAt != nil }.count
    }
}

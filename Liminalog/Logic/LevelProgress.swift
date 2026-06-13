import Foundation

enum LiminalLevel {
    static func requiredScore(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        return 15 * level * (level - 1)
    }

    static func level(forScore score: Int) -> Int {
        guard score > 0 else { return 1 }
        var level = max(1, Int((1 + (1 + 4 * Double(score) / 15).squareRoot()) / 2))
        while requiredScore(for: level + 1) <= score {
            level += 1
        }
        while level > 1 && requiredScore(for: level) > score {
            level -= 1
        }
        return level
    }

    static func progressToNextLevel(score: Int) -> (current: Int, required: Int, fraction: Double) {
        let current = level(forScore: score)
        let base = requiredScore(for: current)
        let span = max(requiredScore(for: current + 1) - base, 1)
        let value = min(max(score - base, 0), span)
        return (value, span, Double(value) / Double(span))
    }

    static func earnedFragments(forScore score: Int) -> Int {
        level(forScore: score) - 1
    }

    static func fragmentBalance(score: Int, exchangedCount: Int) -> Int {
        max(0, earnedFragments(forScore: score) - max(exchangedCount, 0))
    }

}

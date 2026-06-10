import Foundation

/// 1日分のスコア計算結果をキャッシュする。
/// カレンダーは開くたび・オーバーレイ切替のたびにページキャッシュを破棄して再計算するため、
/// 予定/実績が変わっていない日まで毎回 `ScoreCalculator.summary` を回すと重い。
/// その日の予定・実績の内容から軽い署名を作り、署名が同じなら前回の結果を再利用する。
/// （署名計算は O(予定数+実績数)、スコア計算は O(予定数×実績数) なので、変化が無ければ確実に得。）
enum CalendarDayScoreCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Date: (signature: Int, summary: ScoreSummary)] = [:]
    private static let maxEntries = 800 // 約2年分の日数。超えたら丸ごと破棄して上限を保つ。

    static func summary(
        date: Date,
        dayStart: Date,
        plans: [PlanBlock],
        chapters: [Chapter],
        calendar: Calendar,
        now: Date
    ) -> ScoreSummary {
        let signature = makeSignature(plans: plans, chapters: chapters, now: now)

        lock.lock()
        if let cached = cache[dayStart], cached.signature == signature {
            let summary = cached.summary
            lock.unlock()
            return summary
        }
        lock.unlock()

        let summary = ScoreCalculator.summary(
            date: date,
            plans: plans,
            chapters: chapters,
            calendar: calendar,
            now: now
        )

        lock.lock()
        if cache.count >= maxEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[dayStart] = (signature, summary)
        lock.unlock()

        return summary
    }

    private static func makeSignature(plans: [PlanBlock], chapters: [Chapter], now: Date) -> Int {
        var hasher = Hasher()
        hasher.combine(plans.count)
        for plan in plans {
            hasher.combine(plan.id)
            hasher.combine(plan.isAllDay)
            hasher.combine(plan.category?.id)
            hasher.combine(plan.startTime)
            hasher.combine(plan.endTime)
        }
        hasher.combine(chapters.count)
        var hasActiveChapter = false
        for chapter in chapters {
            hasher.combine(chapter.id)
            hasher.combine(chapter.category?.id)
            hasher.combine(chapter.startTime)
            if let endTime = chapter.endTime {
                hasher.combine(endTime)
            } else {
                hasActiveChapter = true
            }
        }
        // 進行中チャプターは now で実効長が変わるため、分単位で署名に織り込む（その日は分ごとに再計算）。
        if hasActiveChapter {
            hasher.combine(Int(now.timeIntervalSince1970 / 60))
        }
        return hasher.finalize()
    }
}

import Foundation

struct ScoreSummary {
    let date: Date
    let categoryScore: Double
    let timelineScore: Double
    let totalScore: Double
    let plannedDuration: TimeInterval
    let recordedDuration: TimeInterval
    let matchedDuration: TimeInterval

    var gradeText: String {
        switch totalScore {
        case 90...: "かなり予定通り"
        case 75..<90: "いい感じ"
        case 60..<75: "合格ライン"
        case 30..<60: "そこそこ"
        case 1..<30: "もう少し"
        default: "予定待ち"
        }
    }
}

enum ScoreCalculator {
    static let categoryWeight = 0.8
    static let timelineWeight = 0.2

    static func summary(date: Date, plans: [PlanBlock], chapters: [Chapter], calendar: Calendar = .current, now: Date = Date()) -> ScoreSummary {
        let boundary = DayBoundary(date: date, calendar: calendar)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let clippedPlans = plans
            .filter { !$0.isAllDay }
            .map { TimeSlice(categoryID: $0.category?.id, start: max($0.startTime, dayStart), end: min($0.endTime, dayEnd)) }
            .filter { $0.duration > 0 }
        let clippedChapters = chapters
            .filter { chapter in
                // 記録中は常に含める。完了済みは1分以上のものだけスコアに反映する。
                // 1分未満の完了チャプターは誤タップとみなしスコアから除外する。
                guard let end = chapter.endTime else { return true }
                return end.timeIntervalSince(chapter.startTime) >= 60
            }
            .map { TimeSlice(categoryID: $0.category?.id, start: max($0.startTime, dayStart), end: min($0.endTime ?? now, dayEnd)) }
            .filter { $0.duration > 0 }

        let plannedDuration = clippedPlans.reduce(0) { $0 + $1.duration }
        let recordedDuration = clippedChapters.reduce(0) { $0 + $1.duration }
        guard plannedDuration > 0 else {
            return ScoreSummary(
                date: date,
                categoryScore: 0,
                timelineScore: 0,
                totalScore: 0,
                plannedDuration: 0,
                recordedDuration: recordedDuration,
                matchedDuration: 0
            )
        }

        let categoryScore = categoryAchievementScore(plans: clippedPlans, chapters: clippedChapters)
        let matchedDuration = timelineMatchedDuration(plans: clippedPlans, chapters: clippedChapters)
        let timelineScore = min(matchedDuration / plannedDuration, 1) * 100
        let total = categoryScore * categoryWeight + timelineScore * timelineWeight

        return ScoreSummary(
            date: date,
            categoryScore: categoryScore,
            timelineScore: timelineScore,
            totalScore: min(total, 100),
            plannedDuration: plannedDuration,
            recordedDuration: recordedDuration,
            matchedDuration: matchedDuration
        )
    }

    private static func categoryAchievementScore(plans: [TimeSlice], chapters: [TimeSlice]) -> Double {
        let plannedByCategory = Dictionary(grouping: plans, by: \.categoryID)
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        let recordedByCategory = Dictionary(grouping: chapters, by: \.categoryID)
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        let plannedTotal = plannedByCategory.values.reduce(0, +)
        guard plannedTotal > 0 else { return 0 }

        let achieved = plannedByCategory.reduce(0) { partial, entry in
            let recorded = recordedByCategory[entry.key] ?? 0
            return partial + min(recorded, entry.value)
        }
        return min(achieved / plannedTotal, 1) * 100
    }

    private static func timelineMatchedDuration(plans: [TimeSlice], chapters: [TimeSlice]) -> TimeInterval {
        let tolerance: TimeInterval = 15 * 60
        return plans.reduce(0) { partial, plan in
            let matches = chapters.filter { $0.categoryID == plan.categoryID }
            let matched = matches.reduce(0) { chapterPartial, chapter in
                let toleratedStart = chapter.start.addingTimeInterval(-tolerance)
                let toleratedEnd = chapter.end.addingTimeInterval(tolerance)
                let overlapStart = max(plan.start, toleratedStart)
                let overlapEnd = min(plan.end, toleratedEnd)
                return chapterPartial + max(overlapEnd.timeIntervalSince(overlapStart), 0)
            }
            return partial + min(matched, plan.duration)
        }
    }
}

private struct TimeSlice {
    let categoryID: UUID?
    let start: Date
    let end: Date

    var duration: TimeInterval {
        max(end.timeIntervalSince(start), 0)
    }
}

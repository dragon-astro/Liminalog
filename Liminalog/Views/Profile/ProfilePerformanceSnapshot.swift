import Foundation
import SwiftData

struct ProfilePerformanceSnapshot {
    let totalEarnedScore: Int
    let streakCount: Int
    let recordedDayCount: Int
    let totalRecordedDuration: TimeInterval
    let earlyRecordDayCount: Int
    let lateNightRecordDayCount: Int
    let distinctCategoryCount: Int
    let unlockMetrics: UnlockMetrics

    static let empty = ProfilePerformanceSnapshot(
        totalEarnedScore: 0,
        streakCount: 0,
        recordedDayCount: 0,
        totalRecordedDuration: 0,
        earlyRecordDayCount: 0,
        lateNightRecordDayCount: 0,
        distinctCategoryCount: 0,
        unlockMetrics: UnlockMetrics()
    )

    @MainActor
    static func load(modelContext: ModelContext, now: Date, calendar: Calendar = .japanese) -> ProfilePerformanceSnapshot {
        let todayStart = DayBoundary.dayStart(for: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let interval = DateInterval(start: start, end: end)

        let plans = ScoreSnapshotLoader.plannedBlocks(in: interval, modelContext: modelContext)
        let chapters = ScoreSnapshotLoader.chapters(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        let allChaptersDescriptor = FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)])
        let allChapters = (try? modelContext.fetch(allChaptersDescriptor)) ?? []
        let summaries = ScoreSnapshotLoader.days(in: interval, calendar: calendar).map { date in
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            return ScoreCalculator.summary(date: date, plans: dayPlans, chapters: dayChapters, calendar: calendar, now: now)
        }

        var streak = 0
        for summary in summaries.reversed() {
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            streak += 1
        }

        let totalEarnedScore = summaries.reduce(0) { $0 + Int($1.totalScore.rounded()) }
        let recordedDayStarts = Set(allChapters.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) })
        let completedChapters = allChapters.filter { $0.endTime != nil }
        let earlyRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard (5..<9).contains(hour) else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let lateNightRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard hour >= 23 || hour < 3 else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let totalRecordedDuration = allChapters.reduce(0) { $0 + max(0, ($1.endTime ?? now).timeIntervalSince($1.startTime)) }
        let distinctCategoryCount = Set(allChapters.compactMap { $0.category?.id }).count
        let unlockMetrics = UnlockMetrics(
            cumulativeScore: totalEarnedScore,
            recordedDays: recordedDayStarts.count,
            recordedHours: max(0, Int(totalRecordedDuration / 3600)),
            streakDays: streak,
            earlyRecordDays: earlyRecordDayCount,
            lateNightRecordDays: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount
        )

        return ProfilePerformanceSnapshot(
            totalEarnedScore: totalEarnedScore,
            streakCount: streak,
            recordedDayCount: recordedDayStarts.count,
            totalRecordedDuration: totalRecordedDuration,
            earlyRecordDayCount: earlyRecordDayCount,
            lateNightRecordDayCount: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount,
            unlockMetrics: unlockMetrics
        )
    }
}

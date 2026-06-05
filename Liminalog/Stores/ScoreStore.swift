import Foundation
import SwiftData

@MainActor
final class ScoreStore {
    private let modelContext: ModelContext
    private let clock: any LiminalogClock

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        self.modelContext = modelContext
        self.clock = clock
    }

    func scoreSummary(on date: Date) -> ScoreSummary {
        scoreSummaryIfAvailable(on: date) ?? ScoreCalculator.summary(
            date: date,
            plans: [],
            chapters: [],
            now: clock.now
        )
    }

    func scoreSummaryIfAvailable(on date: Date) -> ScoreSummary? {
        guard let plans = plannedBlocksIfAvailable(on: date),
              let chapters = chaptersIfAvailable(on: date)
        else {
            return nil
        }
        return ScoreCalculator.summary(
            date: date,
            plans: plans,
            chapters: chapters,
            now: clock.now
        )
    }

    func streakCount(endingAt date: Date = Date()) -> Int {
        streakCountIfAvailable(endingAt: date) ?? 0
    }

    func streakCountIfAvailable(endingAt date: Date = Date()) -> Int? {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: date) else { break }
            guard let summary = scoreSummaryIfAvailable(on: target) else { break }
            let qualifies = summary.plannedDuration > 0 && summary.totalScore >= StreakRules.passingScore
            if qualifies {
                count += 1
                continue
            }
            // 進行中の「今日」はまだ未達でも連続を切らない（昨日以前で数える）。
            // 通知の昨日起点カウント等、ループに今日が含まれない呼び出しには影響しない。
            if calendar.isDate(target, inSameDayAs: clock.now) {
                continue
            }
            break
        }
        return count
    }

    func totalScore(days: Int = 365) -> Int {
        totalScoreIfAvailable(days: days) ?? 0
    }

    func totalScoreIfAvailable(days: Int = 365) -> Int? {
        let calendar = Calendar.current
        var total = 0
        for offset in 0..<days {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { continue }
            guard let summary = scoreSummaryIfAvailable(on: target) else { return nil }
            total += Int(summary.totalScore.rounded())
        }
        return total
    }

    private func plannedBlocks(on date: Date) -> [PlanBlock] {
        plannedBlocksIfAvailable(on: date) ?? []
    }

    private func plannedBlocksIfAvailable(on date: Date) -> [PlanBlock]? {
        let boundary = DayBoundary(date: date)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch score store plans: \(String(describing: error))")
            return nil
        }
    }

    private func chapters(on date: Date) -> [Chapter] {
        chaptersIfAvailable(on: date) ?? []
    }

    private func chaptersIfAvailable(on date: Date) -> [Chapter]? {
        let boundary = DayBoundary(date: date)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let now = clock.now
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
                .filter { ($0.endTime ?? now) > dayStart }
        } catch {
            NSLog("Liminalog: failed to fetch score store chapters: \(String(describing: error))")
            return nil
        }
    }
}

@MainActor
enum ScoreSnapshotLoader {
    static func summary(
        on date: Date,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> ScoreSummary {
        let boundary = DayBoundary(date: date, calendar: calendar)
        let interval = DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
        let plans = plannedBlocks(in: interval, modelContext: modelContext)
        let chapters = chapters(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        return ScoreCalculator.summary(date: date, plans: plans, chapters: chapters, calendar: calendar, now: now)
    }

    static func summaryIfAvailable(
        on date: Date,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> ScoreSummary? {
        let boundary = DayBoundary(date: date, calendar: calendar)
        let interval = DateInterval(start: boundary.dayStart, end: boundary.dayEnd)
        guard let plans = plannedBlocksIfAvailable(in: interval, modelContext: modelContext),
              let chapters = chaptersIfAvailable(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        else {
            return nil
        }
        return ScoreCalculator.summary(date: date, plans: plans, chapters: chapters, calendar: calendar, now: now)
    }

    static func summaries(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> [ScoreSummary] {
        summariesIfAvailable(in: interval, modelContext: modelContext, now: now, calendar: calendar) ?? []
    }

    static func summariesIfAvailable(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> [ScoreSummary]? {
        let dates = days(in: interval, calendar: calendar)
        guard !dates.isEmpty else { return [] }

        guard let plans = plannedBlocksIfAvailable(in: interval, modelContext: modelContext),
              let chapters = chaptersIfAvailable(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        else {
            return nil
        }

        return dates.map { date in
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            return ScoreCalculator.summary(
                date: date,
                plans: dayPlans,
                chapters: dayChapters,
                calendar: calendar,
                now: now
            )
        }
    }

    static func averageScore(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> Double {
        let scored = summaries(in: interval, modelContext: modelContext, now: now, calendar: calendar)
            .filter { $0.plannedDuration > 0 }
        guard !scored.isEmpty else { return 0 }
        return scored.map(\.totalScore).reduce(0, +) / Double(scored.count)
    }

    static func plannedBlocks(
        in interval: DateInterval,
        modelContext: ModelContext
    ) -> [PlanBlock] {
        plannedBlocksIfAvailable(in: interval, modelContext: modelContext) ?? []
    }

    private static func plannedBlocksIfAvailable(
        in interval: DateInterval,
        modelContext: ModelContext
    ) -> [PlanBlock]? {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch score plans: \(String(describing: error))")
            return nil
        }
    }

    static func chapters(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese,
        lookbackDays: Int = 14
    ) -> [Chapter] {
        chaptersIfAvailable(in: interval, modelContext: modelContext, now: now, calendar: calendar, lookbackDays: lookbackDays) ?? []
    }

    private static func chaptersIfAvailable(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese,
        lookbackDays: Int = 14
    ) -> [Chapter]? {
        let lookbackStart = calendar.date(byAdding: .day, value: -lookbackDays, to: interval.start) ?? interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= lookbackStart && $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let fetchedChapters: [Chapter]
        do {
            fetchedChapters = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch score chapters: \(String(describing: error))")
            return nil
        }
        var chapters = fetchedChapters.filter { ($0.endTime ?? now) > interval.start }

        let activeDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let existingIDs = Set(chapters.map(\.id))
        let activeChapters: [Chapter]
        do {
            activeChapters = try modelContext.fetch(activeDescriptor)
                .filter { !existingIDs.contains($0.id) && $0.startTime < end && ($0.endTime ?? now) > interval.start }
        } catch {
            NSLog("Liminalog: failed to fetch active score chapters: \(String(describing: error))")
            return nil
        }
        chapters.append(contentsOf: activeChapters)
        return chapters.sorted { $0.startTime < $1.startTime }
    }

    static func days(in interval: DateInterval, calendar: Calendar = .japanese) -> [Date] {
        var dates: [Date] = []
        var cursor = DayBoundary.dayStart(for: interval.start, calendar: calendar)
        while cursor < interval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }
}

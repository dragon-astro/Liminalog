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
        ScoreCalculator.summary(
            date: date,
            plans: plannedBlocks(on: date),
            chapters: chapters(on: date),
            now: clock.now
        )
    }

    func streakCount(endingAt date: Date = Date()) -> Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: date) else { break }
            let summary = scoreSummary(on: target)
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            count += 1
        }
        return count
    }

    func totalScore(days: Int = 365) -> Int {
        let calendar = Calendar.current
        return (0..<days).reduce(0) { partial, offset in
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { return partial }
            let summary = scoreSummary(on: target)
            return partial + Int(summary.totalScore.rounded())
        }
    }

    private func plannedBlocks(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let now = clock.now
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { ($0.endTime ?? now) > dayStart }
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

    static func summaries(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> [ScoreSummary] {
        let dates = days(in: interval, calendar: calendar)
        guard !dates.isEmpty else { return [] }

        let plans = plannedBlocks(in: interval, modelContext: modelContext)
        let chapters = chapters(in: interval, modelContext: modelContext, now: now, calendar: calendar)

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
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func chapters(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese,
        lookbackDays: Int = 14
    ) -> [Chapter] {
        let lookbackStart = calendar.date(byAdding: .day, value: -lookbackDays, to: interval.start) ?? interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= lookbackStart && $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var chapters = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { ($0.endTime ?? now) > interval.start }

        let activeDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let existingIDs = Set(chapters.map(\.id))
        let activeChapters = ((try? modelContext.fetch(activeDescriptor)) ?? [])
            .filter { !existingIDs.contains($0.id) && $0.startTime < end && ($0.endTime ?? now) > interval.start }
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

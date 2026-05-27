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

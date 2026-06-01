import Foundation

struct DailyCardPatternDetector {
    enum Shape {
        case sprinter
        case marathon
        case zapping
    }

    enum Chronotype {
        case morning
        case daytime
        case evening
        case midnight
        case unknown
    }

    let focusCategory: (category: Category, duration: TimeInterval)?
    let longestMeaningfulCategory: Category?
    let longestMeaningfulDuration: TimeInterval
    let shape: Shape
    let chronotype: Chronotype
    let signal: DailyCardPatternSignal?
    let discretionaryDuration: TimeInterval
    let restWasExcluded: Bool
    let isChargeDay: Bool
    let meaningfulSwitchCount: Int

    init(
        chapters: [Chapter],
        historyChapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        recordedDuration: TimeInterval,
        dayBoundary: DayBoundary
    ) {
        let restCategoryIDs = Self.majorRestCategoryIDs(
            chapters: chapters,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary
        )
        let nonRestRows = categoryRows.filter { !restCategoryIDs.contains($0.category.id) }
        let nonRestChapters = chapters.filter { chapter in
            guard let id = chapter.category?.id else { return true }
            return !restCategoryIDs.contains(id)
        }
        let effectiveChapters = nonRestChapters.isEmpty && !restCategoryIDs.isEmpty ? [] : (nonRestChapters.isEmpty ? chapters : nonRestChapters)
        let discretionaryDuration = nonRestRows.reduce(TimeInterval(0)) { $0 + $1.duration }
        let restDuration = max(0, recordedDuration - discretionaryDuration)
        let restWasExcluded = !restCategoryIDs.isEmpty && restDuration >= 60 * 60 && discretionaryDuration < recordedDuration
        let shape = Self.shape(for: effectiveChapters, dayBoundary: dayBoundary)
        let meaningfulSwitchCount = Self.meaningfulSwitchCount(for: effectiveChapters, dayBoundary: dayBoundary)
        let longestMeaningful = Self.longestMeaningfulBlock(for: effectiveChapters, dayBoundary: dayBoundary)

        self.focusCategory = nonRestRows.first ?? (restCategoryIDs.isEmpty ? categoryRows.first : nil)
        self.longestMeaningfulCategory = longestMeaningful.category
        self.longestMeaningfulDuration = longestMeaningful.duration
        self.shape = shape
        self.chronotype = Self.chronotype(for: effectiveChapters, dayBoundary: dayBoundary)
        self.signal = Self.signal(
            categoryRows: categoryRows,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary,
            excludedCategoryIDs: restCategoryIDs
        )
        self.discretionaryDuration = discretionaryDuration
        self.restWasExcluded = restWasExcluded
        self.isChargeDay = restWasExcluded && (restDuration >= 10 * 60 * 60 || (discretionaryDuration <= 60 * 60 && recordedDuration >= 8 * 60 * 60))
        self.meaningfulSwitchCount = meaningfulSwitchCount
    }

    private static func majorRestCategoryIDs(
        chapters: [Chapter],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> Set<UUID> {
        let calendar = Calendar.japanese
        let explicitRestIDs = Set((chapters + historyChapters).compactMap { chapter in
            chapter.category?.isDailyCardSleepCategory == true ? chapter.category?.id : nil
        })
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historicalDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        let source = historicalDays >= 7 ? historical : chapters
        guard !source.isEmpty else { return explicitRestIDs }

        struct RestCandidate {
            var category: Category
            var totalLongBlocks = 0
            var presenceDays = Set<Date>()
            var longestTotal: TimeInterval = 0
            var blockCount = 0
        }

        var candidates: [UUID: RestCandidate] = [:]
        for chapter in source {
            guard let category = chapter.category else { continue }
            let duration = rawDuration(for: chapter, fallbackEnd: dayBoundary.dayEnd)
            guard duration >= 3 * 60 * 60 else { continue }
            let day = DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
            var candidate = candidates[category.id] ?? RestCandidate(category: category)
            candidate.totalLongBlocks += 1
            candidate.presenceDays.insert(day)
            candidate.longestTotal += duration
            candidate.blockCount += 1
            candidates[category.id] = candidate
        }

        let detectedRestIDs = Set(candidates.compactMap { id, candidate in
            let averageLongBlock = candidate.longestTotal / Double(max(candidate.blockCount, 1))
            let dayBase = max(historicalDays, 1)
            let frequency = Double(candidate.presenceDays.count) / Double(dayBase)
            if historicalDays >= 7 {
                return frequency >= 0.42 && averageLongBlock >= 4 * 60 * 60 ? id : nil
            } else {
                return candidate.totalLongBlocks >= 1 && averageLongBlock >= 6 * 60 * 60 ? id : nil
            }
        })
        return explicitRestIDs.union(detectedRestIDs)
    }

    private static func shape(
        for chapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> Shape {
        let durations = chapters.map { clippedDuration(for: $0, dayBoundary: dayBoundary) }
            .filter { $0 >= 5 * 60 }
            .sorted()
        let longest = durations.max() ?? 0
        let median = medianDuration(durations)

        if longest >= 90 * 60 {
            return .sprinter
        }
        if durations.count >= 8 && median < 25 * 60 {
            return .zapping
        }
        return .marathon
    }

    private static func chronotype(for chapters: [Chapter], dayBoundary: DayBoundary) -> Chronotype {
        let deepNightEnd = dayBoundary.dayStart.addingTimeInterval(5 * 60 * 60)
        let deepNightDuration = chapters.reduce(TimeInterval(0)) { partial, chapter in
            partial + overlapDuration(for: chapter, from: dayBoundary.dayStart, to: deepNightEnd, dayBoundary: dayBoundary)
        }
        if deepNightDuration >= 60 * 60 {
            return .midnight
        }

        let weighted = chapters.reduce((total: TimeInterval(0), weighted: TimeInterval(0))) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            let duration = max(end.timeIntervalSince(start), 0)
            let midpoint = start.timeIntervalSince(dayBoundary.dayStart) + duration / 2
            return (partial.total + duration, partial.weighted + midpoint * duration)
        }
        guard weighted.total > 0 else { return .unknown }
        let hour = weighted.weighted / weighted.total / 3600
        switch hour {
        case 0..<5:
            return .midnight
        case 5..<11:
            return .morning
        case 11..<16:
            return .daytime
        default:
            return .evening
        }
    }

    private static func signal(
        categoryRows: [(category: Category, duration: TimeInterval)],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary,
        excludedCategoryIDs: Set<UUID>
    ) -> DailyCardPatternSignal? {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historyDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        guard historyDays >= 7 else { return nil }

        let todayRows = categoryRows.filter { !excludedCategoryIDs.contains($0.category.id) }
        var best: (signal: DailyCardPatternSignal, score: Double)?

        for row in todayRows where !excludedCategoryIDs.contains(row.category.id) {
            var dailyTotals: [Date: TimeInterval] = [:]
            var lastSeen: Date?
            var historicalCount = 0
            for chapter in historical where chapter.category?.id == row.category.id {
                let day = DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
                let duration = rawDuration(for: chapter, fallbackEnd: dayBoundary.dayStart)
                dailyTotals[day, default: 0] += duration
                lastSeen = max(lastSeen ?? day, day)
                historicalCount += 1
            }

            let values = (0..<28).compactMap { offset -> TimeInterval? in
                guard let day = calendar.date(byAdding: .day, value: -offset - 1, to: dayBoundary.dayStart) else { return nil }
                return dailyTotals[day, default: 0]
            }
            let mean = values.reduce(0, +) / Double(max(values.count, 1))
            let variance = values.reduce(0) { partial, value in
                partial + pow(value - mean, 2)
            } / Double(max(values.count, 1))
            let std = max(sqrt(variance), 15 * 60)
            let z = (row.duration - mean) / std
            let daysSinceLast: Int? = lastSeen.map { calendar.dateComponents([.day], from: $0, to: dayBoundary.dayStart).day ?? 0 }
            let delta = abs(row.duration - mean)
            let candidate: (DailyCardPatternSignal, Double)?

            if historicalCount == 0, row.duration >= 15 * 60 {
                candidate = (.firstRecord(category: row.category), 4 + min(row.duration / (60 * 60), 3))
            } else if let daysSinceLast, daysSinceLast >= 10 {
                candidate = (.returnAfterGap(category: row.category, days: daysSinceLast), 3 + min(Double(daysSinceLast) / 14, 3))
            } else if abs(z) >= 1.5, delta >= 20 * 60 {
                candidate = z > 0
                    ? (.moreThanUsual(category: row.category, delta: delta), abs(z))
                    : (.lessThanUsual(category: row.category, delta: delta), abs(z))
            } else {
                candidate = nil
            }

            if let candidate, candidate.1 > (best?.score ?? -Double.infinity) {
                best = (candidate.0, candidate.1)
            }
        }

        return best?.signal
    }

    private static func meaningfulSwitchCount(for chapters: [Chapter], dayBoundary: DayBoundary) -> Int {
        chapters.map { clippedDuration(for: $0, dayBoundary: dayBoundary) }
            .filter { $0 >= 5 * 60 }
            .count
    }

    private static func longestMeaningfulBlock(for chapters: [Chapter], dayBoundary: DayBoundary) -> (category: Category?, duration: TimeInterval) {
        chapters.reduce((category: nil, duration: TimeInterval(0))) { best, chapter in
            let duration = clippedDuration(for: chapter, dayBoundary: dayBoundary)
            guard duration > best.duration else { return best }
            return (chapter.category, duration)
        }
    }

    private static func clippedDuration(for chapter: Chapter, dayBoundary: DayBoundary) -> TimeInterval {
        let start = max(chapter.startTime, dayBoundary.dayStart)
        let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
        return max(end.timeIntervalSince(start), 0)
    }

    private static func overlapDuration(for chapter: Chapter, from windowStart: Date, to windowEnd: Date, dayBoundary: DayBoundary) -> TimeInterval {
        let start = max(max(chapter.startTime, dayBoundary.dayStart), windowStart)
        let end = min(min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd), windowEnd)
        return max(end.timeIntervalSince(start), 0)
    }

    private static func rawDuration(for chapter: Chapter, fallbackEnd: Date) -> TimeInterval {
        max(0, (chapter.endTime ?? fallbackEnd).timeIntervalSince(chapter.startTime))
    }

    private static func medianDuration(_ durations: [TimeInterval]) -> TimeInterval {
        guard !durations.isEmpty else { return 0 }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }
}

enum DailyCardPatternSignal {
    case firstRecord(category: Category)
    case returnAfterGap(category: Category, days: Int)
    case moreThanUsual(category: Category, delta: TimeInterval)
    case lessThanUsual(category: Category, delta: TimeInterval)
}

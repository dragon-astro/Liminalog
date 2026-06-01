import Foundation

struct DailyCardPatternDetector {
    enum DetectorKind {
        case routineDeviation
        case difference
        case personalBest
        case dayShape
        case timeOfDay
        case planMatch
        case categoryComposition
        case sensoryConversion
        case recordingHabit
        case mood
        case friendOverlap
        case declaredIntent
    }

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
    let spotlightFact: DailyCardPatternFact?
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
        let spotlight = Self.spotlight(
            categoryRows: categoryRows,
            effectiveRows: nonRestRows,
            effectiveChapters: effectiveChapters,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary,
            excludedCategoryIDs: restCategoryIDs
        )

        self.focusCategory = nonRestRows.first ?? (restCategoryIDs.isEmpty ? categoryRows.first : nil)
        self.longestMeaningfulCategory = longestMeaningful.category
        self.longestMeaningfulDuration = longestMeaningful.duration
        self.shape = shape
        self.chronotype = Self.chronotype(for: effectiveChapters, dayBoundary: dayBoundary)
        self.signal = spotlight?.signal
        self.spotlightFact = spotlight?.fact
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
        let explicitRestIDs = Set((chapters + historyChapters).compactMap { chapter in
            chapter.category?.isDailyCardSleepCategory == true ? chapter.category?.id : nil
        })
        let historyStart = dayBoundary.dayStart.addingTimeInterval(-28 * 24 * 60 * 60)
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historicalDays = Set(historical.map { dayOffset(for: $0.startTime, dayBoundary: dayBoundary) }).count
        let source = historicalDays >= 7 ? historical : chapters
        guard !source.isEmpty else { return explicitRestIDs }

        struct RestCandidate {
            var category: Category
            var totalLongBlocks = 0
            var presenceDays = Set<Int>()
            var longestTotal: TimeInterval = 0
            var blockCount = 0
        }

        var candidates: [UUID: RestCandidate] = [:]
        for chapter in source {
            guard let category = chapter.category else { continue }
            let duration = rawDuration(for: chapter, fallbackEnd: dayBoundary.dayEnd)
            guard duration >= 3 * 60 * 60 else { continue }
            let day = dayOffset(for: chapter.startTime, dayBoundary: dayBoundary)
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

    private static func spotlight(
        categoryRows: [(category: Category, duration: TimeInterval)],
        effectiveRows: [(category: Category, duration: TimeInterval)],
        effectiveChapters: [Chapter],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary,
        excludedCategoryIDs: Set<UUID>
    ) -> DailyCardPatternSpotlight? {
        let historyStart = dayBoundary.dayStart.addingTimeInterval(-28 * 24 * 60 * 60)
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historyDays = Set(historical.map { dayOffset(for: $0.startTime, dayBoundary: dayBoundary) }).count
        var candidates: [DailyCardPatternSpotlight] = []
        let todayRows = categoryRows.filter { !excludedCategoryIDs.contains($0.category.id) }

        if historyDays >= 7 {
            candidates += historicalCandidates(
                todayRows: todayRows,
                historical: historical,
                dayBoundary: dayBoundary
            )
            if let streakCandidate = recordingStreakCandidate(
                historical: historical,
                effectiveChapters: effectiveChapters,
                dayBoundary: dayBoundary
            ) {
                candidates.append(streakCandidate)
            }
        }

        if let composition = categoryCompositionCandidate(effectiveRows: effectiveRows) {
            candidates.append(composition)
        }

        let punchCandidates = candidates.filter { !$0.isFloor }
        let pool = punchCandidates.isEmpty ? candidates : punchCandidates
        return pool.max { lhs, rhs in
            lhs.selectionScore < rhs.selectionScore
        }
    }

    private static func historicalCandidates(
        todayRows: [(category: Category, duration: TimeInterval)],
        historical: [Chapter],
        dayBoundary: DayBoundary
    ) -> [DailyCardPatternSpotlight] {
        var candidates: [DailyCardPatternSpotlight] = []

        for row in todayRows {
            var dailyTotals: [Int: TimeInterval] = [:]
            var lastSeenOffset: Int?
            var historicalCount = 0
            for chapter in historical where chapter.category?.id == row.category.id {
                let day = dayOffset(for: chapter.startTime, dayBoundary: dayBoundary)
                let duration = rawDuration(for: chapter, fallbackEnd: dayBoundary.dayStart)
                dailyTotals[day, default: 0] += duration
                lastSeenOffset = max(lastSeenOffset ?? day, day)
                historicalCount += 1
            }

            let values = (1...28).map { offset -> TimeInterval in
                dailyTotals[-offset, default: 0]
            }
            let mean = values.reduce(0, +) / Double(max(values.count, 1))
            let variance = values.reduce(0) { partial, value in
                partial + pow(value - mean, 2)
            } / Double(max(values.count, 1))
            let std = max(sqrt(variance), 15 * 60)
            let z = (row.duration - mean) / std
            let daysSinceLast: Int? = lastSeenOffset.map { abs($0) }
            let delta = abs(row.duration - mean)
            let previousBest = values.max() ?? 0
            let isPersonalBest = previousBest >= 15 * 60 && row.duration >= previousBest + 20 * 60

            if historicalCount == 0, row.duration >= 15 * 60 {
                candidates.append(DailyCardPatternSpotlight(
                    kind: .routineDeviation,
                    signal: .firstRecord(category: row.category),
                    fact: DailyCardPatternFact(id: "signal-first", title: "初記録", value: row.category.name, suffix: nil, systemImage: "sparkles"),
                    punch: 4 + min(row.duration / (60 * 60), 3),
                    newsworthiness: 1.1,
                    isFloor: false
                ))
            } else if let daysSinceLast, daysSinceLast >= 10 {
                candidates.append(DailyCardPatternSpotlight(
                    kind: .routineDeviation,
                    signal: .returnAfterGap(category: row.category, days: daysSinceLast),
                    fact: DailyCardPatternFact(id: "signal-gap", title: "復帰", value: "\(daysSinceLast)", suffix: "日ぶり", systemImage: "hand.wave.fill"),
                    punch: 3 + min(Double(daysSinceLast) / 14, 3),
                    newsworthiness: 1.0,
                    isFloor: false
                ))
            }

            if isPersonalBest {
                let improvement = row.duration - previousBest
                candidates.append(DailyCardPatternSpotlight(
                    kind: .personalBest,
                    signal: .personalBest(category: row.category, duration: row.duration, previousBest: previousBest),
                    fact: DailyCardPatternFact(id: "signal-best", title: "自己最長", value: formatPatternDuration(row.duration), suffix: nil, systemImage: "crown.fill"),
                    punch: 6.0 + min(improvement / (30 * 60), 2.0),
                    newsworthiness: 1.15,
                    isFloor: false
                ))
            }

            if abs(z) >= 1.5, delta >= 20 * 60 {
                let declaredIntentMatches = row.category.dailyCardIntent != .neutral
                if isPersonalBest && !declaredIntentMatches {
                    continue
                }
                let signal: DailyCardPatternSignal = z > 0
                    ? .moreThanUsual(category: row.category, delta: delta)
                    : .lessThanUsual(category: row.category, delta: delta)
                let fact = DailyCardPatternFact(
                    id: z > 0 ? "signal-more" : "signal-less",
                    title: "いつもより",
                    value: formatPatternDuration(delta),
                    suffix: z > 0 ? "多め" : "控えめ",
                    systemImage: z > 0 ? "arrow.up.right" : "arrow.down.right"
                )
                candidates.append(DailyCardPatternSpotlight(
                    kind: declaredIntentMatches ? .declaredIntent : .difference,
                    signal: signal,
                    fact: fact,
                    punch: min(abs(z), 5.5) + (declaredIntentMatches ? 1.3 : 0),
                    newsworthiness: declaredIntentMatches ? 1.45 : 1.0,
                    isFloor: false
                ))
            }
        }

        return candidates
    }

    private static func recordingStreakCandidate(
        historical: [Chapter],
        effectiveChapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> DailyCardPatternSpotlight? {
        guard !effectiveChapters.isEmpty else { return nil }
        let daysWithRecords = Set(historical.map { dayOffset(for: $0.startTime, dayBoundary: dayBoundary) })
        var streak = 1
        var offset = -1
        while daysWithRecords.contains(offset) {
            streak += 1
            offset -= 1
        }
        guard streak >= 5 else { return nil }
        return DailyCardPatternSpotlight(
            kind: .recordingHabit,
            signal: nil,
            fact: DailyCardPatternFact(id: "habit-streak", title: "記録", value: "\(streak)", suffix: "日連続", systemImage: "flame.fill"),
            punch: 1.4 + min(Double(streak) / 20, 1.2),
            newsworthiness: 0.8,
            isFloor: true
        )
    }

    private static func categoryCompositionCandidate(
        effectiveRows: [(category: Category, duration: TimeInterval)]
    ) -> DailyCardPatternSpotlight? {
        let rows = effectiveRows.filter { $0.duration >= 15 * 60 }
        let total = rows.reduce(TimeInterval(0)) { $0 + $1.duration }
        guard total >= 2 * 60 * 60, let top = rows.max(by: { $0.duration < $1.duration }) else { return nil }
        let topShare = top.duration / total

        if rows.count >= 3, topShare <= 0.55 {
            return DailyCardPatternSpotlight(
                kind: .categoryComposition,
                signal: nil,
                fact: DailyCardPatternFact(id: "composition-split", title: "構成", value: "\(rows.count)", suffix: "カテゴリ", systemImage: "square.grid.3x3.fill"),
                punch: 1.7,
                newsworthiness: 0.75,
                isFloor: true
            )
        }

        if topShare >= 0.75 {
            return DailyCardPatternSpotlight(
                kind: .categoryComposition,
                signal: nil,
                fact: DailyCardPatternFact(id: "composition-focus", title: "主成分", value: top.category.name, suffix: "\(Int((topShare * 100).rounded()))%", systemImage: "chart.pie.fill"),
                punch: 1.5,
                newsworthiness: 0.7,
                isFloor: true
            )
        }

        return nil
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

    private static func dayOffset(for date: Date, dayBoundary: DayBoundary) -> Int {
        Int(floor(date.timeIntervalSince(dayBoundary.dayStart) / (24 * 60 * 60)))
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
    case personalBest(category: Category, duration: TimeInterval, previousBest: TimeInterval)
    case moreThanUsual(category: Category, delta: TimeInterval)
    case lessThanUsual(category: Category, delta: TimeInterval)
}

struct DailyCardPatternFact: Hashable {
    let id: String
    let title: String
    let value: String
    let suffix: String?
    let systemImage: String
}

private struct DailyCardPatternSpotlight {
    let kind: DailyCardPatternDetector.DetectorKind
    let signal: DailyCardPatternSignal?
    let fact: DailyCardPatternFact
    let punch: Double
    let newsworthiness: Double
    let isFloor: Bool

    var selectionScore: Double {
        kindPriority + punch * newsworthiness
    }

    private var kindPriority: Double {
        switch kind {
        case .declaredIntent:
            return 30
        case .personalBest:
            return 20
        case .routineDeviation:
            return 12
        case .difference, .timeOfDay:
            return 8
        case .planMatch, .dayShape:
            return 4
        case .recordingHabit, .categoryComposition:
            return 1
        case .sensoryConversion, .mood, .friendOverlap:
            return 0
        }
    }
}

private func formatPatternDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(Int(seconds / 60), 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0, minutes > 0 {
        return "\(hours)時間\(minutes)分"
    } else if hours > 0 {
        return "\(hours)時間"
    } else {
        return "\(minutes)分"
    }
}

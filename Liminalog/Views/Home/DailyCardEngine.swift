import Foundation

struct DailyCardFact: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let suffix: String?
    let systemImage: String
}

struct DailyPersona {
    let title: String
    let message: String
    let symbol: String
    let facts: [DailyCardFact]

    static func make(
        summary: ScoreSummary,
        chapters: [Chapter],
        historyChapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        recordedDuration: TimeInterval,
        dayBoundary: DayBoundary
    ) -> DailyPersona {
        let analysis = DailyCardPatternDetector(
            chapters: chapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: dayBoundary
        )
        let facts = Self.makeFacts(
            analysis: analysis,
            recordedDuration: recordedDuration,
            chapterCount: chapters.count
        )

        guard !chapters.isEmpty else {
            return DailyPersona(
                title: "行方不明の1日",
                message: "記録が薄い日。たぶん何かはしてた、という人類共通の強い気持ちだけ残りました。",
                symbol: "moon.dust.fill",
                facts: facts
            )
        }

        if summary.plannedDuration > 0, summary.totalScore >= 88 {
            return DailyPersona(
                title: "有言実行の人",
                message: "未来の自分が置いた予定に、現在の自分がちゃんと出席しました。えらい、これは事件。",
                symbol: "checkmark.seal.fill",
                facts: facts
            )
        }

        if let signal = analysis.signal {
            let copy = signal.copy
            return DailyPersona(title: copy.title, message: copy.message, symbol: copy.symbol, facts: facts)
        }

        if let focus = analysis.focusCategory, analysis.shape == .sprinter {
            return DailyPersona(
                title: "\(analysis.chronoPrefix)スプリンター",
                message: "\(focus.category.name)に\(formatDailyCardDuration(focus.duration))。寄り道する脳をなんとか椅子に縛った日です。",
                symbol: "bolt.fill",
                facts: facts
            )
        }

        if analysis.shape == .zapping {
            return DailyPersona(
                title: "\(analysis.chronoPrefix)ザッピング",
                message: "\(analysis.meaningfulSwitchCount)回の切り替え。集中力は小分けパックでしたが、ちゃんと1日は組み上がっています。",
                symbol: "sparkles",
                facts: facts
            )
        }

        if summary.plannedDuration == 0 {
            return DailyPersona(
                title: "風まかせ",
                message: "予定なしで流れた日。地図はなかったけど、足跡だけは妙にリアルです。",
                symbol: "wind",
                facts: facts
            )
        }

        return DailyPersona(
            title: "\(analysis.chronoPrefix)マラソナー",
            message: "派手な爆発はなし。代わりに、地味な前進をちゃんと積んだ日です。地味、でも強い。",
            symbol: "figure.run",
            facts: facts
        )
    }

    private static func makeFacts(
        analysis: DailyCardPatternDetector,
        recordedDuration: TimeInterval,
        chapterCount: Int
    ) -> [DailyCardFact] {
        let hasMeaningfulRestExclusion = analysis.restWasExcluded && analysis.discretionaryDuration > 0
        let durationForPrimaryFact = hasMeaningfulRestExclusion ? analysis.discretionaryDuration : recordedDuration
        let durationTitle = hasMeaningfulRestExclusion ? "裁量時間" : "記録カバー"
        let switchCount = max(analysis.meaningfulSwitchCount, chapterCount == 0 ? 0 : 1)

        return [
            DailyCardFact(
                id: "duration",
                title: durationTitle,
                value: formatDailyCardDuration(durationForPrimaryFact),
                suffix: nil,
                systemImage: hasMeaningfulRestExclusion ? "clock.badge.checkmark" : "clock.fill"
            ),
            DailyCardFact(
                id: "switches",
                title: "切替",
                value: "\(switchCount)",
                suffix: "回",
                systemImage: "rectangle.2.swap"
            )
        ]
    }
}

private struct DailyCardPatternDetector {
    enum Shape {
        case sprinter
        case marathon
        case zapping
    }

    let focusCategory: (category: Category, duration: TimeInterval)?
    let shape: Shape
    let chronoPrefix: String
    let signal: DailyCardSignal?
    let discretionaryDuration: TimeInterval
    let restWasExcluded: Bool
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

        self.focusCategory = nonRestRows.first ?? (restCategoryIDs.isEmpty ? categoryRows.first : nil)
        self.shape = Self.shape(for: effectiveChapters, focusCategory: focusCategory, dayBoundary: dayBoundary)
        self.chronoPrefix = Self.chronoPrefix(for: effectiveChapters, dayBoundary: dayBoundary)
        self.signal = Self.signal(
            categoryRows: categoryRows,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary,
            excludedCategoryIDs: restCategoryIDs
        )
        self.discretionaryDuration = discretionaryDuration
        self.restWasExcluded = restWasExcluded
        self.meaningfulSwitchCount = Self.meaningfulSwitchCount(for: effectiveChapters, dayBoundary: dayBoundary)
    }

    private static func majorRestCategoryIDs(
        chapters: [Chapter],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> Set<UUID> {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historicalDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        let source = historicalDays >= 7 ? historical : chapters
        guard !source.isEmpty else { return [] }

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

        return Set(candidates.compactMap { id, candidate in
            let averageLongBlock = candidate.longestTotal / Double(max(candidate.blockCount, 1))
            let dayBase = max(historicalDays, 1)
            let frequency = Double(candidate.presenceDays.count) / Double(dayBase)
            if historicalDays >= 7 {
                return frequency >= 0.42 && averageLongBlock >= 4 * 60 * 60 ? id : nil
            } else {
                return candidate.totalLongBlocks >= 1 && averageLongBlock >= 6 * 60 * 60 ? id : nil
            }
        })
    }

    private static func shape(
        for chapters: [Chapter],
        focusCategory: (category: Category, duration: TimeInterval)?,
        dayBoundary: DayBoundary
    ) -> Shape {
        let durations = chapters.map { clippedDuration(for: $0, dayBoundary: dayBoundary) }
        let total = durations.reduce(0, +)
        let longest = max(durations.max() ?? 0, focusCategory?.duration ?? 0)
        let meaningfulSwitchCount = durations.filter { $0 >= 5 * 60 }.count
        let average = total / Double(max(meaningfulSwitchCount, 1))

        if meaningfulSwitchCount >= 8 || average <= 35 * 60 {
            return .zapping
        }
        if longest >= 150 * 60 && (total == 0 || longest / total >= 0.42) {
            return .sprinter
        }
        return .marathon
    }

    private static func chronoPrefix(for chapters: [Chapter], dayBoundary: DayBoundary) -> String {
        let weighted = chapters.reduce((total: TimeInterval(0), weighted: TimeInterval(0))) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            let duration = max(end.timeIntervalSince(start), 0)
            let midpoint = start.timeIntervalSince(dayBoundary.dayStart) + duration / 2
            return (partial.total + duration, partial.weighted + midpoint * duration)
        }
        guard weighted.total > 0 else { return "今日の" }
        let hour = weighted.weighted / weighted.total / 3600
        switch hour {
        case 0..<5: return "深夜の"
        case 5..<11: return "朝の"
        case 11..<16: return "昼の"
        default: return "夜の"
        }
    }

    private static func signal(
        categoryRows: [(category: Category, duration: TimeInterval)],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary,
        excludedCategoryIDs: Set<UUID>
    ) -> DailyCardSignal? {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historyDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        guard historyDays >= 7 else { return nil }

        let todayRows = categoryRows.filter { !excludedCategoryIDs.contains($0.category.id) }
        var best: (category: Category, duration: TimeInterval, z: Double, daysSinceLast: Int?)?

        for row in todayRows where !excludedCategoryIDs.contains(row.category.id) {
            var dailyTotals: [Date: TimeInterval] = [:]
            var lastSeen: Date?
            for chapter in historical where chapter.category?.id == row.category.id {
                let day = DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
                let duration = rawDuration(for: chapter, fallbackEnd: dayBoundary.dayStart)
                dailyTotals[day, default: 0] += duration
                lastSeen = max(lastSeen ?? day, day)
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
            let isSignal = abs(z) >= 1.5 || (daysSinceLast ?? 0) >= 10
            if isSignal, abs(z) > abs(best?.z ?? 0) || best == nil {
                best = (row.category, row.duration, z, daysSinceLast)
            }
        }

        guard let best else { return nil }
        if let days = best.daysSinceLast, days >= 10 {
            return .returnAfterGap(category: best.category, days: days)
        }
        if best.z > 0 {
            return .moreThanUsual(category: best.category)
        } else {
            return .lessThanUsual(category: best.category)
        }
    }

    private static func meaningfulSwitchCount(for chapters: [Chapter], dayBoundary: DayBoundary) -> Int {
        chapters.map { clippedDuration(for: $0, dayBoundary: dayBoundary) }
            .filter { $0 >= 5 * 60 }
            .count
    }

    private static func clippedDuration(for chapter: Chapter, dayBoundary: DayBoundary) -> TimeInterval {
        let start = max(chapter.startTime, dayBoundary.dayStart)
        let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
        return max(end.timeIntervalSince(start), 0)
    }

    private static func rawDuration(for chapter: Chapter, fallbackEnd: Date) -> TimeInterval {
        max(0, (chapter.endTime ?? fallbackEnd).timeIntervalSince(chapter.startTime))
    }
}

private enum DailyCardSignal {
    case returnAfterGap(category: Category, days: Int)
    case moreThanUsual(category: Category)
    case lessThanUsual(category: Category)

    var copy: DailyPersonaCopy {
        switch self {
        case let .returnAfterGap(category, days):
            return DailyPersonaCopy(
                title: "\(category.name)帰還",
                message: "\(days)日ぶりの\(category.name)。急に戻ってきたので、今日のカードがちょっとざわついています。",
                symbol: "arrow.uturn.left.circle.fill"
            )
        case let .moreThanUsual(category):
            return DailyPersonaCopy(
                title: "\(category.name)増量中",
                message: "\(category.name)がいつもより多め。今日の自分、そこだけ急にボリューム上げてきました。",
                symbol: "speaker.wave.3.fill"
            )
        case let .lessThanUsual(category):
            return DailyPersonaCopy(
                title: "\(category.name)控えめ",
                message: "\(category.name)はいつもより控えめ。空いた余白に、別の今日が入り込んでいます。",
                symbol: "leaf.fill"
            )
        }
    }
}

private struct DailyPersonaCopy {
    let title: String
    let message: String
    let symbol: String
}

private func formatDailyCardDuration(_ seconds: TimeInterval) -> String {
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

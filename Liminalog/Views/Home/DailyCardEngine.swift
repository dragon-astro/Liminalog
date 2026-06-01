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
        let messageSeed = Self.messageSeed(dayBoundary: dayBoundary, chapterCount: chapters.count)

        guard !chapters.isEmpty, recordedDuration >= 45 * 60 else {
            let copy = DailyCardCopyCatalog.missingDayCopy()
            return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if summary.plannedDuration > 0, summary.totalScore >= 88 {
            let copy = DailyCardCopyCatalog.planMatchedCopy()
            return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if analysis.isChargeDay {
            let copy = DailyCardCopyCatalog.chargeDayCopy()
            return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if let signal = analysis.signal {
            let copy = signal.copy
            return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if summary.plannedDuration == 0 {
            let copy = DailyCardCopyCatalog.noPlanCopy()
            return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        let copy = DailyCardCopyCatalog.shapeCopy(analysis: analysis)
        return DailyPersona(title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
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

        var facts = [
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
        if let signalFact = analysis.signal?.fact {
            facts.append(signalFact)
        }
        return Array(facts.prefix(3))
    }

    private static func messageSeed(dayBoundary: DayBoundary, chapterCount: Int) -> Int {
        let calendar = Calendar.japanese
        let components = calendar.dateComponents([.year, .month, .day], from: dayBoundary.dayStart)
        return (components.year ?? 0) * 372 + (components.month ?? 0) * 31 + (components.day ?? 0) + chapterCount
    }
}

private struct DailyCardPatternDetector {
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
    let signal: DailyCardSignal?
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
    ) -> DailyCardSignal? {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historyDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        guard historyDays >= 7 else { return nil }

        let todayRows = categoryRows.filter { !excludedCategoryIDs.contains($0.category.id) }
        var best: (signal: DailyCardSignal, score: Double)?

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
            let candidate: (DailyCardSignal, Double)?

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

private enum DailyCardSignal {
    case firstRecord(category: Category)
    case returnAfterGap(category: Category, days: Int)
    case moreThanUsual(category: Category, delta: TimeInterval)
    case lessThanUsual(category: Category, delta: TimeInterval)

    var copy: DailyPersonaCopy {
        switch self {
        case let .firstRecord(category):
            return DailyPersonaCopy(
                title: "\(category.name)、はじめました",
                messages: [
                    "\(category.name)、本日デビュー。新カテゴリ解禁で、世界がちょっと広がった日。",
                    "\(category.name)が初登場。今日のあなた、いつもの地図に新しいピンを刺しました。"
                ],
                symbol: "sparkles"
            )
        case let .returnAfterGap(category, days):
            return DailyPersonaCopy(
                title: "おかえり\(category.name)",
                messages: [
                    "\(category.name)が\(days)日ぶりに登場。おかえり。ちゃんと覚えてたよ。",
                    "\(days)日ぶりの\(category.name)。久々すぎて、今日のカードがちょっと二度見しています。"
                ],
                symbol: "hand.wave.fill"
            )
        case let .moreThanUsual(category, delta):
            return DailyPersonaCopy(
                title: "\(category.name)増量中",
                messages: [
                    "\(category.name)がいつもより\(formatDailyCardDuration(delta))多め。今日のあなた、そこだけ急にボリュームを上げてきました。",
                    "\(category.name)がいつもより\(formatDailyCardDuration(delta))増殖。何があった、とは聞かないでおきます。"
                ],
                symbol: "speaker.wave.3.fill"
            )
        case let .lessThanUsual(category, delta):
            return DailyPersonaCopy(
                title: "\(category.name)控えめ",
                messages: [
                    "\(category.name)はいつもより\(formatDailyCardDuration(delta))控えめ。空いた余白に、別の今日が入り込んでいます。",
                    "\(category.name)が今日は控えめ運転。いつもより\(formatDailyCardDuration(delta))、静かな存在感でした。"
                ],
                symbol: "leaf.fill"
            )
        }
    }

    var fact: DailyCardFact {
        switch self {
        case let .firstRecord(category):
            return DailyCardFact(id: "signal-first", title: "初記録", value: category.name, suffix: nil, systemImage: "sparkles")
        case let .returnAfterGap(_, days):
            return DailyCardFact(id: "signal-gap", title: "復帰", value: "\(days)", suffix: "日ぶり", systemImage: "hand.wave.fill")
        case let .moreThanUsual(_, delta):
            return DailyCardFact(id: "signal-more", title: "いつもより", value: formatDailyCardDuration(delta), suffix: "多め", systemImage: "arrow.up.right")
        case let .lessThanUsual(_, delta):
            return DailyCardFact(id: "signal-less", title: "いつもより", value: formatDailyCardDuration(delta), suffix: "控えめ", systemImage: "arrow.down.right")
        }
    }
}

private enum DailyCardCopyCatalog {
    static func missingDayCopy() -> DailyPersonaCopy {
        DailyPersonaCopy(
            title: "行方不明の1日",
            messages: [
                "記録、ほぼ白紙。何かはしてたはず、という人類共通の強い気持ちだけ残りました。",
                "今日の足取り、行方不明。ミステリーとして来世に持ち越しです。"
            ],
            symbol: "moon.dust.fill"
        )
    }

    static func planMatchedCopy() -> DailyPersonaCopy {
        DailyPersonaCopy(
            title: "有言実行の人",
            messages: [
                "未来の自分が置いた予定に、現在の自分が珍しく出席。えらい、これは事件。",
                "予定と実績がほぼ一致。今日のあなた、有言実行すぎて逆にちょっと怖い。"
            ],
            symbol: "checkmark.seal.fill"
        )
    }

    static func chargeDayCopy() -> DailyPersonaCopy {
        DailyPersonaCopy(
            title: "ガチ充電デー",
            messages: [
                "本日のミッションは回復。達成度100%、文句なし。",
                "人生で一番、充電した日。起きてた記憶は薄めでも、それも今日の仕事です。"
            ],
            symbol: "moon.zzz.fill"
        )
    }

    static func noPlanCopy() -> DailyPersonaCopy {
        DailyPersonaCopy(
            title: "風まかせ",
            messages: [
                "ノープランで流れた1日。地図はなかったけど、足跡だけは妙にリアル。",
                "計画ゼロ、自由は満タン。風まかせ無敵モード、本日も発動。"
            ],
            symbol: "wind"
        )
    }

    static func shapeCopy(analysis: DailyCardPatternDetector) -> DailyPersonaCopy {
        let focusName = analysis.focusCategory?.category.name ?? "今日"
        let focusDuration = formatDailyCardDuration(analysis.focusCategory?.duration ?? analysis.discretionaryDuration)
        let sprintName = analysis.longestMeaningfulCategory?.name ?? focusName
        let sprintDuration = formatDailyCardDuration(analysis.longestMeaningfulDuration)
        let switchCount = max(analysis.meaningfulSwitchCount, 1)

        switch analysis.shape {
        case .sprinter:
            return DailyPersonaCopy(
                title: title(chronotype: analysis.chronotype, shape: .sprinter),
                messages: [
                    "\(focusName)に\(focusDuration)。寄り道する脳を、なんとか椅子に縛りつけた日。",
                    "\(focusName)ひとすじ\(focusDuration)。今日のあなた、ちょっと尊敬するレベルの一点突破。",
                    "\(sprintDuration)ぶっ通しで\(sprintName)。集中力の在庫、たぶん今日で使い切りました。"
                ],
                symbol: "bolt.fill"
            )
        case .marathon:
            return DailyPersonaCopy(
                title: title(chronotype: analysis.chronotype, shape: .marathon),
                messages: [
                    "派手な爆発はなし。地味な前進をコツコツ積んだ、滋味深い1日。",
                    "淡々と\(switchCount)個こなして終了。バズらないけど、こういう日が一番強い。",
                    "大崩れせず完走。優勝ではない、でもちゃんと完走。"
                ],
                symbol: "figure.run"
            )
        case .zapping:
            return DailyPersonaCopy(
                title: title(chronotype: analysis.chronotype, shape: .zapping),
                messages: [
                    "\(switchCount)回の切り替え。集中力は小分けパック、でも1日はちゃんと組み上がった。",
                    "あっちこっち\(switchCount)回。落ち着け、と数時間前のあなたが言っています。",
                    "\(switchCount)回スイッチ。忙しそうで何より、忙しいとは言ってない。"
                ],
                symbol: "sparkles"
            )
        }
    }

    private static func title(
        chronotype: DailyCardPatternDetector.Chronotype,
        shape: DailyCardPatternDetector.Shape
    ) -> String {
        switch (chronotype, shape) {
        case (.morning, .sprinter): return "朝の短距離走者"
        case (.morning, .marathon): return "早起きコツコツ"
        case (.morning, .zapping): return "朝からせわしない"
        case (.daytime, .sprinter): return "昼の集中砲"
        case (.daytime, .marathon): return "平常運転マスター"
        case (.daytime, .zapping): return "マルチタスク昼"
        case (.evening, .sprinter): return "夜型スプリンター"
        case (.evening, .marathon): return "宵っ張りの持久型"
        case (.evening, .zapping): return "夜のザッピング"
        case (.midnight, .sprinter): return "丑三つの天才"
        case (.midnight, .marathon): return "不眠の修行僧"
        case (.midnight, .zapping): return "体内時計バグり気味"
        case (.unknown, .sprinter): return "今日の短距離走者"
        case (.unknown, .marathon): return "今日のマラソナー"
        case (.unknown, .zapping): return "今日のザッピング"
        }
    }
}

private struct DailyPersonaCopy {
    let title: String
    let messages: [String]
    let symbol: String

    func message(seed: Int) -> String {
        guard !messages.isEmpty else { return "" }
        return messages[abs(seed % messages.count)]
    }
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

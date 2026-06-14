import Foundation

struct DailyCardFact: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let suffix: String?
    let systemImage: String
}

struct DailyPersona {
    let kind: DailyCardPersonaKind
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
        dayBoundary: DayBoundary,
        avoidsYesterdaySpotlightKind: Bool = true
    ) -> DailyPersona {
        let avoidedSpotlightKinds = avoidsYesterdaySpotlightKind
            ? Self.yesterdaySpotlightKinds(historyChapters: historyChapters, dayBoundary: dayBoundary)
            : []
        let analysis = StatsEngine.dailyCardPattern(
            chapters: chapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: dayBoundary,
            avoidedSpotlightKinds: avoidedSpotlightKinds
        )
        let facts = Self.makeFacts(
            summary: summary,
            analysis: analysis,
            recordedDuration: recordedDuration,
            chapterCount: chapters.count
        )
        let messageSeed = Self.messageSeed(dayBoundary: dayBoundary, chapterCount: chapters.count)

        guard !chapters.isEmpty, recordedDuration >= 45 * 60 else {
            let copy = DailyCardCopyCatalog.missingDayCopy()
            return DailyPersona(kind: .missingDay, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if summary.plannedDuration > 0, summary.totalScore >= 88 {
            let copy = DailyCardCopyCatalog.planMatchedCopy()
            return DailyPersona(kind: .planMatched, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if analysis.isChargeDay {
            let copy = DailyCardCopyCatalog.chargeDayCopy()
            return DailyPersona(kind: .chargeDay, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if let signal = analysis.signal {
            let copy = signal.copy
            return DailyPersona(kind: .signal, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        if summary.plannedDuration == 0 {
            if let lifestyleCopy = DailyCardLifestyleCopy.shapeDraft(analysis: analysis) {
                let copy = DailyPersonaCopy(lifestyleCopy)
                return DailyPersona(kind: .noPlan, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
            }
            let copy = DailyCardCopyCatalog.noPlanCopy()
            return DailyPersona(kind: .noPlan, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
        }

        let copy = DailyCardCopyCatalog.shapeCopy(analysis: analysis)
        return DailyPersona(kind: .shape, title: copy.title, message: copy.message(seed: messageSeed), symbol: copy.symbol, facts: facts)
    }

    private static func makeFacts(
        summary: ScoreSummary,
        analysis: DailyCardPatternDetector,
        recordedDuration: TimeInterval,
        chapterCount: Int
    ) -> [DailyCardFact] {
        var facts = [
            primaryFact(analysis: analysis, recordedDuration: recordedDuration),
            secondaryFact(summary: summary, chapterCount: chapterCount)
        ]
        if let spotlightFact = analysis.spotlightFact {
            facts.append(DailyCardFact(spotlightFact))
        } else if let signalFact = analysis.signal?.fact {
            facts.append(signalFact)
        }
        return Array(facts.prefix(3))
    }

    private static func primaryFact(
        analysis: DailyCardPatternDetector,
        recordedDuration: TimeInterval
    ) -> DailyCardFact {
        if let focus = analysis.focusCategory {
            return DailyCardFact(
                id: "focus-category",
                title: "主役",
                value: focus.category.name,
                suffix: formatDailyCardDuration(focus.duration),
                systemImage: "star.fill"
            )
        }

        return DailyCardFact(
            id: "record-cover",
            title: "記録カバー",
            value: formatDailyCardDuration(recordedDuration),
            suffix: nil,
            systemImage: "clock.fill"
        )
    }

    private static func secondaryFact(summary: ScoreSummary, chapterCount: Int) -> DailyCardFact {
        guard summary.plannedDuration > 0 else {
            return DailyCardFact(
                id: "record-count",
                title: "記録数",
                value: "\(chapterCount)",
                suffix: "件",
                systemImage: "list.bullet.rectangle"
            )
        }

        let matchRate = min(max(summary.matchedDuration / summary.plannedDuration, 0), 1)
        return DailyCardFact(
            id: "match-rate",
            title: "一致率",
            value: "\(Int((matchRate * 100).rounded()))",
            suffix: "%",
            systemImage: "checkmark.seal.fill"
        )
    }

    private static func messageSeed(dayBoundary: DayBoundary, chapterCount: Int) -> Int {
        let calendar = Calendar.japanese
        let components = calendar.dateComponents([.year, .month, .day], from: dayBoundary.dayStart)
        return (components.year ?? 0) * 372 + (components.month ?? 0) * 31 + (components.day ?? 0) + chapterCount
    }

    private static func yesterdaySpotlightKinds(
        historyChapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> Set<String> {
        let yesterdayBoundary = DayBoundary(dayStart: dayBoundary.dayStart.addingTimeInterval(-24 * 60 * 60))
        let yesterdayChapters = historyChapters.filter {
            $0.startTime < yesterdayBoundary.dayEnd && ($0.endTime ?? yesterdayBoundary.dayEnd) > yesterdayBoundary.dayStart
        }
        guard !yesterdayChapters.isEmpty else { return [] }

        let previousHistory = historyChapters.filter { $0.startTime < yesterdayBoundary.dayStart }
        let categoryRows = Self.categoryRows(for: yesterdayChapters, dayBoundary: yesterdayBoundary)
        let recordedDuration = Self.recordedDuration(for: yesterdayChapters, dayBoundary: yesterdayBoundary)
        let detector = StatsEngine.dailyCardPattern(
            chapters: yesterdayChapters,
            historyChapters: previousHistory,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: yesterdayBoundary
        )
        guard let kind = detector.spotlightKind else { return [] }
        return [kind.rawValue]
    }

    private static func categoryRows(
        for chapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> [(category: Category, duration: TimeInterval)] {
        let grouped = Dictionary(grouping: chapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            return (category, max(end.timeIntervalSince(start), 0))
        }, by: { $0.0.id })

        return grouped.compactMap { _, values in
            guard let category = values.first?.0 else { return nil }
            return (category, values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.duration > $1.duration }
    }

    private static func recordedDuration(
        for chapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> TimeInterval {
        chapters.reduce(TimeInterval(0)) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            return partial + max(end.timeIntervalSince(start), 0)
        }
    }
}

private extension DailyCardPatternSignal {
    var copy: DailyPersonaCopy {
        switch self {
        case let .firstRecord(category):
            if let draft = DailyCardLifestyleCopy.firstRecordDraft(for: category) {
                return DailyPersonaCopy(draft)
            }
            return DailyPersonaCopy(
                title: "\(category.name)、はじめました",
                messages: [
                    "\(category.name)、本日デビュー。新カテゴリ解禁で、世界がちょっと広がった日。",
                    "\(category.name)が初登場。今日のあなた、いつもの地図に新しいピンを刺しました。"
                ],
                symbol: "sparkles"
            )
        case let .returnAfterGap(category, days):
            if let draft = DailyCardLifestyleCopy.returnAfterGapDraft(for: category, days: days) {
                return DailyPersonaCopy(draft)
            }
            return DailyPersonaCopy(
                title: "おかえり\(category.name)",
                messages: [
                    "\(category.name)が\(days)日ぶりに登場。おかえり。ちゃんと覚えてたよ。",
                    "\(days)日ぶりの\(category.name)。久々すぎて、今日のカードがちょっと二度見しています。"
                ],
                symbol: "hand.wave.fill"
            )
        case let .personalBest(category, duration, previousBest):
            let improvement = max(duration - previousBest, 0)
            if let draft = DailyCardLifestyleCopy.personalBestDraft(for: category, duration: duration, improvement: improvement) {
                return DailyPersonaCopy(draft)
            }
            return DailyPersonaCopy(
                title: "\(category.name)自己最長",
                messages: [
                    "\(category.name)が\(formatDailyCardDuration(duration))で自己最長。前回ベストより\(formatDailyCardDuration(improvement))、じわっと更新。",
                    "\(category.name)、今日は自己ベスト更新。\(formatDailyCardDuration(duration))ぶん居座った集中、なかなか強い。"
                ],
                symbol: "crown.fill"
            )
        case let .moreThanUsual(category, delta):
            switch category.dailyCardIntent {
            case .increase:
                return DailyPersonaCopy(
                    title: "\(category.name)、狙い通り増量",
                    messages: [
                        "増やしたい\(category.name)が、いつもより\(formatDailyCardDuration(delta))多め。珍しく宣言と現実が握手しました。",
                        "\(category.name)を増やす作戦、本日は成功寄り。いつもより\(formatDailyCardDuration(delta))、ちゃんと上乗せ。"
                    ],
                    symbol: "arrow.up.right.circle.fill"
                )
            case .decrease:
                return DailyPersonaCopy(
                    title: "\(category.name)増えちゃった",
                    messages: [
                        "減らしたい\(category.name)が、いつもより\(formatDailyCardDuration(delta))多め。まあ、そういう日もあります。",
                        "\(category.name)を減らしたい側なのに、今日は\(formatDailyCardDuration(delta))増量。現実、たまに強い。"
                    ],
                    symbol: "exclamationmark.triangle.fill"
                )
            case .neutral:
                break
            }
            return DailyPersonaCopy(
                title: "\(category.name)増量中",
                messages: [
                    "\(category.name)がいつもより\(formatDailyCardDuration(delta))多め。今日のあなた、そこだけ急にボリュームを上げてきました。",
                    "\(category.name)がいつもより\(formatDailyCardDuration(delta))増殖。何があった、とは聞かないでおきます。"
                ],
                symbol: "speaker.wave.3.fill"
            )
        case let .lessThanUsual(category, delta):
            switch category.dailyCardIntent {
            case .increase:
                return DailyPersonaCopy(
                    title: "\(category.name)足りなめ",
                    messages: [
                        "増やしたい\(category.name)は、いつもより\(formatDailyCardDuration(delta))控えめ。明日の自分にメモだけ渡しておきます。",
                        "\(category.name)を増やす予定のはずが、今日は少し静か。いつもより\(formatDailyCardDuration(delta))ぶん、余白が残りました。"
                    ],
                    symbol: "arrow.down.right.circle.fill"
                )
            case .decrease:
                return DailyPersonaCopy(
                    title: "\(category.name)、控えめ成功",
                    messages: [
                        "減らしたい\(category.name)が、いつもより\(formatDailyCardDuration(delta))控えめ。今日はちゃんと舵が効いています。",
                        "\(category.name)を減らす宣言、今日は現実側も協力的。いつもより\(formatDailyCardDuration(delta))静かでした。"
                    ],
                    symbol: "checkmark.circle.fill"
                )
            case .neutral:
                break
            }
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
        case let .personalBest(_, duration, _):
            return DailyCardFact(id: "signal-best", title: "自己最長", value: formatDailyCardDuration(duration), suffix: nil, systemImage: "crown.fill")
        case let .moreThanUsual(category, delta):
            return DailyCardFact(id: "signal-more", title: category.name, value: "+\(formatDailyCardDuration(delta))", suffix: "多め", systemImage: "arrow.up.right")
        case let .lessThanUsual(category, delta):
            return DailyCardFact(id: "signal-less", title: category.name, value: "-\(formatDailyCardDuration(delta))", suffix: "控えめ", systemImage: "arrow.down.right")
        }
    }
}

private extension DailyCardFact {
    init(_ patternFact: DailyCardPatternFact) {
        self.init(
            id: patternFact.id,
            title: patternFact.title,
            value: patternFact.value,
            suffix: patternFact.suffix,
            systemImage: patternFact.systemImage
        )
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
                "過去の自分が立てた予定どおりに、今日の自分がちゃんと動けた。えらい、これはもう事件です。",
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
                "ノープランで流れた1日。地図はなかったけど、ちゃんとどこかへは歩いてた。",
                "計画ゼロ、自由は満タン。風まかせ無敵モード、本日も発動。"
            ],
            symbol: "wind"
        )
    }

    static func shapeCopy(analysis: DailyCardPatternDetector) -> DailyPersonaCopy {
        if let lifestyleCopy = DailyCardLifestyleCopy.shapeDraft(analysis: analysis) {
            return DailyPersonaCopy(lifestyleCopy)
        }

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
                    "\(switchCount)回スイッチ。忙しそうに見えて、本当に忙しかったかはナゾ。"
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
        case (.evening, .zapping): return "目まぐるしい夜"
        case (.midnight, .sprinter): return "丑三つの天才"
        case (.midnight, .marathon): return "不眠の修行僧"
        case (.midnight, .zapping): return "体内時計バグり気味"
        case (.unknown, .sprinter): return "今日の短距離走者"
        case (.unknown, .marathon): return "今日のマラソナー"
        case (.unknown, .zapping): return "目まぐるしい1日"
        }
    }
}

private struct DailyPersonaCopy {
    let title: String
    let messages: [String]
    let symbol: String

    init(title: String, messages: [String], symbol: String) {
        self.title = title
        self.messages = messages
        self.symbol = symbol
    }

    init(_ draft: DailyCardLifestyleCopyDraft) {
        self.init(title: draft.title, messages: draft.messages, symbol: draft.symbol)
    }

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

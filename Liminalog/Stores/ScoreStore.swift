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
        dailyScoreDraftsIfAvailable(
            in: interval,
            modelContext: modelContext,
            now: now,
            calendar: calendar,
            includeCardMetrics: false
        )?.map(\.summary)
    }

    private static func dailyScoreDraftsIfAvailable(
        in interval: DateInterval,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese,
        includeCardMetrics: Bool
    ) -> [DailyScoreSnapshotDraft]? {
        let dates = days(in: interval, calendar: calendar)
        guard !dates.isEmpty else { return [] }

        guard let plans = plannedBlocksIfAvailable(in: interval, modelContext: modelContext),
              let chapters = chaptersIfAvailable(in: interval, modelContext: modelContext, now: now, calendar: calendar)
        else {
            return nil
        }
        let dailyCardsByIdentifier: [String: DailyCardSnapshot]
        if includeCardMetrics {
            let dailyCards = dailyCardSnapshots(in: interval, modelContext: modelContext) ?? []
            dailyCardsByIdentifier = Dictionary(grouping: dailyCards, by: \.dayIdentifier)
                .compactMapValues { snapshots in
                    snapshots.sorted { $0.updatedAt > $1.updatedAt }.first
                }
        } else {
            dailyCardsByIdentifier = [:]
        }

        return dates.map { date in
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            let summary = ScoreCalculator.summary(
                date: date,
                plans: dayPlans,
                chapters: dayChapters,
                calendar: calendar,
                now: now
            )
            let completedChapters = dayChapters.filter { $0.endTime != nil }
            let categoryIDs = Set(dayChapters.compactMap { $0.category?.id })
                .sorted { $0.uuidString < $1.uuidString }
            let dayIdentifier = DailyCardSnapshot.dayIdentifier(for: boundary.dayStart, calendar: calendar)
            return DailyScoreSnapshotDraft(
                dayStart: boundary.dayStart,
                dayIdentifier: dayIdentifier,
                summary: summary,
                hasRecord: !dayChapters.isEmpty,
                earlyRecordDay: completedChapters.contains { chapter in
                    let hour = calendar.component(.hour, from: chapter.startTime)
                    return (5..<9).contains(hour)
                },
                lateNightRecordDay: completedChapters.contains { chapter in
                    let hour = calendar.component(.hour, from: chapter.startTime)
                    return hour >= 23 || hour < 3
                },
                categoryIDs: categoryIDs,
                cardMetrics: includeCardMetrics
                    ? DailyScoreCardMetrics(snapshot: dailyCardsByIdentifier[dayIdentifier])
                    : DailyScoreCardMetrics()
            )
        }
    }

    /// 累積スコア。昨日以前は日別の確定台帳、今日はライブ計算を足す。
    static func cumulativeScore(
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .japanese
    ) -> Int {
        let todayStart = DayBoundary.dayStart(for: now, calendar: calendar)
        let settings = SeedCoordinator.ensureUserSettingsIfAvailable(in: modelContext, now: now)
        reconcileFinalizedDailyScores(
            before: todayStart,
            settings: settings,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )

        let finalizedScore = settings?.isFinalizedScoreLedgerInitialized == true
            ? max(settings?.finalizedCumulativeScore ?? 0, 0)
            : finalizedCumulativeScore(
            before: todayStart,
            modelContext: modelContext
        )
        let todayScore = Int(summary(on: now, modelContext: modelContext, now: now, calendar: calendar).totalScore.rounded())
        return finalizedScore + todayScore
    }

    private static func earliestScoringStart(
        modelContext: ModelContext,
        calendar: Calendar = .japanese
    ) -> Date? {
        var descriptor = FetchDescriptor<PlanBlock>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        descriptor.fetchLimit = 1
        do {
            guard let firstPlan = try modelContext.fetch(descriptor).first else {
                return nil
            }
            return DayBoundary.dayStart(for: firstPlan.startTime, calendar: calendar)
        } catch {
            NSLog("Liminalog: failed to fetch earliest score plan: \(String(describing: error))")
            return nil
        }
    }

    private static func reconcileFinalizedDailyScores(
        before end: Date,
        settings: UserSettings?,
        modelContext: ModelContext,
        now: Date,
        calendar: Calendar = .japanese
    ) {
        guard let settings else { return }

        if !settings.isFinalizedScoreLedgerInitialized {
            initializeFinalizedScoreLedger(
                before: end,
                settings: settings,
                modelContext: modelContext,
                now: now,
                calendar: calendar
            )
            return
        }

        guard let start = nextReconciliationStart(
            settings: settings,
            end: end,
            modelContext: modelContext,
            calendar: calendar
        ), start < end else { return }

        let interval = DateInterval(start: start, end: end)
        guard let existingSnapshots = dailyScoreSnapshots(in: interval, modelContext: modelContext),
              let drafts = dailyScoreDraftsIfAvailable(
                in: interval,
                modelContext: modelContext,
                now: now,
                calendar: calendar,
                includeCardMetrics: true
              )
        else { return }

        var didChange = removeDuplicateDailyScoreSnapshots(existingSnapshots, modelContext: modelContext)
        let existingDayIdentifiers = Set(existingSnapshots.map(\.dayIdentifier))
        var addedScore = 0
        for draft in drafts {
            let dayStart = draft.dayStart
            guard dayStart < end else { continue }
            guard draft.shouldPersist else { continue }
            guard !existingDayIdentifiers.contains(draft.dayIdentifier) else { continue }

            let snapshot = DailyScoreSnapshot()
            snapshot.createdAt = now
            apply(draft, to: snapshot, now: now)
            modelContext.insert(snapshot)
            addedScore += max(snapshot.score, 0)
            didChange = true
        }

        settings.finalizedCumulativeScore += addedScore
        settings.finalizedScoreReconciledThroughDayStart = previousDayStart(before: end, calendar: calendar)
        settings.updatedAt = now
        didChange = true

        if didChange {
            saveChanges("daily score snapshot reconciliation", modelContext: modelContext)
        }
    }

    private static func initializeFinalizedScoreLedger(
        before end: Date,
        settings: UserSettings,
        modelContext: ModelContext,
        now: Date,
        calendar: Calendar = .japanese
    ) {
        let existingSnapshots = dailyScoreSnapshots(before: end, modelContext: modelContext) ?? []
        var didChange = removeDuplicateDailyScoreSnapshots(existingSnapshots, modelContext: modelContext)
        var existingDayIdentifiers = Set<String>()
        var total = 0
        for snapshot in existingSnapshots {
            guard existingDayIdentifiers.insert(snapshot.dayIdentifier).inserted else { continue }
            total += max(snapshot.score, 0)
        }

        if let start = earliestScoringStart(modelContext: modelContext, calendar: calendar), start < end {
            let interval = DateInterval(start: start, end: end)
            guard let drafts = dailyScoreDraftsIfAvailable(
                in: interval,
                modelContext: modelContext,
                now: now,
                calendar: calendar,
                includeCardMetrics: true
            ) else { return }
            let existingByDayIdentifier = Dictionary(grouping: existingSnapshots, by: \.dayIdentifier)
                .compactMapValues { snapshots in
                    snapshots.sorted { $0.updatedAt > $1.updatedAt }.first
                }

            for draft in drafts {
                let dayStart = draft.dayStart
                guard dayStart < end else { continue }
                guard draft.shouldPersist else { continue }
                if let existing = existingByDayIdentifier[draft.dayIdentifier] {
                    if apply(draft, to: existing, now: now) {
                        didChange = true
                    }
                    _ = existingDayIdentifiers.insert(draft.dayIdentifier)
                    continue
                }
                guard existingDayIdentifiers.insert(draft.dayIdentifier).inserted else { continue }

                let snapshot = DailyScoreSnapshot()
                snapshot.createdAt = now
                apply(draft, to: snapshot, now: now)
                modelContext.insert(snapshot)
                total += max(snapshot.score, 0)
                didChange = true
            }
        }

        settings.finalizedCumulativeScore = total
        settings.isFinalizedScoreLedgerInitialized = true
        settings.finalizedScoreReconciledThroughDayStart = previousDayStart(before: end, calendar: calendar)
        settings.updatedAt = now
        didChange = true

        if didChange {
            saveChanges("daily score ledger initialization", modelContext: modelContext)
        }
    }

    private static func nextReconciliationStart(
        settings: UserSettings,
        end: Date,
        modelContext: ModelContext,
        calendar: Calendar = .japanese
    ) -> Date? {
        if let reconciledThrough = settings.finalizedScoreReconciledThroughDayStart {
            return calendar.date(byAdding: .day, value: 1, to: reconciledThrough)
        }

        if let latestSnapshot = latestDailyScoreSnapshot(before: end, modelContext: modelContext) {
            return calendar.date(byAdding: .day, value: 1, to: latestSnapshot.dayStart)
        }

        return earliestScoringStart(modelContext: modelContext, calendar: calendar)
    }

    private static func previousDayStart(before end: Date, calendar: Calendar = .japanese) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: DayBoundary.dayStart(for: end, calendar: calendar))
    }

    private static func finalizedCumulativeScore(
        before end: Date,
        modelContext: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let snapshots = try modelContext.fetch(descriptor)
            var seenDayIdentifiers = Set<String>()
            return snapshots.reduce(0) { total, snapshot in
                guard seenDayIdentifiers.insert(snapshot.dayIdentifier).inserted else {
                    return total
                }
                return total + max(snapshot.score, 0)
            }
        } catch {
            NSLog("Liminalog: failed to fetch finalized score snapshots: \(String(describing: error))")
            return 0
        }
    }

    private static func dailyScoreSnapshots(
        in interval: DateInterval,
        modelContext: ModelContext
    ) -> [DailyScoreSnapshot]? {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily score snapshots: \(String(describing: error))")
            return nil
        }
    }

    private static func dailyScoreSnapshots(
        before end: Date,
        modelContext: ModelContext
    ) -> [DailyScoreSnapshot]? {
        let descriptor = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch finalized daily score snapshots: \(String(describing: error))")
            return nil
        }
    }

    private static func latestDailyScoreSnapshot(
        before end: Date,
        modelContext: ModelContext
    ) -> DailyScoreSnapshot? {
        var descriptor = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            NSLog("Liminalog: failed to fetch latest daily score snapshot: \(String(describing: error))")
            return nil
        }
    }

    private static func dailyCardSnapshots(
        in interval: DateInterval,
        modelContext: ModelContext
    ) -> [DailyCardSnapshot]? {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card snapshots for score ledger: \(String(describing: error))")
            return nil
        }
    }

    private static func removeDuplicateDailyScoreSnapshots(
        _ snapshots: [DailyScoreSnapshot],
        modelContext: ModelContext
    ) -> Bool {
        var seenDayIdentifiers = Set<String>()
        var didChange = false
        for snapshot in snapshots {
            guard seenDayIdentifiers.insert(snapshot.dayIdentifier).inserted else {
                modelContext.delete(snapshot)
                didChange = true
                continue
            }
        }
        return didChange
    }

    @discardableResult
    private static func apply(_ draft: DailyScoreSnapshotDraft, to snapshot: DailyScoreSnapshot, now: Date) -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<DailyScoreSnapshot, Value>, to value: Value) {
            if snapshot[keyPath: keyPath] != value {
                snapshot[keyPath: keyPath] = value
                didChange = true
            }
        }

        update(\.dayStart, to: draft.dayStart)
        update(\.dayIdentifier, to: draft.dayIdentifier)
        update(\.score, to: Int(draft.summary.totalScore.rounded()))
        update(\.plannedDuration, to: draft.summary.plannedDuration)
        update(\.recordedDuration, to: draft.summary.recordedDuration)
        update(\.hasRecord, to: draft.hasRecord)
        update(\.earlyRecordDay, to: draft.earlyRecordDay)
        update(\.lateNightRecordDay, to: draft.lateNightRecordDay)
        update(\.categoryIDs, to: draft.categoryIDs)
        update(\.planMatchedDay, to: draft.cardMetrics.planMatchedDay)
        update(\.chargeDay, to: draft.cardMetrics.chargeDay)
        update(\.morningPersonaDay, to: draft.cardMetrics.morningPersonaDay)
        update(\.nightPersonaDay, to: draft.cardMetrics.nightPersonaDay)
        update(\.recordingHabitDay, to: draft.cardMetrics.recordingHabitDay)
        update(\.personalBestDay, to: draft.cardMetrics.personalBestDay)
        update(\.returnAfterGapDay, to: draft.cardMetrics.returnAfterGapDay)
        update(\.firstRecordDay, to: draft.cardMetrics.firstRecordDay)
        update(\.balancedDay, to: draft.cardMetrics.balancedDay)
        update(\.focusedDay, to: draft.cardMetrics.focusedDay)
        update(\.changeSignalDay, to: draft.cardMetrics.changeSignalDay)

        if didChange {
            snapshot.updatedAt = now
        }
        return didChange
    }

    private static func saveChanges(_ action: String, modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
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

    private struct DailyScoreSnapshotDraft {
        let dayStart: Date
        let dayIdentifier: String
        let summary: ScoreSummary
        let hasRecord: Bool
        let earlyRecordDay: Bool
        let lateNightRecordDay: Bool
        let categoryIDs: [UUID]
        let cardMetrics: DailyScoreCardMetrics

        var shouldPersist: Bool {
            summary.plannedDuration > 0
                || summary.recordedDuration > 0
                || summary.totalScore > 0
                || hasRecord
                || cardMetrics.hasAnyValue
        }
    }

    private struct DailyScoreCardMetrics {
        var planMatchedDay = false
        var chargeDay = false
        var morningPersonaDay = false
        var nightPersonaDay = false
        var recordingHabitDay = false
        var personalBestDay = false
        var returnAfterGapDay = false
        var firstRecordDay = false
        var balancedDay = false
        var focusedDay = false
        var changeSignalDay = false

        var hasAnyValue: Bool {
            planMatchedDay || chargeDay || morningPersonaDay || nightPersonaDay
                || recordingHabitDay || personalBestDay || returnAfterGapDay || firstRecordDay
                || balancedDay || focusedDay || changeSignalDay
        }

        init() {}

        init(snapshot: DailyCardSnapshot?) {
            guard let snapshot else {
                return
            }

            let factIDs = Set(snapshot.facts.map(\.id))

            planMatchedDay = snapshot.personaKind == .planMatched
            chargeDay = snapshot.personaKind == .chargeDay
            morningPersonaDay = DailyCardLifestyleCopy.morningPersonaTitles.contains(snapshot.title)
            nightPersonaDay = DailyCardLifestyleCopy.nightPersonaTitles.contains(snapshot.title)
            recordingHabitDay = factIDs.contains("habit-streak")
            personalBestDay = factIDs.contains("signal-best")
            returnAfterGapDay = factIDs.contains("signal-gap")
            firstRecordDay = factIDs.contains("signal-first")
            balancedDay = factIDs.contains("composition-split")
            focusedDay = factIDs.contains("composition-focus")
            changeSignalDay = factIDs.contains("signal-more") || factIDs.contains("signal-less")
        }
    }
}

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
        loadIfAvailable(modelContext: modelContext, now: now, calendar: calendar) ?? empty
    }

    @MainActor
    static func loadIfAvailable(modelContext: ModelContext, now: Date, calendar: Calendar = .japanese) -> ProfilePerformanceSnapshot? {
        let todayStart = DayBoundary.dayStart(for: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let interval = DateInterval(start: start, end: end)

        guard let summaries = ScoreSnapshotLoader.summariesIfAvailable(
            in: interval,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        ) else {
            NSLog("Liminalog: failed to load profile score summaries")
            return nil
        }

        var streak = 0
        for summary in summaries.reversed() {
            guard summary.plannedDuration > 0, summary.totalScore >= StreakRules.passingScore else { break }
            streak += 1
        }

        let totalEarnedScore = ScoreSnapshotLoader.cumulativeScore(
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        guard let finalizedSnapshots = finalizedDailyScoreSnapshots(before: todayStart, modelContext: modelContext),
              let todayStats = todayProfileStats(modelContext: modelContext, now: now, calendar: calendar)
        else { return nil }

        let recordedDayCount = finalizedSnapshots.filter(\.hasRecord).count + (todayStats.hasRecord ? 1 : 0)
        let totalRecordedDuration = finalizedSnapshots.reduce(todayStats.recordedDuration) { total, snapshot in
            total + max(0, snapshot.recordedDuration)
        }
        let earlyRecordDayCount = finalizedSnapshots.filter(\.earlyRecordDay).count + (todayStats.earlyRecordDay ? 1 : 0)
        let lateNightRecordDayCount = finalizedSnapshots.filter(\.lateNightRecordDay).count + (todayStats.lateNightRecordDay ? 1 : 0)
        var distinctCategoryIDs = Set(finalizedSnapshots.flatMap(\.categoryIDs))
        distinctCategoryIDs.formUnion(todayStats.categoryIDs)
        let dailyCardMetrics = DailyCardUnlockMetrics(snapshots: finalizedSnapshots, today: todayStats.cardMetrics)
        let unlockMetrics = UnlockMetrics(
            cumulativeScore: totalEarnedScore,
            recordedDays: recordedDayCount,
            recordedHours: max(0, Int(totalRecordedDuration / 3600)),
            streakDays: streak,
            earlyRecordDays: earlyRecordDayCount,
            lateNightRecordDays: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryIDs.count,
            planMatchedDays: dailyCardMetrics.planMatchedDays,
            chargeDays: dailyCardMetrics.chargeDays,
            morningPersonaDays: dailyCardMetrics.morningPersonaDays,
            nightPersonaDays: dailyCardMetrics.nightPersonaDays,
            recordingHabitDays: dailyCardMetrics.recordingHabitDays,
            personalBestDays: dailyCardMetrics.personalBestDays,
            returnAfterGapDays: dailyCardMetrics.returnAfterGapDays,
            firstRecordDays: dailyCardMetrics.firstRecordDays,
            balancedDays: dailyCardMetrics.balancedDays,
            focusedDays: dailyCardMetrics.focusedDays,
            changeSignalDays: dailyCardMetrics.changeSignalDays
        )

        return ProfilePerformanceSnapshot(
            totalEarnedScore: totalEarnedScore,
            streakCount: streak,
            recordedDayCount: recordedDayCount,
            totalRecordedDuration: totalRecordedDuration,
            earlyRecordDayCount: earlyRecordDayCount,
            lateNightRecordDayCount: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryIDs.count,
            unlockMetrics: unlockMetrics
        )
    }

    @MainActor
    private static func finalizedDailyScoreSnapshots(
        before end: Date,
        modelContext: ModelContext
    ) -> [DailyScoreSnapshot]? {
        let descriptor = FetchDescriptor<DailyScoreSnapshot>(
            predicate: #Predicate { $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            var seenDayIdentifiers = Set<String>()
            return try modelContext.fetch(descriptor).filter { snapshot in
                seenDayIdentifiers.insert(snapshot.dayIdentifier).inserted
            }
        } catch {
            NSLog("Liminalog: failed to fetch profile daily score snapshots: \(String(describing: error))")
            return nil
        }
    }

    @MainActor
    private static func todayProfileStats(
        modelContext: ModelContext,
        now: Date,
        calendar: Calendar
    ) -> TodayProfileStats? {
        let boundary = DayBoundary(date: now, calendar: calendar)
        let start = boundary.dayStart
        let end = boundary.dayEnd
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let chapters: [Chapter]
        do {
            chapters = try modelContext.fetch(descriptor)
                .filter { ($0.endTime ?? now) > start }
        } catch {
            NSLog("Liminalog: failed to fetch today's profile chapters: \(String(describing: error))")
            return nil
        }

        let completedChapters = chapters.filter { $0.endTime != nil }
        let dayIdentifier = DailyCardSnapshot.dayIdentifier(for: start, calendar: calendar)
        return TodayProfileStats(
            hasRecord: !chapters.isEmpty,
            recordedDuration: chapters.reduce(0) { $0 + max(0, ($1.endTime ?? now).timeIntervalSince($1.startTime)) },
            earlyRecordDay: completedChapters.contains { chapter in
                let hour = calendar.component(.hour, from: chapter.startTime)
                return (5..<9).contains(hour)
            },
            lateNightRecordDay: completedChapters.contains { chapter in
                let hour = calendar.component(.hour, from: chapter.startTime)
                return hour >= 23 || hour < 3
            },
            categoryIDs: Set(chapters.compactMap { $0.category?.id }),
            cardMetrics: latestDailyCardMetrics(dayIdentifier: dayIdentifier, modelContext: modelContext)
        )
    }

    @MainActor
    private static func latestDailyCardMetrics(
        dayIdentifier: String,
        modelContext: ModelContext
    ) -> DailyCardUnlockMetrics {
        var descriptor = FetchDescriptor<DailyCardSnapshot>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return DailyCardUnlockMetrics(snapshot: try modelContext.fetch(descriptor).first)
        } catch {
            NSLog("Liminalog: failed to fetch today's daily card snapshot for profile unlocks: \(String(describing: error))")
            return DailyCardUnlockMetrics()
        }
    }
}

private struct DailyCardUnlockMetrics {
    var planMatchedDays = 0
    var chargeDays = 0
    var morningPersonaDays = 0
    var nightPersonaDays = 0
    var recordingHabitDays = 0
    var personalBestDays = 0
    var returnAfterGapDays = 0
    var firstRecordDays = 0
    var balancedDays = 0
    var focusedDays = 0
    var changeSignalDays = 0

    init() {}

    init(snapshot: DailyCardSnapshot?) {
        guard let snapshot else {
            return
        }
        let morningTitles: Set<String> = [
            "朝の短距離走者",
            "早起きコツコツ",
            "朝からせわしない"
        ]
        let nightTitles: Set<String> = [
            "夜型スプリンター",
            "宵っ張りの持久型",
            "目まぐるしい夜",
            "丑三つの天才",
            "不眠の修行僧",
            "体内時計バグり気味"
        ]

        let factIDs = snapshot.factIDs
        planMatchedDays = snapshot.personaKind == .planMatched ? 1 : 0
        chargeDays = snapshot.personaKind == .chargeDay ? 1 : 0
        morningPersonaDays = morningTitles.contains(snapshot.title) ? 1 : 0
        nightPersonaDays = nightTitles.contains(snapshot.title) ? 1 : 0
        recordingHabitDays = factIDs.contains("habit-streak") ? 1 : 0
        personalBestDays = factIDs.contains("signal-best") ? 1 : 0
        returnAfterGapDays = factIDs.contains("signal-gap") ? 1 : 0
        firstRecordDays = factIDs.contains("signal-first") ? 1 : 0
        balancedDays = factIDs.contains("composition-split") ? 1 : 0
        focusedDays = factIDs.contains("composition-focus") ? 1 : 0
        changeSignalDays = factIDs.contains("signal-more") || factIDs.contains("signal-less") ? 1 : 0
    }

    init(snapshots: [DailyScoreSnapshot], today: DailyCardUnlockMetrics) {
        planMatchedDays = snapshots.filter(\.planMatchedDay).count + today.planMatchedDays
        chargeDays = snapshots.filter(\.chargeDay).count + today.chargeDays
        morningPersonaDays = snapshots.filter(\.morningPersonaDay).count + today.morningPersonaDays
        nightPersonaDays = snapshots.filter(\.nightPersonaDay).count + today.nightPersonaDays
        recordingHabitDays = snapshots.filter(\.recordingHabitDay).count + today.recordingHabitDays
        personalBestDays = snapshots.filter(\.personalBestDay).count + today.personalBestDays
        returnAfterGapDays = snapshots.filter(\.returnAfterGapDay).count + today.returnAfterGapDays
        firstRecordDays = snapshots.filter(\.firstRecordDay).count + today.firstRecordDays
        balancedDays = snapshots.filter(\.balancedDay).count + today.balancedDays
        focusedDays = snapshots.filter(\.focusedDay).count + today.focusedDays
        changeSignalDays = snapshots.filter(\.changeSignalDay).count + today.changeSignalDays
    }
}

private struct TodayProfileStats {
    let hasRecord: Bool
    let recordedDuration: TimeInterval
    let earlyRecordDay: Bool
    let lateNightRecordDay: Bool
    let categoryIDs: Set<UUID>
    let cardMetrics: DailyCardUnlockMetrics
}

private extension DailyCardSnapshot {
    var factIDs: Set<String> {
        Set(facts.map(\.id))
    }
}

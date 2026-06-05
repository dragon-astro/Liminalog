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

        let allChaptersDescriptor = FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.startTime)])
        let allChapters: [Chapter]
        do {
            allChapters = try modelContext.fetch(allChaptersDescriptor)
        } catch {
            NSLog("Liminalog: failed to fetch profile chapters: \(String(describing: error))")
            return nil
        }
        guard let summaries = ScoreSnapshotLoader.summariesIfAvailable(
            in: interval,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        ) else {
            NSLog("Liminalog: failed to load profile score summaries")
            return nil
        }

        let dailySnapshotsDescriptor = FetchDescriptor<DailyCardSnapshot>(
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let dailySnapshots: [DailyCardSnapshot]
        do {
            dailySnapshots = try modelContext.fetch(dailySnapshotsDescriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card snapshots for profile unlocks: \(String(describing: error))")
            return nil
        }

        var streak = 0
        for summary in summaries.reversed() {
            guard summary.plannedDuration > 0, summary.totalScore >= StreakRules.passingScore else { break }
            streak += 1
        }

        let totalEarnedScore = summaries.reduce(0) { $0 + Int($1.totalScore.rounded()) }
        let recordedDayStarts = Set(allChapters.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) })
        let completedChapters = allChapters.filter { $0.endTime != nil }
        let earlyRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard (5..<9).contains(hour) else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let lateNightRecordDayCount = Set(completedChapters.compactMap { chapter -> Date? in
            let hour = calendar.component(.hour, from: chapter.startTime)
            guard hour >= 23 || hour < 3 else { return nil }
            return DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
        }).count
        let totalRecordedDuration = allChapters.reduce(0) { $0 + max(0, ($1.endTime ?? now).timeIntervalSince($1.startTime)) }
        let distinctCategoryCount = Set(allChapters.compactMap { $0.category?.id }).count
        let dailyCardMetrics = DailyCardUnlockMetrics(snapshots: dailySnapshots)
        let unlockMetrics = UnlockMetrics(
            cumulativeScore: totalEarnedScore,
            recordedDays: recordedDayStarts.count,
            recordedHours: max(0, Int(totalRecordedDuration / 3600)),
            streakDays: streak,
            earlyRecordDays: earlyRecordDayCount,
            lateNightRecordDays: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount,
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
            recordedDayCount: recordedDayStarts.count,
            totalRecordedDuration: totalRecordedDuration,
            earlyRecordDayCount: earlyRecordDayCount,
            lateNightRecordDayCount: lateNightRecordDayCount,
            distinctCategoryCount: distinctCategoryCount,
            unlockMetrics: unlockMetrics
        )
    }
}

private struct DailyCardUnlockMetrics {
    let planMatchedDays: Int
    let chargeDays: Int
    let morningPersonaDays: Int
    let nightPersonaDays: Int
    let recordingHabitDays: Int
    let personalBestDays: Int
    let returnAfterGapDays: Int
    let firstRecordDays: Int
    let balancedDays: Int
    let focusedDays: Int
    let changeSignalDays: Int

    init(snapshots: [DailyCardSnapshot]) {
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

        planMatchedDays = snapshots.filter { $0.personaKind == .planMatched }.count
        chargeDays = snapshots.filter { $0.personaKind == .chargeDay }.count
        morningPersonaDays = snapshots.filter { morningTitles.contains($0.title) }.count
        nightPersonaDays = snapshots.filter { nightTitles.contains($0.title) }.count
        recordingHabitDays = snapshots.filter { $0.factIDs.contains("habit-streak") }.count
        personalBestDays = snapshots.filter { $0.factIDs.contains("signal-best") }.count
        returnAfterGapDays = snapshots.filter { $0.factIDs.contains("signal-gap") }.count
        firstRecordDays = snapshots.filter { $0.factIDs.contains("signal-first") }.count
        balancedDays = snapshots.filter { $0.factIDs.contains("composition-split") }.count
        focusedDays = snapshots.filter { $0.factIDs.contains("composition-focus") }.count
        changeSignalDays = snapshots.filter { snapshot in
            let ids = snapshot.factIDs
            return ids.contains("signal-more") || ids.contains("signal-less")
        }.count
    }
}

private extension DailyCardSnapshot {
    var factIDs: Set<String> {
        Set(facts.map(\.id))
    }
}

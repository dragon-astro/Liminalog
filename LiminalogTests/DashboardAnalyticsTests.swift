import Foundation
import Testing
@testable import Liminalog

struct DashboardAnalyticsTests {
    @Test
    func timeOfDaySummarySplitsChaptersAcrossMorningAfternoonAndNight() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let intervalEnd = try #require(calendar.date(byAdding: .day, value: 2, to: day))
        let category = Category(name: "記録", colorHex: "#2F80ED")
        let early = chapter(
            category: category,
            start: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 4))),
            end: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7)))
        )
        let afternoon = chapter(
            category: category,
            start: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 13))),
            end: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 14)))
        )
        let overnight = chapter(
            category: category,
            start: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 22))),
            end: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 1)))
        )

        let summary = DashboardTimeOfDaySummary.make(
            chapters: [afternoon, overnight, early],
            interval: DateInterval(start: day, end: intervalEnd),
            calendar: calendar
        )

        #expect(duration(for: .morning, in: summary) == 2 * 60 * 60)
        #expect(duration(for: .afternoon, in: summary) == 60 * 60)
        #expect(duration(for: .night, in: summary) == 4 * 60 * 60)
        #expect(summary.totalDuration == 7 * 60 * 60)
        #expect(summary.dominantSegment == .night)
        #expect(abs((row(for: .night, in: summary)?.ratio ?? 0) - (4.0 / 7.0)) < 0.0001)
    }

    @Test
    func timeOfDaySummaryUsesNowForActiveChaptersAndClipsToInterval() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let intervalEnd = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let category = Category(name: "記録", colorHex: "#2F80ED")
        let active = Chapter(
            category: category,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10)))
        )
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 13)))

        let summary = DashboardTimeOfDaySummary.make(
            chapters: [active],
            interval: DateInterval(start: day, end: intervalEnd),
            calendar: calendar,
            now: now
        )

        #expect(duration(for: .morning, in: summary) == 2 * 60 * 60)
        #expect(duration(for: .afternoon, in: summary) == 60 * 60)
        #expect(duration(for: .night, in: summary) == 0)
    }

    @Test
    func periodDeltaComparesAverageScoredDaysAndDurations() throws {
        let calendar = Calendar.liminalogTest
        let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let current = [
            scoreSummary(date: base, totalScore: 80, plannedHours: 2, recordedHours: 3, matchedHours: 2),
            scoreSummary(
                date: try #require(calendar.date(byAdding: .day, value: 1, to: base)),
                totalScore: 0,
                plannedHours: 0,
                recordedHours: 1,
                matchedHours: 0
            )
        ]
        let previous = [
            scoreSummary(
                date: try #require(calendar.date(byAdding: .day, value: -7, to: base)),
                totalScore: 60,
                plannedHours: 2,
                recordedHours: 2,
                matchedHours: 1
            ),
            scoreSummary(
                date: try #require(calendar.date(byAdding: .day, value: -6, to: base)),
                totalScore: 70,
                plannedHours: 1,
                recordedHours: 1,
                matchedHours: 1
            )
        ]

        let delta = DashboardPeriodDeltaSummary.make(
            currentSummaries: current,
            previousSummaries: previous
        )

        #expect(delta.score.current == 80)
        #expect(delta.score.previous == 65)
        #expect(delta.score.delta == 15)
        #expect(abs((delta.score.percentChange ?? 0) - (15.0 / 65.0)) < 0.0001)
        #expect(delta.recordedDuration.delta == 60 * 60)
        #expect(delta.plannedDuration.delta == -60 * 60)
        #expect(delta.scoredDayCount.delta == -1)
    }

    @Test
    func periodDeltaHasNilPercentChangeWhenPreviousValueIsZero() throws {
        let calendar = Calendar.liminalogTest
        let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let current = [
            scoreSummary(date: base, totalScore: 90, plannedHours: 1, recordedHours: 1, matchedHours: 1)
        ]

        let delta = DashboardPeriodDeltaSummary.make(currentSummaries: current, previousSummaries: [])

        #expect(delta.score.delta == 90)
        #expect(delta.score.percentChange == nil)
        #expect(delta.score.isIncrease)
        #expect(!delta.score.isDecrease)
    }

    private func chapter(category: Liminalog.Category, start: Date, end: Date) -> Chapter {
        let chapter = Chapter(category: category, startTime: start)
        chapter.endTime = end
        return chapter
    }

    private func row(for segment: DashboardTimeOfDay, in summary: DashboardTimeOfDaySummary) -> DashboardTimeOfDayRow? {
        summary.rows.first { $0.segment == segment }
    }

    private func duration(for segment: DashboardTimeOfDay, in summary: DashboardTimeOfDaySummary) -> TimeInterval {
        row(for: segment, in: summary)?.duration ?? 0
    }

    private func scoreSummary(
        date: Date,
        totalScore: Double,
        plannedHours: Double,
        recordedHours: Double,
        matchedHours: Double
    ) -> ScoreSummary {
        ScoreSummary(
            date: date,
            categoryScore: totalScore,
            timelineScore: totalScore,
            totalScore: totalScore,
            plannedDuration: plannedHours * 60 * 60,
            recordedDuration: recordedHours * 60 * 60,
            matchedDuration: matchedHours * 60 * 60
        )
    }
}

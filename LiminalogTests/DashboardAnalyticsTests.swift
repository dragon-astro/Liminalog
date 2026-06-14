import Foundation
import Testing
@testable import Liminalog

struct DashboardAnalyticsTests {
    @Test
    func hourRhythmSplitsChaptersByOverlappedHourAndCategory() throws {
        let calendar = Calendar.liminalogTest
        let study = Category(name: "勉強", colorHex: "#2F80ED")
        let hobby = Category(name: "趣味", colorHex: "#F2994A")
        let studyChapter = Chapter(
            category: study,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9, minute: 30)))
        )
        studyChapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 11, minute: 30))
        let hobbyChapter = Chapter(
            category: hobby,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 15)))
        )
        hobbyChapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 45))

        let stats = HourStat.stats(from: [studyChapter, hobbyChapter], calendar: calendar)

        #expect(stats[9].duration == TimeInterval(30 * 60))
        #expect(stats[9].segments.first?.category?.id == study.id)
        #expect(stats[10].duration == TimeInterval(90 * 60))
        #expect(stats[10].segments.count == 2)
        #expect(stats[10].segments.first?.category?.id == study.id)
        #expect(stats[10].segments.first?.duration == TimeInterval(60 * 60))
        #expect(stats[10].segments.last?.category?.id == hobby.id)
        #expect(stats[10].segments.last?.duration == TimeInterval(30 * 60))
        #expect(stats[11].duration == TimeInterval(30 * 60))
        #expect(stats[11].segments.first?.category?.id == study.id)
        #expect(stats[12].duration == 0)
    }

    @Test
    func hourRhythmGroupsOvernightChaptersByLocalHourOfDay() throws {
        let calendar = Calendar.liminalogTest
        let sleep = Category(name: "睡眠", colorHex: "#8B5CF6")
        let chapter = Chapter(
            category: sleep,
            startTime: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 30)))
        )
        chapter.endTime = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 1, minute: 30))

        let stats = HourStat.stats(from: [chapter], calendar: calendar)

        #expect(stats[23].duration == TimeInterval(30 * 60))
        #expect(stats[0].duration == TimeInterval(60 * 60))
        #expect(stats[1].duration == TimeInterval(30 * 60))
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

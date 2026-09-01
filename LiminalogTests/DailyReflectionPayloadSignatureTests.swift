import Foundation
import Testing
@testable import Liminalog

struct DailyReflectionPayloadSignatureTests {
    @Test
    func structuredSignaturesTrackTheSameRenderAndSnapshotInputs() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let start = try #require(calendar.date(byAdding: .hour, value: 9, to: day))
        let end = try #require(calendar.date(byAdding: .hour, value: 1, to: start))
        let category = Category(name: "勉強", colorHex: "#2F80ED")
        let plan = PlanBlock(category: category, title: "復習", startTime: start, endTime: end)
        let chapter = Chapter(category: category, startTime: start)
        chapter.endTime = end
        let summary = ScoreSummary(
            date: day,
            categoryScore: 100,
            timelineScore: 100,
            totalScore: 100,
            plannedDuration: 3_600,
            recordedDuration: 3_600,
            matchedDuration: 3_600
        )
        let persona = DailyPersona(
            kind: .planMatched,
            title: "有言実行の人",
            message: "予定どおり",
            symbol: "checkmark",
            facts: []
        )
        let payload = DailyReflectionPayload(
            date: day,
            dayBoundary: DayBoundary(date: day, calendar: calendar),
            dayPlans: [plan],
            dayChapters: [chapter],
            historyChapters: [chapter],
            summary: summary,
            recordedDuration: 3_600,
            categoryRows: [(category: category, duration: 3_600)],
            persona: persona
        )

        let initialRenderSignature = payload.renderSignature
        let initialSnapshotSignature = payload.snapshotSignature
        plan.updatedAt = try #require(calendar.date(byAdding: .minute, value: 1, to: plan.updatedAt))

        #expect(payload.renderSignature != initialRenderSignature)
        #expect(payload.snapshotSignature == initialSnapshotSignature)
    }
}

import Foundation
import Testing
@testable import Liminalog

@MainActor
struct ProfileDailyCardEntryTests {
    @Test
    func mergedUsesPersistedCardBeforeGeneratedFallback() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let dayStart = DayBoundary.dayStart(for: day, calendar: calendar)
        let dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
        let category = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")

        let cardSnapshot = DailyCardSnapshot()
        cardSnapshot.dayStart = dayStart
        cardSnapshot.dayIdentifier = dayIdentifier
        cardSnapshot.personaKind = .signal
        cardSnapshot.title = "保存済みの称号"
        cardSnapshot.message = "昨日カードで確定した本文"
        cardSnapshot.symbol = "crown.fill"
        cardSnapshot.score = 91
        cardSnapshot.recordedDuration = 2 * 60 * 60
        cardSnapshot.updatedAt = day.addingTimeInterval(60)

        let scoreSnapshot = DailyScoreSnapshot()
        scoreSnapshot.dayStart = dayStart
        scoreSnapshot.dayIdentifier = dayIdentifier
        scoreSnapshot.score = 80
        scoreSnapshot.plannedDuration = 2 * 60 * 60
        scoreSnapshot.recordedDuration = 90 * 60
        scoreSnapshot.hasRecord = true
        scoreSnapshot.categoryIDs = [category.id]

        let entries = ProfileDailyCardEntry.merged(
            snapshots: [cardSnapshot],
            scoreSnapshots: [scoreSnapshot],
            categories: [category]
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "保存済みの称号")
        #expect(!entries[0].isGeneratedFromScoreSnapshot)
    }

    @Test
    func mergedGeneratesCardForUnopenedPastScoreDay() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))
        let dayStart = DayBoundary.dayStart(for: day, calendar: calendar)
        let category = Category(name: "制作", colorHex: "#5FE0A8", icon: "hammer.fill")

        let scoreSnapshot = DailyScoreSnapshot()
        scoreSnapshot.dayStart = dayStart
        scoreSnapshot.dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
        scoreSnapshot.score = 95
        scoreSnapshot.plannedDuration = 3 * 60 * 60
        scoreSnapshot.recordedDuration = 3 * 60 * 60
        scoreSnapshot.hasRecord = true
        scoreSnapshot.planMatchedDay = true
        scoreSnapshot.categoryIDs = [category.id]

        let entries = ProfileDailyCardEntry.merged(
            snapshots: [],
            scoreSnapshots: [scoreSnapshot],
            categories: [category]
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "予定通りの日")
        #expect(entries[0].message == "制作を中心に過ごした日")
        #expect(entries[0].personaKind == .planMatched)
        #expect(entries[0].isGeneratedFromScoreSnapshot)
    }

    @Test
    func generatedPastCardUsesCategoryAnalysisKindCopy() throws {
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        let dayStart = DayBoundary.dayStart(for: day, calendar: calendar)
        let category = Category(
            name: "制作",
            colorHex: "#5FE0A8",
            icon: "hammer.fill",
            analysisKind: .work
        )

        let scoreSnapshot = DailyScoreSnapshot()
        scoreSnapshot.dayStart = dayStart
        scoreSnapshot.dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
        scoreSnapshot.score = 95
        scoreSnapshot.plannedDuration = 3 * 60 * 60
        scoreSnapshot.recordedDuration = 3 * 60 * 60
        scoreSnapshot.hasRecord = true
        scoreSnapshot.planMatchedDay = true
        scoreSnapshot.categoryIDs = [category.id]

        let entries = ProfileDailyCardEntry.merged(
            snapshots: [],
            scoreSnapshots: [scoreSnapshot],
            categories: [category]
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "予定通り進んだ日")
        #expect(entries[0].message.contains("制作"))
        #expect(entries[0].message.contains("仕事"))
    }
}

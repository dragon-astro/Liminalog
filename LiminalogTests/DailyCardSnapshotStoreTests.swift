import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct DailyCardSnapshotStoreTests {
    @Test
    func upsertCreatesAndUpdatesSingleSnapshotPerDay() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = DailyCardSnapshotStore(modelContext: context)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let category = Category(name: "制作", colorHex: "#2F80ED", icon: "hammer.fill")
        let summary = ScoreSummary(
            date: day,
            categoryScore: 80,
            timelineScore: 90,
            totalScore: 88,
            plannedDuration: 2 * 60 * 60,
            recordedDuration: 2 * 60 * 60,
            matchedDuration: 90 * 60
        )

        let first = store.upsert(
            date: day,
            summary: summary,
            persona: persona(title: "スプリンター", kind: .shape),
            categoryRows: [(category: category, duration: 2 * 60 * 60)],
            recordedDuration: 2 * 60 * 60,
            calendar: calendar,
            now: day
        )
        let updated = store.upsert(
            date: day,
            summary: summary,
            persona: persona(title: "有言実行の人", kind: .planMatched),
            categoryRows: [(category: category, duration: 90 * 60)],
            recordedDuration: 90 * 60,
            calendar: calendar,
            now: try #require(calendar.date(byAdding: .hour, value: 1, to: day))
        )

        let snapshots = try context.fetch(FetchDescriptor<DailyCardSnapshot>())
        #expect(snapshots.count == 1)
        #expect(first.id == updated.id)
        #expect(updated.dayIdentifier == "2026-06-01")
        #expect(updated.personaKind == .planMatched)
        #expect(updated.title == "有言実行の人")
        #expect(updated.recordedDuration == 90 * 60)
        #expect(updated.facts.map(\.title) == ["一致率"])
        #expect(updated.categories.first?.name == "制作")
    }

    @Test
    func titleCollectionAggregatesPersistedCardTitles() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = DailyCardSnapshotStore(modelContext: context)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let thirdDay = try #require(calendar.date(byAdding: .day, value: 2, to: day))
        let summary = ScoreSummary(
            date: day,
            categoryScore: 0,
            timelineScore: 0,
            totalScore: 0,
            plannedDuration: 0,
            recordedDuration: 60 * 60,
            matchedDuration: 0
        )

        store.upsert(date: day, summary: summary, persona: persona(title: "風まかせの人", kind: .noPlan), categoryRows: [], recordedDuration: 60 * 60, calendar: calendar, now: day)
        store.upsert(date: secondDay, summary: summary, persona: persona(title: "風まかせの人", kind: .noPlan), categoryRows: [], recordedDuration: 60 * 60, calendar: calendar, now: secondDay)
        store.upsert(date: thirdDay, summary: summary, persona: persona(title: "充電の人", kind: .chargeDay), categoryRows: [], recordedDuration: 60 * 60, calendar: calendar, now: thirdDay)

        let collection = store.titleCollection()

        #expect(collection.map(\.title) == ["風まかせの人", "充電の人"])
        #expect(collection[0].count == 2)
        #expect(collection[0].personaKind == .noPlan)
        #expect(collection[1].latestDayStart == DayBoundary.dayStart(for: thirdDay, calendar: calendar))
    }

    @Test
    func upsertSkipsSaveWhenSnapshotIsUnchanged() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = DailyCardSnapshotStore(modelContext: context)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let later = try #require(calendar.date(byAdding: .hour, value: 1, to: day))
        let summary = ScoreSummary(
            date: day,
            categoryScore: 80,
            timelineScore: 90,
            totalScore: 88,
            plannedDuration: 2 * 60 * 60,
            recordedDuration: 2 * 60 * 60,
            matchedDuration: 90 * 60
        )

        let first = store.upsert(
            date: day,
            summary: summary,
            persona: persona(title: "有言実行の人", kind: .planMatched),
            categoryRows: [],
            recordedDuration: 2 * 60 * 60,
            calendar: calendar,
            now: day
        )
        let firstUpdatedAt = first.updatedAt
        let second = store.upsert(
            date: day,
            summary: summary,
            persona: persona(title: "有言実行の人", kind: .planMatched),
            categoryRows: [],
            recordedDuration: 2 * 60 * 60,
            calendar: calendar,
            now: later
        )

        #expect(first.id == second.id)
        #expect(second.updatedAt == firstUpdatedAt)
        #expect(try context.fetch(FetchDescriptor<DailyCardSnapshot>()).count == 1)
    }

    @Test
    func backfillCreatesCardsForUnopenedScoreSnapshots() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = DailyCardSnapshotStore(modelContext: context)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let category = Category(name: "制作", colorHex: "#2F80ED", icon: "hammer.fill")
        context.insert(category)

        for targetDay in [day, secondDay] {
            let dayStart = DayBoundary.dayStart(for: targetDay, calendar: calendar)
            let plan = PlanBlock(
                category: category,
                title: "制作",
                startTime: dayStart,
                endTime: try #require(calendar.date(byAdding: .hour, value: 2, to: dayStart))
            )
            let chapter = Chapter(category: category, startTime: dayStart)
            chapter.endTime = calendar.date(byAdding: .minute, value: 90, to: dayStart)
            context.insert(plan)
            context.insert(chapter)

            let scoreSnapshot = DailyScoreSnapshot()
            scoreSnapshot.dayStart = dayStart
            scoreSnapshot.dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
            scoreSnapshot.score = 80
            scoreSnapshot.plannedDuration = 2 * 60 * 60
            scoreSnapshot.recordedDuration = 90 * 60
            scoreSnapshot.hasRecord = true
            scoreSnapshot.categoryIDs = [category.id]
            context.insert(scoreSnapshot)
        }
        try context.save()

        let insertedCount = store.backfillMissingSnapshots(
            from: try context.fetch(FetchDescriptor<DailyScoreSnapshot>()),
            calendar: calendar,
            now: try #require(calendar.date(byAdding: .day, value: 3, to: day))
        )

        let snapshots = try context.fetch(FetchDescriptor<DailyCardSnapshot>(
            sortBy: [SortDescriptor(\.dayStart)]
        ))
        #expect(insertedCount == 2)
        #expect(snapshots.map(\.dayIdentifier) == ["2026-06-01", "2026-06-02"])
        #expect(snapshots.allSatisfy { !$0.title.isEmpty })
        #expect(snapshots.allSatisfy { $0.categories.first?.name == "制作" })

        let secondInsertedCount = store.backfillMissingSnapshots(
            from: try context.fetch(FetchDescriptor<DailyScoreSnapshot>()),
            calendar: calendar
        )
        #expect(secondInsertedCount == 0)
        #expect(try context.fetch(FetchDescriptor<DailyCardSnapshot>()).count == 2)
    }

    private func persona(title: String, kind: DailyCardPersonaKind) -> DailyPersona {
        DailyPersona(
            kind: kind,
            title: title,
            message: "\(title) の本文",
            symbol: "sparkles",
            facts: [
                DailyCardFact(
                    id: "match-rate",
                    title: "一致率",
                    value: "75",
                    suffix: "%",
                    systemImage: "checkmark.seal.fill"
                )
            ]
        )
    }
}

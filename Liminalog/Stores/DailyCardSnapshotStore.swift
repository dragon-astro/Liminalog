import Foundation
import SwiftData

@MainActor
struct DailyCardSnapshotStore {
    let modelContext: ModelContext

    private enum SnapshotLookup {
        case found(DailyCardSnapshot)
        case missing
        case failed
    }

    @discardableResult
    func upsert(
        date: Date,
        summary: ScoreSummary,
        persona: DailyPersona,
        categoryRows: [(category: Category, duration: TimeInterval)],
        recordedDuration: TimeInterval,
        calendar: Calendar = .japanese,
        now: Date = Date()
    ) -> DailyCardSnapshot {
        let dayStart = DayBoundary.dayStart(for: date, calendar: calendar)
        let dayIdentifier = DailyCardSnapshot.dayIdentifier(for: dayStart, calendar: calendar)
        let lookup = existingSnapshot(dayIdentifier: dayIdentifier)
        let score = Int(summary.totalScore.rounded())
        let factPayloadJSON = DailyCardSnapshot.encode(
            persona.facts.map {
                DailyCardSnapshotFactPayload(
                    id: $0.id,
                    title: $0.title,
                    value: $0.value,
                    suffix: $0.suffix,
                    systemImage: $0.systemImage
                )
            }
        )
        let categoryPayloadJSON = DailyCardSnapshot.encode(
            categoryRows.prefix(6).map {
                DailyCardSnapshotCategoryPayload(
                    categoryID: $0.category.id,
                    name: $0.category.name,
                    colorHex: $0.category.colorHex,
                    duration: $0.duration
                )
            }
        )
        let snapshot: DailyCardSnapshot
        let shouldInsert: Bool
        let canSave: Bool
        switch lookup {
        case .found(let existingSnapshot):
            snapshot = existingSnapshot
            shouldInsert = false
            canSave = true
        case .missing:
            snapshot = DailyCardSnapshot()
            shouldInsert = true
            canSave = true
        case .failed:
            snapshot = DailyCardSnapshot()
            shouldInsert = false
            canSave = false
        }

        let hasChanges = shouldInsert || snapshot.dayStart != dayStart ||
            snapshot.dayIdentifier != dayIdentifier ||
            snapshot.schemaVersion != 1 ||
            snapshot.personaKind != persona.kind ||
            snapshot.title != persona.title ||
            snapshot.message != persona.message ||
            snapshot.symbol != persona.symbol ||
            snapshot.score != score ||
            snapshot.plannedDuration != summary.plannedDuration ||
            snapshot.recordedDuration != recordedDuration ||
            snapshot.factPayloadJSON != factPayloadJSON ||
            snapshot.categoryPayloadJSON != categoryPayloadJSON

        guard hasChanges else {
            return snapshot
        }

        snapshot.dayStart = dayStart
        snapshot.dayIdentifier = dayIdentifier
        snapshot.schemaVersion = 1
        snapshot.personaKind = persona.kind
        snapshot.title = persona.title
        snapshot.message = persona.message
        snapshot.symbol = persona.symbol
        snapshot.score = score
        snapshot.plannedDuration = summary.plannedDuration
        snapshot.recordedDuration = recordedDuration
        snapshot.factPayloadJSON = factPayloadJSON
        snapshot.categoryPayloadJSON = categoryPayloadJSON
        snapshot.updatedAt = now

        if shouldInsert {
            snapshot.createdAt = now
            modelContext.insert(snapshot)
        }
        if canSave {
            saveChanges("daily card snapshot")
        }
        return snapshot
    }

    func snapshots() -> [DailyCardSnapshot] {
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card snapshots: \(String(describing: error))")
            return []
        }
    }

    func titleCollection() -> [DailyCardTitleCollectionEntry] {
        let grouped = Dictionary(grouping: snapshots().filter { !$0.title.isEmpty }, by: \.title)
        return grouped.compactMap { title, snapshots in
            guard let latest = snapshots.max(by: { $0.dayStart < $1.dayStart }) else { return nil }
            return DailyCardTitleCollectionEntry(
                title: title,
                personaKind: latest.personaKind,
                symbol: latest.symbol,
                count: snapshots.count,
                latestDayStart: latest.dayStart
            )
        }
        .sorted {
            if $0.count == $1.count {
                return $0.latestDayStart > $1.latestDayStart
            }
            return $0.count > $1.count
        }
    }

    @discardableResult
    func backfillMissingSnapshots(
        from scoreSnapshots: [DailyScoreSnapshot],
        limit: Int = 120,
        calendar: Calendar = .japanese,
        now: Date = Date()
    ) -> Int {
        let candidates = scoreSnapshots
            .filter(\.shouldDisplayAsDailyCard)
            .sorted { $0.dayStart > $1.dayStart }
            .prefix(max(limit, 0))
        guard !candidates.isEmpty else { return 0 }

        let dayStarts = candidates.map(\.dayStart)
        guard let earliestDayStart = dayStarts.min(),
              let latestDayStart = dayStarts.max(),
              let fetchEnd = calendar.date(byAdding: .day, value: 1, to: latestDayStart),
              let historyStart = calendar.date(byAdding: .day, value: -28, to: earliestDayStart)
        else { return 0 }

        let existingIDs = Set(snapshots(in: DateInterval(start: earliestDayStart, end: fetchEnd)).map(\.dayIdentifier))
        let missingCandidates = candidates.filter { !existingIDs.contains($0.dayIdentifier) }
        guard !missingCandidates.isEmpty else { return 0 }

        let plans = plannedBlocks(in: DateInterval(start: earliestDayStart, end: fetchEnd))
        let chapters = chapters(in: DateInterval(start: historyStart, end: fetchEnd), now: now)
        var insertedCount = 0

        for scoreSnapshot in missingCandidates {
            let boundary = DayBoundary(date: scoreSnapshot.dayStart, calendar: calendar)
            let dayPlans = plans.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chapters.filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart }
            let historyChapters = chapters.filter { $0.startTime < boundary.dayEnd }
            let categoryRows = categoryRows(for: dayChapters, dayBoundary: boundary, now: now)
            let summary = ScoreCalculator.summary(
                date: scoreSnapshot.dayStart,
                plans: dayPlans,
                chapters: dayChapters,
                calendar: calendar,
                now: now
            )
            let recordedDuration = recordedDuration(for: dayChapters, dayBoundary: boundary, now: now)
            let persona = DailyPersona.make(
                summary: summary,
                chapters: dayChapters,
                historyChapters: historyChapters,
                categoryRows: categoryRows,
                recordedDuration: recordedDuration,
                dayBoundary: boundary
            )

            upsert(
                date: scoreSnapshot.dayStart,
                summary: summary,
                persona: persona,
                categoryRows: categoryRows,
                recordedDuration: recordedDuration,
                calendar: calendar,
                now: now
            )
            insertedCount += 1
        }

        return insertedCount
    }

    private func existingSnapshot(dayIdentifier: String) -> SnapshotLookup {
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let matches: [DailyCardSnapshot]
        do {
            matches = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card snapshot \(dayIdentifier): \(String(describing: error))")
            return .failed
        }
        guard let primary = matches.first else { return .missing }
        for duplicate in matches.dropFirst() {
            modelContext.delete(duplicate)
        }
        return .found(primary)
    }

    private func snapshots(in interval: DateInterval) -> [DailyCardSnapshot] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            predicate: #Predicate { $0.dayStart >= start && $0.dayStart < end },
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card snapshots for backfill: \(String(describing: error))")
            return []
        }
    }

    private func plannedBlocks(in interval: DateInterval) -> [PlanBlock] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card backfill plans: \(String(describing: error))")
            return []
        }
    }

    private func chapters(in interval: DateInterval, now: Date) -> [Chapter] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
                .filter { ($0.endTime ?? now) > start }
        } catch {
            NSLog("Liminalog: failed to fetch daily card backfill chapters: \(String(describing: error))")
            return []
        }
    }

    private func recordedDuration(
        for chapters: [Chapter],
        dayBoundary: DayBoundary,
        now: Date
    ) -> TimeInterval {
        chapters.reduce(0) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
            return partial + max(end.timeIntervalSince(start), 0)
        }
    }

    private func categoryRows(
        for chapters: [Chapter],
        dayBoundary: DayBoundary,
        now: Date
    ) -> [(category: Category, duration: TimeInterval)] {
        let grouped = Dictionary(grouping: chapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
            return (category, max(end.timeIntervalSince(start), 0))
        }, by: { $0.0.id })

        return grouped.compactMap { _, values in
            guard let category = values.first?.0 else { return nil }
            return (category, values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.duration > $1.duration }
    }

    private func saveChanges(_ action: String) {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
        }
    }
}

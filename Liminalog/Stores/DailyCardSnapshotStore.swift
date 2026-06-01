import Foundation
import SwiftData

@MainActor
struct DailyCardSnapshotStore {
    let modelContext: ModelContext

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
        let snapshot = existingSnapshot(dayIdentifier: dayIdentifier) ?? DailyCardSnapshot()
        let isNew = snapshot.dayIdentifier.isEmpty

        snapshot.dayStart = dayStart
        snapshot.dayIdentifier = dayIdentifier
        snapshot.schemaVersion = 1
        snapshot.personaKind = persona.kind
        snapshot.title = persona.title
        snapshot.message = persona.message
        snapshot.symbol = persona.symbol
        snapshot.score = Int(summary.totalScore.rounded())
        snapshot.plannedDuration = summary.plannedDuration
        snapshot.recordedDuration = recordedDuration
        snapshot.factPayloadJSON = DailyCardSnapshot.encode(
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
        snapshot.categoryPayloadJSON = DailyCardSnapshot.encode(
            categoryRows.prefix(6).map {
                DailyCardSnapshotCategoryPayload(
                    categoryID: $0.category.id,
                    name: $0.category.name,
                    colorHex: $0.category.colorHex,
                    duration: $0.duration
                )
            }
        )
        snapshot.updatedAt = now

        if isNew {
            snapshot.createdAt = now
            modelContext.insert(snapshot)
        }
        try? modelContext.save()
        return snapshot
    }

    func snapshots() -> [DailyCardSnapshot] {
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

    private func existingSnapshot(dayIdentifier: String) -> DailyCardSnapshot? {
        let descriptor = FetchDescriptor<DailyCardSnapshot>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let matches = try? modelContext.fetch(descriptor),
              let primary = matches.first
        else { return nil }
        for duplicate in matches.dropFirst() {
            modelContext.delete(duplicate)
        }
        return primary
    }
}

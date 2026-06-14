import Foundation

@MainActor
struct ProfileDailyCardEntry: Identifiable, Hashable {
    let id: String
    let dayStart: Date
    let dayIdentifier: String
    let personaKind: DailyCardPersonaKind
    let title: String
    let message: String
    let symbol: String
    let score: Int
    let plannedDuration: TimeInterval
    let recordedDuration: TimeInterval
    let categories: [DailyCardSnapshotCategoryPayload]
    let isGeneratedFromScoreSnapshot: Bool

    init(snapshot: DailyCardSnapshot) {
        id = snapshot.dayIdentifier
        dayStart = snapshot.dayStart
        dayIdentifier = snapshot.dayIdentifier
        personaKind = snapshot.personaKind
        title = snapshot.title
        message = snapshot.message
        symbol = snapshot.symbol
        score = snapshot.score
        plannedDuration = snapshot.plannedDuration
        recordedDuration = snapshot.recordedDuration
        categories = snapshot.categories
        isGeneratedFromScoreSnapshot = false
    }

    init(scoreSnapshot: DailyScoreSnapshot, categoriesByID: [UUID: Category]) {
        let primaryCategory = scoreSnapshot.categoryIDs.compactMap { categoriesByID[$0] }.first
        let draft = DailyCardLifestyleCopy.fallbackDraft(for: scoreSnapshot, primaryCategory: primaryCategory)

        id = scoreSnapshot.dayIdentifier
        dayStart = scoreSnapshot.dayStart
        dayIdentifier = scoreSnapshot.dayIdentifier
        personaKind = Self.personaKind(for: scoreSnapshot)
        title = draft.title
        message = draft.messages.first ?? ""
        symbol = draft.symbol
        score = scoreSnapshot.score
        plannedDuration = scoreSnapshot.plannedDuration
        recordedDuration = scoreSnapshot.recordedDuration
        categories = scoreSnapshot.categoryIDs.compactMap { categoryID in
            guard let category = categoriesByID[categoryID] else { return nil }
            return DailyCardSnapshotCategoryPayload(
                categoryID: category.id,
                name: category.name,
                colorHex: category.colorHex,
                duration: 0
            )
        }
        isGeneratedFromScoreSnapshot = true
    }

    static func merged(
        snapshots: [DailyCardSnapshot],
        scoreSnapshots: [DailyScoreSnapshot],
        categories: [Category]
    ) -> [ProfileDailyCardEntry] {
        let latestSnapshotsByDayIdentifier = Dictionary(grouping: snapshots, by: \.dayIdentifier)
            .compactMapValues { snapshots in
                snapshots.sorted { $0.updatedAt > $1.updatedAt }.first
            }
        var entriesByDayIdentifier = latestSnapshotsByDayIdentifier.mapValues(ProfileDailyCardEntry.init(snapshot:))
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        for scoreSnapshot in scoreSnapshots where scoreSnapshot.shouldDisplayAsDailyCard {
            guard entriesByDayIdentifier[scoreSnapshot.dayIdentifier] == nil else { continue }
            entriesByDayIdentifier[scoreSnapshot.dayIdentifier] = ProfileDailyCardEntry(
                scoreSnapshot: scoreSnapshot,
                categoriesByID: categoriesByID
            )
        }

        return entriesByDayIdentifier.values.sorted {
            if $0.dayStart == $1.dayStart {
                return $0.isGeneratedFromScoreSnapshot == false && $1.isGeneratedFromScoreSnapshot
            }
            return $0.dayStart > $1.dayStart
        }
    }

    private static func personaKind(for snapshot: DailyScoreSnapshot) -> DailyCardPersonaKind {
        if snapshot.planMatchedDay || (snapshot.plannedDuration > 0 && snapshot.score >= 88) {
            return .planMatched
        }
        if snapshot.chargeDay {
            return .chargeDay
        }
        if snapshot.firstRecordDay || snapshot.personalBestDay || snapshot.returnAfterGapDay || snapshot.changeSignalDay {
            return .signal
        }
        if snapshot.plannedDuration <= 0 {
            return .noPlan
        }
        if snapshot.recordedDuration < 45 * 60 {
            return .missingDay
        }
        return .shape
    }
}

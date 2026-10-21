import Foundation
import SwiftData

/// 予定編集で使うカテゴリは、今日を含む直近90日に作成した予定の件数で並べる。
/// 実績や外部カレンダー、自動で展開された繰り返しは選択頻度に混ぜない。
/// 繰り返しを設定した元の予定は、手動で作った1件として数える。
@MainActor
enum CategoryUsageRanking {
    static let lookbackDays = 90

    static func window(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    static func load(modelContext: ModelContext, window: DateInterval) throws -> [UUID: Int] {
        // register() keeps a nil baseline for the explicitly saved source. Generated
        // occurrences retain a baseline even after the user adjusts that day's copy.
        var sources = FetchDescriptor<PlanRecurrenceOccurrence>(predicate: #Predicate {
            $0.baselineData == nil && $0.planID != nil && !$0.isBlocked
        })
        sources.includePendingChanges = false
        let manualRecurrenceIDs = try modelContext.fetch(sources).compactMap(\.planID)
        let manualRecurrencePlanIDs = Set(manualRecurrenceIDs)
        let start = window.start, end = window.end
        var descriptor = FetchDescriptor<PlanBlock>(predicate: #Predicate {
            $0.createdAt >= start && $0.createdAt < end
                && ($0.recurrenceSeriesID == nil || manualRecurrenceIDs.contains($0.id))
        })
        descriptor.includePendingChanges = false
        descriptor.relationshipKeyPathsForPrefetching = [\PlanBlock.category]
        // Filter in the store before materializing models, so opening the editor does
        // not load the many future copies generated from a few recurring defaults.
        let plans = try modelContext.fetch(descriptor)
        return counts(plans: plans, manualRecurrencePlanIDs: manualRecurrencePlanIDs, window: window)
    }

    static func counts(
        plans: [PlanBlock],
        manualRecurrencePlanIDs: Set<UUID>,
        window: DateInterval
    ) -> [UUID: Int] {
        plans.reduce(into: [:]) { counts, plan in
            guard plan.createdAt >= window.start, plan.createdAt < window.end,
                  !plan.hasExternalCalendarSource,
                  plan.recurrenceSeriesID == nil || manualRecurrencePlanIDs.contains(plan.id),
                  let categoryID = plan.category?.id else { return }
            counts[categoryID, default: 0] += 1
        }
    }

    /// 回数の多い順。同数・未使用はカテゴリ管理の並び順。
    /// 同期で sortOrder が重複しても表示順が揺れないよう、作成日時・IDで確定する。
    static func ordered(_ categories: [Category], counts: [UUID: Int]) -> [Category] {
        categories.sorted { lhs, rhs in
            let left = counts[lhs.id, default: 0]
            let right = counts[rhs.id, default: 0]
            if left != right { return left > right }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

/// ChapterStore owns one cache per ModelContext; no models or counts cross account/store boundaries.
/// Reopening the picker reuses counts until content changes or the 90-day window moves.
@MainActor
final class CategoryUsageCache {
    private var entry: (revision: Int, window: DateInterval, counts: [UUID: Int])?

    func counts(
        revision: Int,
        window: DateInterval,
        load: () throws -> [UUID: Int]
    ) rethrows -> [UUID: Int] {
        if let entry, entry.revision == revision, entry.window == window { return entry.counts }
        let counts = try load()
        entry = (revision, window, counts)
        return counts
    }

    func invalidate() { entry = nil }
}

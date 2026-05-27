import Foundation
import SwiftData

@MainActor
final class PlanStore {
    private let modelContext: ModelContext
    private let clock: any LiminalogClock

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        self.modelContext = modelContext
        self.clock = clock
    }

    func isScheduleLocked(_ plan: PlanBlock, now: Date? = nil) -> Bool {
        let reference = now ?? clock.now
        return !plan.isAllDay && DayBoundary.dayStart(for: plan.startTime) <= DayBoundary.dayStart(for: reference)
    }

    func canCreate(startTime: Date, isAllDay: Bool = false, now: Date? = nil) -> Bool {
        if isAllDay {
            return true
        }
        let reference = now ?? clock.now
        return DayBoundary.dayStart(for: startTime) > DayBoundary.dayStart(for: reference)
    }

    func plannedBlocks(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        return plannedBlocks(from: boundary.dayStart, to: boundary.dayEnd)
    }

    func plannedBlocks(from start: Date, to end: Date) -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allPlannedBlocks() -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addPlanBlock(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, isImportant: Bool = false, note: String? = nil, isPublic: Bool = true) -> Bool {
        guard canCreate(startTime: startTime, isAllDay: isAllDay) else { return false }
        let plan = PlanBlock(
            category: category,
            title: normalizedTitle(title, category: category),
            startTime: startTime,
            endTime: max(endTime, startTime.addingTimeInterval(60)),
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            isPublic: isPublic
        )
        plan.updatedAt = clock.now
        modelContext.insert(plan)
        try? modelContext.save()
        return true
    }

    @discardableResult
    func savePlanBlock(_ plan: PlanBlock, category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool, isImportant: Bool, note: String?, isPublic: Bool) -> Bool {
        if isScheduleLocked(plan) {
            plan.isImportant = isImportant
        } else {
            guard canCreate(startTime: startTime, isAllDay: isAllDay) else { return false }
            plan.category = category
            plan.title = normalizedTitle(title, category: category)
            plan.startTime = startTime
            plan.endTime = max(endTime, startTime.addingTimeInterval(60))
            plan.isAllDay = isAllDay
            plan.isImportant = isImportant
        }
        plan.note = note.flatMap { $0.isEmpty ? nil : $0 }
        plan.isPublic = isPublic
        plan.updatedAt = clock.now
        try? modelContext.save()
        return true
    }

    @discardableResult
    func deletePlanBlock(_ plan: PlanBlock) -> Bool {
        guard !isScheduleLocked(plan) else { return false }
        modelContext.delete(plan)
        try? modelContext.save()
        return true
    }

    private func normalizedTitle(_ title: String, category: Category?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (category?.name ?? "予定") : trimmed
    }
}

import Foundation
import SwiftData

struct DayPresetDraft: Equatable {
    var name: String
    var items: [PlanTemplateSnapshot]
    var excludedItemCount: Int
}

@Observable
@MainActor
final class PlanPresetStore {
    private let modelContext: ModelContext
    private let clock: any LiminalogClock

    init(
        modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock()
    ) {
        self.modelContext = modelContext
        self.clock = clock
    }

    func planPresetsIfAvailable() -> [PlanPreset]? {
        do {
            return try modelContext.fetch(FetchDescriptor<PlanPreset>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch plan presets: \(String(describing: error))")
            return nil
        }
    }

    func dayPresetsIfAvailable() -> [DayPreset]? {
        do {
            return try modelContext.fetch(FetchDescriptor<DayPreset>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            ))
        } catch {
            NSLog("Liminalog: failed to fetch day presets: \(String(describing: error))")
            return nil
        }
    }

    @discardableResult
    func createPlanPreset(
        name: String,
        snapshot: PlanTemplateSnapshot,
        placementMode: PlanPresetPlacementMode = .duration
    ) -> PlanPreset? {
        guard isValid(snapshot),
              let presets = planPresetsIfAvailable()
        else { return nil }
        let preset = PlanPreset(
            name: normalizedPlanPresetName(name, title: snapshot.title),
            title: snapshot.title,
            categoryID: snapshot.categoryID,
            startMinute: snapshot.startMinute,
            endMinute: snapshot.endMinute,
            isAllDay: snapshot.isAllDay,
            isImportant: snapshot.isImportant,
            note: normalizedNote(snapshot.note),
            isPublic: snapshot.isPublic,
            placementMode: snapshot.isAllDay ? .fixedTime : placementMode,
            sortOrder: (presets.map(\.sortOrder).max() ?? -1) + 1,
            now: clock.now
        )
        modelContext.insert(preset)
        return saveChanges("plan preset add") ? preset : nil
    }

    @discardableResult
    func updatePlanPreset(
        _ preset: PlanPreset,
        name: String,
        snapshot: PlanTemplateSnapshot,
        placementMode: PlanPresetPlacementMode = .duration
    ) -> Bool {
        guard isValid(snapshot) else { return false }
        preset.name = normalizedPlanPresetName(name, title: snapshot.title)
        preset.title = snapshot.title
        preset.categoryID = snapshot.categoryID
        preset.startMinute = snapshot.startMinute
        preset.endMinute = snapshot.endMinute
        preset.isAllDay = snapshot.isAllDay
        preset.isImportant = snapshot.isImportant
        preset.note = normalizedNote(snapshot.note)
        preset.isPublic = snapshot.isPublic
        preset.placementMode = snapshot.isAllDay ? .fixedTime : placementMode
        preset.updatedAt = clock.now
        return saveChanges("plan preset update")
    }

    @discardableResult
    func deletePlanPreset(_ preset: PlanPreset) -> Bool {
        modelContext.delete(preset)
        return saveChanges("plan preset delete")
    }

    @discardableResult
    func movePlanPresets(from source: IndexSet, to destination: Int) -> Bool {
        guard let presets = planPresetsIfAvailable(),
              SortOrderNormalizer.reorder(
                presets,
                from: source,
                to: destination,
                sortOrder: \.sortOrder
              )
        else { return false }
        return saveChanges("plan preset move")
    }

    @discardableResult
    func markUsed(_ preset: PlanPreset) -> Bool {
        preset.lastUsedAt = clock.now
        preset.useCount += 1
        preset.updatedAt = clock.now
        return saveChanges("plan preset use")
    }

    func items(for preset: DayPreset) -> Result<
        [PlanTemplateSnapshot],
        DayPresetItemsCodec.CodecError
    > {
        do {
            return .success(try DayPresetItemsCodec.decode(preset.itemsData))
        } catch let error as DayPresetItemsCodec.CodecError {
            return .failure(error)
        } catch {
            return .failure(.invalidPayload)
        }
    }

    @discardableResult
    func createDayPreset(
        name: String,
        items: [PlanTemplateSnapshot],
        colorHex: String = "#2F80ED",
        icon: String = "calendar"
    ) -> DayPreset? {
        guard isValidDayPresetItems(items),
              let presets = dayPresetsIfAvailable(),
              let data = try? DayPresetItemsCodec.encode(items)
        else { return nil }
        let nextOrder = (presets.map(\.sortOrder).max() ?? -1) + 1
        let preset = DayPreset(
            name: normalizedDayPresetName(name, fallbackIndex: nextOrder + 1),
            itemsData: data,
            itemCount: items.count,
            colorHex: colorHex,
            icon: icon,
            sortOrder: nextOrder,
            now: clock.now
        )
        modelContext.insert(preset)
        return saveChanges("day preset add") ? preset : nil
    }

    @discardableResult
    func updateDayPreset(
        _ preset: DayPreset,
        name: String,
        items: [PlanTemplateSnapshot],
        colorHex: String? = nil,
        icon: String? = nil
    ) -> Bool {
        guard isValidDayPresetItems(items),
              let data = try? DayPresetItemsCodec.encode(items)
        else { return false }
        preset.name = normalizedDayPresetName(name, fallbackIndex: preset.sortOrder + 1)
        preset.itemsData = data
        preset.itemCount = items.count
        if let colorHex { preset.colorHex = colorHex }
        if let icon { preset.icon = icon }
        preset.updatedAt = clock.now
        return saveChanges("day preset update")
    }

    @discardableResult
    func deleteDayPreset(_ preset: DayPreset) -> Bool {
        modelContext.delete(preset)
        return saveChanges("day preset delete")
    }

    @discardableResult
    func moveDayPresets(from source: IndexSet, to destination: Int) -> Bool {
        guard let presets = dayPresetsIfAvailable(),
              SortOrderNormalizer.reorder(
                presets,
                from: source,
                to: destination,
                sortOrder: \.sortOrder
              )
        else { return false }
        return saveChanges("day preset move")
    }

    @discardableResult
    func markUsed(_ preset: DayPreset) -> Bool {
        preset.lastUsedAt = clock.now
        preset.useCount += 1
        preset.updatedAt = clock.now
        return saveChanges("day preset use")
    }

    func makeDayPresetDraft(
        from date: Date,
        plans: [PlanBlock],
        calendar: Calendar = .current
    ) -> DayPresetDraft {
        let boundary = DayBoundary(date: date, calendar: calendar)
        var items: [PlanTemplateSnapshot] = []
        var excludedItemCount = 0

        for plan in plans.sorted(by: { $0.startTime < $1.startTime }) {
            guard let snapshot = snapshot(
                from: plan,
                boundary: boundary,
                calendar: calendar
            ) else {
                excludedItemCount += 1
                continue
            }
            items.append(snapshot)
        }

        return DayPresetDraft(
            name: "",
            items: items,
            excludedItemCount: excludedItemCount
        )
    }

    private func snapshot(
        from plan: PlanBlock,
        boundary: DayBoundary,
        calendar: Calendar
    ) -> PlanTemplateSnapshot? {
        guard plan.startTime >= boundary.dayStart,
              plan.startTime < boundary.dayEnd,
              plan.endTime > plan.startTime,
              plan.endTime.timeIntervalSince(plan.startTime) <= 24 * 60 * 60
        else { return nil }
        if plan.isAllDay {
            guard plan.startTime == boundary.dayStart,
                  plan.endTime == boundary.dayEnd
            else { return nil }
            return PlanTemplateSnapshot(
                title: plan.title,
                categoryID: plan.category?.id,
                startMinute: 0,
                endMinute: 24 * 60,
                isAllDay: true,
                isImportant: plan.isImportant,
                note: plan.note,
                isPublic: plan.isPublic
            )
        }

        let startMinute = wallClockMinute(
            for: plan.startTime,
            relativeTo: boundary.dayStart,
            calendar: calendar
        )
        let endMinute = wallClockMinute(
            for: plan.endTime,
            relativeTo: boundary.dayStart,
            calendar: calendar
        )
        let result = PlanTemplateSnapshot(
            title: plan.title,
            categoryID: plan.category?.id,
            startMinute: startMinute,
            endMinute: endMinute,
            isAllDay: false,
            isImportant: plan.isImportant,
            note: plan.note,
            isPublic: plan.isPublic
        )
        return result.hasValidTime ? result : nil
    }

    private func wallClockMinute(
        for date: Date,
        relativeTo dayStart: Date,
        calendar: Calendar
    ) -> Int {
        let dateDayStart = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents(
            [.day],
            from: dayStart,
            to: dateDayStart
        ).day ?? 0
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return dayOffset * 24 * 60 + (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }

    private func isValid(_ snapshot: PlanTemplateSnapshot) -> Bool {
        let hasNormalizedTime = snapshot.isAllDay
            ? snapshot.startMinute == 0 && snapshot.endMinute == 24 * 60
            : snapshot.hasValidTime
        return hasNormalizedTime && (snapshot.note?.count ?? 0) <= 200
    }

    private func isValidDayPresetItems(_ items: [PlanTemplateSnapshot]) -> Bool {
        (1...24).contains(items.count)
            && items.allSatisfy(isValid)
            && items.filter(\.isAllDay).count <= 3
            && !DayPresetApplyPlanner.hasConflictsWithinPreset(items)
    }

    private func normalizedPlanPresetName(_ name: String, title: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedTitle.isEmpty ? "予定" : trimmedTitle
        return String((trimmedName.isEmpty ? fallback : trimmedName).prefix(20))
    }

    private func normalizedDayPresetName(_ name: String, fallbackIndex: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "一日プリセット \(fallbackIndex)"
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(20))
    }

    private func normalizedNote(_ note: String?) -> String? {
        note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : note
    }

    private func saveChanges(_ action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }
}

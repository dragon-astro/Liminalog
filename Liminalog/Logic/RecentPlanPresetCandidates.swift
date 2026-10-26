import Foundation

@MainActor
enum RecentPlanPresetCandidates {
    static func make(plans: [PlanBlock], presets: [PlanPreset], calendar: Calendar = .current) -> [PlanPreset] {
        var result: [PlanPreset] = []
        for plan in plans.sorted(by: {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }) {
            guard !plan.hasExternalCalendarSource, plan.recurrenceSeriesID == nil,
                  let snapshot = PlanPresetStore.snapshot(from: plan, calendar: calendar),
                  (snapshot.note?.count ?? 0) <= 200 else { continue }
            let candidate = PlanPreset(name: snapshot.title, title: snapshot.title,
                categoryID: snapshot.categoryID, startMinute: snapshot.startMinute, endMinute: snapshot.endMinute,
                isAllDay: snapshot.isAllDay, isImportant: snapshot.isImportant, note: snapshot.note, locationName: snapshot.locationName, urlString: snapshot.urlString,
                isPublic: snapshot.isPublic, placementMode: snapshot.isAllDay ? .fixedTime : .duration,
                now: plan.createdAt)
            candidate.id = plan.id
            candidate.reminderMinutesBefore = snapshot.reminderMinutesBefore
            guard !presets.contains(where: { matches(candidate, registered: $0) }),
                  !result.contains(where: { matches(candidate, registered: $0) }) else { continue }
            result.append(candidate)
            if result.count == 6 { break }
        }
        return result
    }

    private static func matches(_ candidate: PlanPreset, registered: PlanPreset) -> Bool {
        var lhs = candidate.snapshot
        var rhs = registered.snapshot
        lhs.title = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        rhs.title = registered.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        lhs.note = normalizedNote(lhs.note)
        rhs.note = normalizedNote(rhs.note)
        if registered.placementMode == .duration, !rhs.isAllDay {
            lhs.endMinute = lhs.durationMinutes
            lhs.startMinute = 0
            rhs.endMinute = rhs.durationMinutes
            rhs.startMinute = 0
        }
        return lhs == rhs
    }

    private static func normalizedNote(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

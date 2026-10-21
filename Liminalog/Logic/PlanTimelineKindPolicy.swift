import Foundation

/// A deliberate horizontal movement changes layers; ordinary vertical dragging keeps its kind.
enum PlanTimelineKindPolicy {
    static func memo(atFraction fraction: CGFloat, horizontalMovement: CGFloat, current: Bool, threshold: CGFloat = 20) -> Bool {
        guard abs(horizontalMovement) >= threshold else { return current }
        if fraction <= 0.44 { return false }
        if fraction >= 0.56 { return true }
        return current
    }

    static func resolve(items: [PlanTimelineInterval], editingID: UUID, start: Int, end: Int,
                        direction: PlanTimelinePushDirection, adjustment: PlanTimelineAdjustment,
                        minimumDuration: Int, targetIsMemo: Bool?) -> [PlanTimelineInterval]? {
        let original = items.first { $0.id == editingID }
        let changesKind = targetIsMemo.map { $0 != original?.isMemo } ?? false
        var baseline = items
        if changesKind, let index = baseline.firstIndex(where: { $0.id == editingID }) {
            // Layer changes never push neighbours. A promotion is confirmed and saved atomically on drop.
            baseline[index].isMemo = true
        }
        guard var resolved = PlanTimelineRescheduler.resolveClamped(items: baseline, editingID: editingID,
            proposedStartMinute: start, proposedEndMinute: end, pushDirection: direction,
            adjustment: adjustment, minimumDuration: minimumDuration) else { return nil }
        if let targetIsMemo, let index = resolved.firstIndex(where: { $0.id == editingID }) {
            resolved[index].isMemo = targetIsMemo
        }
        return resolved
    }
}

struct PlanTimelineKindChange: Identifiable {
    var id: UUID { plan.id }
    let plan: PlanBlock
    let start: Date
    let end: Date
    let approval: [PlanMemoPromotionChange]
}

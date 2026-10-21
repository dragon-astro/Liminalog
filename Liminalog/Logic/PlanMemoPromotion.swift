import Foundation

typealias PlanMemoPromotionMode = PlanTemplateReplacementMode

extension PlanTemplateReplacementMode {
    func replacement(changes: [PlanMemoPromotionChange], start: Date, end: Date) -> PlanTemplateReplacement {
        return PlanTemplateReplacement(mode: self == .keepRemainders ? .keepRemainders : .replaceWholePlans,
            changes: changes.map { change in
                let original = DateInterval(start: change.start, end: change.end)
                let remaining = self == .keepRemainders
                    ? PlanTemplateReplacement.remainingParts(of: original, excluding: [.init(start: start, end: end)]) : []
                return .init(id: change.id, title: change.title, updatedAt: change.updatedAt, original: original,
                    remaining: remaining, colorHex: change.colorHex, icon: change.icon)
            })
    }
}

/// Approval is tied to exactly the affected main plan revisions and ranges.
struct PlanMemoPromotionChange: Equatable, Identifiable {
    let id: UUID
    let updatedAt: Date
    let title: String
    let start: Date
    let end: Date
    let colorHex: String?
    let icon: String?

    init(_ plan: PlanBlock) {
        id = plan.id; updatedAt = plan.updatedAt; title = plan.title
        start = plan.startTime; end = plan.endTime
        colorHex = plan.category?.colorHex; icon = plan.category?.icon
    }
}

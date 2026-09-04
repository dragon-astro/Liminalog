import Foundation

enum PlanTemplateReplacementMode: String, CaseIterable, Identifiable {
    case keepRemainders
    case replaceWholePlans
    var id: String { rawValue }
    var title: String {
        self == .keepRemainders ? "重なる部分だけ置換" : "重なる予定を丸ごと置換"
    }
}

/// Value-only preview also acts as approval for exactly these revisions/ranges.
/// Recomputed immediately before saving; a changed preview requires new approval.
struct PlanTemplateReplacement: Equatable {
    struct Change: Equatable {
        let id: UUID
        let title: String
        let updatedAt: Date
        let original: DateInterval
        let remaining: [DateInterval]
    }
    let mode: PlanTemplateReplacementMode
    let changes: [Change]

    static func remainingParts(of original: DateInterval, excluding incoming: [DateInterval]) -> [DateInterval] {
        incoming.sorted { $0.start < $1.start }.reduce([original]) { parts, cut in
            guard cut.start < cut.end else { return parts }
            return parts.flatMap { part -> [DateInterval] in
                guard cut.start < part.end, cut.end > part.start else { return [part] }
                var result: [DateInterval] = []
                if part.start < cut.start { result.append(DateInterval(start: part.start, end: cut.start)) }
                if cut.end < part.end { result.append(DateInterval(start: cut.end, end: part.end)) }
                return result
            }
        }
    }
}

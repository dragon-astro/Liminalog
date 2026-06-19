import Foundation

struct PlanTimelineInterval: Hashable, Identifiable {
    let id: UUID
    var startMinute: Int
    var endMinute: Int
    var isLocked: Bool = false

    var duration: Int {
        max(endMinute - startMinute, 0)
    }
}

enum PlanTimelinePushDirection: Equatable {
    case earlier
    case later
}

enum PlanTimelineResizeEdge {
    case start
    case end
}

struct PlanTimelineResizeResult: Equatable {
    let startMinute: Int
    let endMinute: Int
    let pushDirection: PlanTimelinePushDirection
    let feedbackMinute: Int
}

enum PlanTimelineRescheduler {
    static let dayStartMinute = 0
    static let dayEndMinute = 24 * 60

    static func resizedBounds(
        originalStartMinute: Int,
        originalEndMinute: Int,
        edge: PlanTimelineResizeEdge,
        delta: Int,
        minimumDuration: Int = 15
    ) -> PlanTimelineResizeResult {
        switch edge {
        case .start:
            let rawStart = originalStartMinute + delta
            let clampedStart = max(
                dayStartMinute,
                min(dayEndMinute - minimumDuration, rawStart)
            )
            if clampedStart > originalEndMinute - minimumDuration {
                return PlanTimelineResizeResult(
                    startMinute: clampedStart,
                    endMinute: clampedStart + minimumDuration,
                    pushDirection: .later,
                    feedbackMinute: clampedStart
                )
            }
            return PlanTimelineResizeResult(
                startMinute: clampedStart,
                endMinute: originalEndMinute,
                pushDirection: clampedStart < originalStartMinute ? .earlier : .later,
                feedbackMinute: clampedStart
            )

        case .end:
            let rawEnd = originalEndMinute + delta
            let clampedEnd = min(
                dayEndMinute,
                max(dayStartMinute + minimumDuration, rawEnd)
            )
            if clampedEnd < originalStartMinute + minimumDuration {
                return PlanTimelineResizeResult(
                    startMinute: clampedEnd - minimumDuration,
                    endMinute: clampedEnd,
                    pushDirection: .earlier,
                    feedbackMinute: clampedEnd
                )
            }
            return PlanTimelineResizeResult(
                startMinute: originalStartMinute,
                endMinute: clampedEnd,
                pushDirection: clampedEnd >= originalEndMinute ? .later : .earlier,
                feedbackMinute: clampedEnd
            )
        }
    }

    static func resolve(
        items: [PlanTimelineInterval],
        editingID: UUID,
        proposedStartMinute: Int,
        proposedEndMinute: Int,
        pushDirection: PlanTimelinePushDirection
    ) -> [PlanTimelineInterval]? {
        guard proposedStartMinute >= dayStartMinute,
              proposedEndMinute <= dayEndMinute,
              proposedStartMinute < proposedEndMinute
        else {
            return nil
        }

        var resolved = items.sorted { lhs, rhs in
            if lhs.startMinute == rhs.startMinute {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startMinute < rhs.startMinute
        }
        guard let editingIndex = resolved.firstIndex(where: { $0.id == editingID }),
              !resolved[editingIndex].isLocked
        else {
            return nil
        }

        resolved[editingIndex].startMinute = proposedStartMinute
        resolved[editingIndex].endMinute = proposedEndMinute
        resolved.sort { lhs, rhs in
            if lhs.startMinute == rhs.startMinute {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startMinute < rhs.startMinute
        }

        guard let updatedEditingIndex = resolved.firstIndex(where: { $0.id == editingID }) else {
            return nil
        }

        switch pushDirection {
        case .later:
            guard pushLater(in: &resolved, editingIndex: updatedEditingIndex) else { return nil }
        case .earlier:
            guard pushEarlier(in: &resolved, editingIndex: updatedEditingIndex) else { return nil }
        }

        return resolved.sorted { lhs, rhs in
            if lhs.startMinute == rhs.startMinute {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startMinute < rhs.startMinute
        }
    }

    private static func pushLater(in items: inout [PlanTimelineInterval], editingIndex: Int) -> Bool {
        let editingInterval = items[editingIndex]
        guard editingInterval.endMinute <= dayEndMinute else { return false }
        var previousEnd = editingInterval.endMinute
        let candidateIndices = items.indices
            .filter { $0 != editingIndex }
            .sorted {
                if items[$0].startMinute == items[$1].startMinute {
                    return items[$0].endMinute < items[$1].endMinute
                }
                return items[$0].startMinute < items[$1].startMinute
            }

        for candidateIndex in candidateIndices {
            guard items[candidateIndex].endMinute > editingInterval.startMinute else { continue }
            guard items[candidateIndex].startMinute < previousEnd else { continue }
            guard !items[candidateIndex].isLocked else { return false }
            let duration = items[candidateIndex].duration
            items[candidateIndex].startMinute = previousEnd
            items[candidateIndex].endMinute = previousEnd + duration
            guard items[candidateIndex].endMinute <= dayEndMinute else { return false }
            previousEnd = items[candidateIndex].endMinute
        }
        return true
    }

    private static func pushEarlier(in items: inout [PlanTimelineInterval], editingIndex: Int) -> Bool {
        let editingInterval = items[editingIndex]
        guard editingInterval.startMinute >= dayStartMinute else { return false }
        var nextStart = editingInterval.startMinute
        let candidateIndices = items.indices
            .filter { $0 != editingIndex }
            .sorted {
                if items[$0].endMinute == items[$1].endMinute {
                    return items[$0].startMinute > items[$1].startMinute
                }
                return items[$0].endMinute > items[$1].endMinute
            }

        for candidateIndex in candidateIndices {
            guard items[candidateIndex].startMinute < editingInterval.endMinute else { continue }
            guard items[candidateIndex].endMinute > nextStart else { continue }
            guard !items[candidateIndex].isLocked else { return false }
            let duration = items[candidateIndex].duration
            items[candidateIndex].endMinute = nextStart
            items[candidateIndex].startMinute = nextStart - duration
            guard items[candidateIndex].startMinute >= dayStartMinute else { return false }
            nextStart = items[candidateIndex].startMinute
        }
        return true
    }
}

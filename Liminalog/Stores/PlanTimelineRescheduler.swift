import Foundation

struct PlanTimelineInterval: Hashable, Identifiable {
    let id: UUID
    var startMinute: Int
    var endMinute: Int
    var isLocked: Bool = false
    var isMemo: Bool = false

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

enum PlanTimelineAdjustment: Equatable {
    case move
    case resizeStart
    case resizeEnd
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

    static func changedIntervals(
        in resolved: [PlanTimelineInterval],
        comparedTo originals: [UUID: PlanTimelineInterval]
    ) -> [PlanTimelineInterval] {
        resolved.filter { interval in
            guard let original = originals[interval.id] else { return true }
            return original.startMinute != interval.startMinute
                || original.endMinute != interval.endMinute
        }
    }

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
                min(originalEndMinute - minimumDuration, rawStart)
            )
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
                max(originalStartMinute + minimumDuration, rawEnd)
            )
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

        guard let editing = items.first(where: { $0.id == editingID }), !editing.isLocked else { return nil }
        if editing.isMemo {
            return sortedIntervals(items.map { item in
                guard item.id == editingID else { return item }
                var copy = item; copy.startMinute = proposedStartMinute; copy.endMinute = proposedEndMinute
                return copy
            })
        }
        if items.contains(where: \.isMemo) {
            guard let main = resolve(items: items.filter { !$0.isMemo }, editingID: editingID,
                proposedStartMinute: proposedStartMinute, proposedEndMinute: proposedEndMinute,
                pushDirection: pushDirection) else { return nil }
            return sortedIntervals(main + items.filter(\.isMemo))
        }
        var resolved = sortedIntervals(items)
        guard let editingIndex = resolved.firstIndex(where: { $0.id == editingID }),
              !resolved[editingIndex].isLocked
        else {
            return nil
        }

        resolved[editingIndex].startMinute = proposedStartMinute
        resolved[editingIndex].endMinute = proposedEndMinute
        resolved = sortedIntervals(resolved)

        guard let updatedEditingIndex = resolved.firstIndex(where: { $0.id == editingID }) else {
            return nil
        }

        switch pushDirection {
        case .later:
            guard pushLater(in: &resolved, editingIndex: updatedEditingIndex) else { return nil }
        case .earlier:
            guard pushEarlier(in: &resolved, editingIndex: updatedEditingIndex) else { return nil }
        }

        return sortedIntervals(resolved)
    }

    private static func sortedIntervals(
        _ intervals: [PlanTimelineInterval]
    ) -> [PlanTimelineInterval] {
        intervals
            .map { (interval: $0, idSortKey: $0.id.uuidString) }
            .sorted { lhs, rhs in
                if lhs.interval.startMinute == rhs.interval.startMinute {
                    return lhs.idSortKey < rhs.idSortKey
                }
                return lhs.interval.startMinute < rhs.interval.startMinute
            }
            .map(\.interval)
    }

    static func resolveClamped(
        items: [PlanTimelineInterval],
        editingID: UUID,
        proposedStartMinute: Int,
        proposedEndMinute: Int,
        pushDirection: PlanTimelinePushDirection,
        adjustment: PlanTimelineAdjustment,
        minimumDuration: Int = 15
    ) -> [PlanTimelineInterval]? {
        guard let original = items.first(where: { $0.id == editingID }),
              proposedStartMinute < proposedEndMinute
        else {
            return nil
        }

        guard !original.isLocked else { return nil }
        if original.isMemo {
            let bounds = clampedToDay(start: proposedStartMinute, end: proposedEndMinute,
                original: original, adjustment: adjustment, minimumDuration: minimumDuration)
            return resolve(items: items, editingID: editingID, proposedStartMinute: bounds.start,
                proposedEndMinute: bounds.end, pushDirection: pushDirection)
        }
        if items.contains(where: \.isMemo) {
            guard let main = resolveClamped(items: items.filter { !$0.isMemo }, editingID: editingID,
                proposedStartMinute: proposedStartMinute, proposedEndMinute: proposedEndMinute,
                pushDirection: pushDirection, adjustment: adjustment, minimumDuration: minimumDuration) else { return nil }
            return sortedIntervals(main + items.filter(\.isMemo))
        }
        var proposal = clampedToDay(
            start: proposedStartMinute,
            end: proposedEndMinute,
            original: original,
            adjustment: adjustment,
            minimumDuration: minimumDuration
        )
        let effectivePushDirection = effectivePushDirection(
            requestedDirection: pushDirection,
            adjustment: adjustment,
            items: items,
            editingID: editingID,
            original: original,
            proposal: proposal
        )

        let correction = correctionForReachability(
            items: items,
            editingID: editingID,
            proposedStartMinute: proposal.start,
            proposedEndMinute: proposal.end,
            pushDirection: effectivePushDirection
        )

        switch (effectivePushDirection, adjustment) {
        case (.later, .resizeEnd):
            proposal.end -= correction
        case (.later, .move):
            proposal.start -= correction
            proposal.end -= correction
        case (.later, .resizeStart):
            if proposal.end == original.endMinute {
                proposal.start = min(proposal.start, proposal.end - minimumDuration)
            } else {
                proposal.start -= correction
                proposal.end -= correction
            }

        case (.earlier, .resizeStart):
            proposal.start += correction
        case (.earlier, .move):
            proposal.start += correction
            proposal.end += correction
        case (.earlier, .resizeEnd):
            if proposal.start == original.startMinute {
                proposal.end = max(proposal.end, proposal.start + minimumDuration)
            } else {
                proposal.start += correction
                proposal.end += correction
            }
        }

        guard proposal.end - proposal.start >= minimumDuration else {
            return nil
        }

        if let resolved = resolve(
            items: items,
            editingID: editingID,
            proposedStartMinute: proposal.start,
            proposedEndMinute: proposal.end,
            pushDirection: effectivePushDirection
        ) {
            return resolved
        }

        return nil
    }

    private static func clampedToDay(
        start: Int,
        end: Int,
        original: PlanTimelineInterval,
        adjustment: PlanTimelineAdjustment,
        minimumDuration: Int
    ) -> (start: Int, end: Int) {
        var start = start
        var end = end

        switch adjustment {
        case .move:
            let duration = max(minimumDuration, end - start)
            start = max(dayStartMinute, min(dayEndMinute - duration, start))
            end = start + duration

        case .resizeStart:
            if end == original.endMinute {
                end = max(dayStartMinute + minimumDuration, min(dayEndMinute, end))
                start = max(dayStartMinute, min(end - minimumDuration, start))
            } else {
                let duration = max(minimumDuration, end - start)
                if start < dayStartMinute {
                    start = dayStartMinute
                    end = start + duration
                }
                if end > dayEndMinute {
                    end = dayEndMinute
                    start = end - duration
                }
            }

        case .resizeEnd:
            if start == original.startMinute {
                start = max(dayStartMinute, min(dayEndMinute - minimumDuration, start))
                end = min(dayEndMinute, max(start + minimumDuration, end))
            } else {
                let duration = max(minimumDuration, end - start)
                if end > dayEndMinute {
                    end = dayEndMinute
                    start = end - duration
                }
                if start < dayStartMinute {
                    start = dayStartMinute
                    end = start + duration
                }
            }
        }

        return (start, end)
    }

    private static func effectivePushDirection(
        requestedDirection: PlanTimelinePushDirection,
        adjustment: PlanTimelineAdjustment,
        items: [PlanTimelineInterval],
        editingID: UUID,
        original: PlanTimelineInterval,
        proposal: (start: Int, end: Int)
    ) -> PlanTimelinePushDirection {
        if let upperBoundary = upperBoundaryEnd(in: items, editingID: editingID, original: original),
           proposal.start < upperBoundary {
            return .earlier
        }
        if let lowerBoundary = lowerBoundaryStart(in: items, editingID: editingID, original: original),
           proposal.end > lowerBoundary {
            return .later
        }

        switch adjustment {
        case .move:
            return requestedDirection
        case .resizeEnd:
            return proposal.start < original.startMinute ? .earlier : requestedDirection
        case .resizeStart:
            return proposal.end > original.endMinute ? .later : requestedDirection
        }
    }

    private static func upperBoundaryEnd(
        in items: [PlanTimelineInterval],
        editingID: UUID,
        original: PlanTimelineInterval
    ) -> Int? {
        items
            .filter { $0.id != editingID && $0.startMinute < original.startMinute }
            .map(\.endMinute)
            .max()
    }

    private static func lowerBoundaryStart(
        in items: [PlanTimelineInterval],
        editingID: UUID,
        original: PlanTimelineInterval
    ) -> Int? {
        items
            .filter { $0.id != editingID && $0.endMinute > original.endMinute }
            .map(\.startMinute)
            .min()
    }

    private static func correctionForReachability(
        items: [PlanTimelineInterval],
        editingID: UUID,
        proposedStartMinute: Int,
        proposedEndMinute: Int,
        pushDirection: PlanTimelinePushDirection
    ) -> Int {
        switch pushDirection {
        case .later:
            return laterOverflow(
                items: items,
                editingID: editingID,
                proposedStartMinute: proposedStartMinute,
                proposedEndMinute: proposedEndMinute
            )
        case .earlier:
            return earlierUnderflow(
                items: items,
                editingID: editingID,
                proposedStartMinute: proposedStartMinute,
                proposedEndMinute: proposedEndMinute
            )
        }
    }

    private static func laterOverflow(
        items: [PlanTimelineInterval],
        editingID: UUID,
        proposedStartMinute: Int,
        proposedEndMinute: Int
    ) -> Int {
        var previousEnd = proposedEndMinute
        if previousEnd > dayEndMinute {
            return previousEnd - dayEndMinute
        }

        let candidates = items
            .filter { $0.id != editingID && $0.endMinute > proposedStartMinute }
            .sorted {
                if $0.startMinute == $1.startMinute {
                    return $0.endMinute < $1.endMinute
                }
                return $0.startMinute < $1.startMinute
            }

        for candidate in candidates {
            guard candidate.startMinute < previousEnd else { break }
            if candidate.isLocked {
                return previousEnd - candidate.startMinute
            }
            previousEnd += candidate.duration
            if previousEnd > dayEndMinute {
                return previousEnd - dayEndMinute
            }
        }

        return 0
    }

    private static func earlierUnderflow(
        items: [PlanTimelineInterval],
        editingID: UUID,
        proposedStartMinute: Int,
        proposedEndMinute: Int
    ) -> Int {
        var nextStart = proposedStartMinute
        if nextStart < dayStartMinute {
            return dayStartMinute - nextStart
        }

        let candidates = items
            .filter { $0.id != editingID && $0.startMinute < proposedEndMinute }
            .sorted {
                if $0.endMinute == $1.endMinute {
                    return $0.startMinute > $1.startMinute
                }
                return $0.endMinute > $1.endMinute
            }

        for candidate in candidates {
            guard candidate.endMinute > nextStart else { break }
            if candidate.isLocked {
                return candidate.endMinute - nextStart
            }
            nextStart -= candidate.duration
            if nextStart < dayStartMinute {
                return dayStartMinute - nextStart
            }
        }

        return 0
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

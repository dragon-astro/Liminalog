import Foundation

/// Empty-space creation uses the same free interval in real and virtual days.
enum PlanTimelineCreationPolicy {
    struct MinuteRange: Equatable {
        let start: Int
        let end: Int
    }

    static func range(
        anchorMinute: Int,
        currentMinute: Int,
        minimumDuration: Int,
        intervals: [PlanTimelineInterval],
        enforcesMinimumDuration: Bool = true
    ) -> MinuteRange? {
        let intervals = intervals.filter { !$0.isMemo }
        guard (0...1440).contains(anchorMinute), minimumDuration > 0,
              !intervals.contains(where: { $0.startMinute < anchorMinute && anchorMinute < $0.endMinute })
        else { return nil }
        let minimumDuration = enforcesMinimumDuration ? minimumDuration : 0
        if currentMinute >= anchorMinute {
            let desiredEnd = min(1440, max(currentMinute, anchorMinute + minimumDuration))
            let nextStart = intervals.filter { $0.startMinute >= anchorMinute }.map(\.startMinute).min() ?? 1440
            let end = min(desiredEnd, nextStart)
            guard end - anchorMinute >= minimumDuration else { return nil }
            return MinuteRange(start: anchorMinute, end: end)
        } else {
            let desiredStart = max(0, min(currentMinute, anchorMinute - minimumDuration))
            let previousEnd = intervals.filter { $0.endMinute <= anchorMinute }.map(\.endMinute).max() ?? 0
            let start = max(desiredStart, previousEnd)
            guard anchorMinute - start >= minimumDuration else { return nil }
            return MinuteRange(start: start, end: anchorMinute)
        }
    }
}

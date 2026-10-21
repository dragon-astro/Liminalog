import Foundation

struct PlanTimelineLayoutSlot {
    let column: Int
    let columnCount: Int
    var isMemo = false

    static func makeSlots(for intervals: [PlanTimelineInterval], overlayMainID: UUID?) -> [UUID: PlanTimelineLayoutSlot] {
        guard let overlayMainID, intervals.contains(where: { $0.id == overlayMainID && !$0.isMemo }) else {
            return makeSlots(for: intervals)
        }
        var slots = makeSlots(for: intervals.filter { $0.id != overlayMainID })
        slots[overlayMainID] = PlanTimelineLayoutSlot(column: 0, columnCount: 1)
        return slots
    }

    static func makeSlots(for intervals: [PlanTimelineInterval]) -> [UUID: PlanTimelineLayoutSlot] {
        if intervals.contains(where: \.isMemo) {
            var result = makeSlots(for: intervals.filter { !$0.isMemo })
            // Memos share their own right-hand overlay; main cards keep their full width.
            for (id, slot) in makeSlots(for: intervals.filter(\.isMemo).map {
                var copy = $0; copy.isMemo = false; return copy
            }) {
                var memoSlot = slot; memoSlot.isMemo = true; result[id] = memoSlot
            }
            return result
        }
        let sorted = intervals.sorted {
            if $0.startMinute == $1.startMinute {
                return $0.endMinute < $1.endMinute
            }
            return $0.startMinute < $1.startMinute
        }
        var slots: [UUID: PlanTimelineLayoutSlot] = [:]
        var cluster: [PlanTimelineInterval] = []
        var clusterEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            let assigned = assignColumns(in: cluster)
            let columnCount = max(assigned.values.max() ?? 0, 0) + 1
            for item in cluster {
                slots[item.id] = PlanTimelineLayoutSlot(
                    column: assigned[item.id] ?? 0,
                    columnCount: columnCount
                )
            }
            cluster.removeAll()
            clusterEnd = 0
        }

        for interval in sorted {
            if cluster.isEmpty {
                cluster = [interval]
                clusterEnd = interval.endMinute
                continue
            }
            if interval.startMinute < clusterEnd {
                cluster.append(interval)
                clusterEnd = max(clusterEnd, interval.endMinute)
            } else {
                flushCluster()
                cluster = [interval]
                clusterEnd = interval.endMinute
            }
        }
        flushCluster()
        return slots
    }

    private static func assignColumns(in intervals: [PlanTimelineInterval]) -> [UUID: Int] {
        var columnEndMinutes: [Int] = []
        var result: [UUID: Int] = [:]
        for interval in intervals {
            if let reusableIndex = columnEndMinutes.firstIndex(where: { $0 <= interval.startMinute }) {
                result[interval.id] = reusableIndex
                columnEndMinutes[reusableIndex] = interval.endMinute
            } else {
                result[interval.id] = columnEndMinutes.count
                columnEndMinutes.append(interval.endMinute)
            }
        }
        return result
    }
}

import CoreGraphics
import Foundation

enum TimelineHourAxisMetrics {
    static let columnWidth: CGFloat = 32

    static func label(for hour: Int) -> String {
        String(min(23, max(0, hour)))
    }
}

struct TimelineAxisInterval: Equatable {
    let startMinute: Int
    let endMinute: Int
}

/// The interval-dependent portion of a timeline axis.
///
/// A render snapshot can reuse this profile while pinch zoom changes only the
/// base hour height. This keeps the resulting axis identical without scanning
/// every interval range for every magnification event.
struct TimelineAxisProfile: Equatable {
    fileprivate let minimumPixelsPerMinute: [CGFloat]

    init(
        intervals: [TimelineAxisInterval],
        minimumIntervalHeight: CGFloat
    ) {
        let safeMinimumHeight = minimumIntervalHeight.isFinite
            ? max(0, minimumIntervalHeight)
            : 0
        var minimumSlopes = Array(
            repeating: CGFloat.zero,
            count: TimelineAxisMap.minutesPerDay
        )

        for interval in intervals {
            let start = min(TimelineAxisMap.minutesPerDay, max(0, interval.startMinute))
            let end = min(TimelineAxisMap.minutesPerDay, max(start + 1, interval.endMinute))
            guard start < end else { continue }
            let requiredSlope = safeMinimumHeight / CGFloat(end - start)
            for minute in start..<end where requiredSlope > minimumSlopes[minute] {
                minimumSlopes[minute] = requiredSlope
            }
        }

        minimumPixelsPerMinute = minimumSlopes
    }
}

/// A monotonic, reversible minute-to-pixel map for a 24-hour timeline.
///
/// Each short interval raises the local pixels-per-minute slope just enough to
/// reach `minimumIntervalHeight`. Overlapping intervals share the same expanded
/// axis range, while consecutive intervals accumulate their required heights.
struct TimelineAxisMap: Equatable {
    static let minutesPerDay = 24 * 60

    private let minutePositions: [CGFloat]

    init(
        hourHeight: CGFloat,
        intervals: [TimelineAxisInterval],
        minimumIntervalHeight: CGFloat
    ) {
        self.init(
            hourHeight: hourHeight,
            profile: TimelineAxisProfile(
                intervals: intervals,
                minimumIntervalHeight: minimumIntervalHeight
            )
        )
    }

    init(hourHeight: CGFloat, profile: TimelineAxisProfile) {
        let safeHourHeight = hourHeight.isFinite && hourHeight > 0 ? hourHeight : 1
        let basePixelsPerMinute = safeHourHeight / 60
        var positions = Array(repeating: CGFloat.zero, count: Self.minutesPerDay + 1)
        for minute in 0..<Self.minutesPerDay {
            let localPixelsPerMinute = max(
                basePixelsPerMinute,
                profile.minimumPixelsPerMinute[minute]
            )
            positions[minute + 1] = positions[minute] + localPixelsPerMinute
        }
        minutePositions = positions
    }

    var contentHeight: CGFloat {
        minutePositions.last ?? 0
    }

    func y(forMinute minute: Int) -> CGFloat {
        minutePositions[min(Self.minutesPerDay, max(0, minute))]
    }

    func y(forMinute minute: CGFloat) -> CGFloat {
        guard minute.isFinite else { return 0 }
        let clamped = min(CGFloat(Self.minutesPerDay), max(0, minute))
        let lowerMinute = Int(clamped.rounded(.down))
        guard lowerMinute < Self.minutesPerDay else { return contentHeight }
        let fraction = clamped - CGFloat(lowerMinute)
        let lowerY = minutePositions[lowerMinute]
        let upperY = minutePositions[lowerMinute + 1]
        return lowerY + (upperY - lowerY) * fraction
    }

    func height(startMinute: Int, endMinute: Int) -> CGFloat {
        max(0, y(forMinute: endMinute) - y(forMinute: startMinute))
    }

    func minute(atY proposedY: CGFloat) -> CGFloat {
        guard proposedY.isFinite else { return 0 }
        let y = min(contentHeight, max(0, proposedY))
        guard y > 0 else { return 0 }
        guard y < contentHeight else { return CGFloat(Self.minutesPerDay) }

        var lower = 0
        var upper = Self.minutesPerDay
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if minutePositions[middle] <= y {
                lower = middle
            } else {
                upper = middle
            }
        }

        let lowerY = minutePositions[lower]
        let upperY = minutePositions[upper]
        let span = upperY - lowerY
        guard span > 0 else { return CGFloat(lower) }
        return CGFloat(lower) + (y - lowerY) / span
    }
}

/// Drag bookkeeping for a non-uniform timeline axis.
///
/// Like `TimelineDragSession`, this preserves a stable finger origin, snap
/// hysteresis, and saturation at scheduling boundaries. Pixel travel is
/// converted through the frozen axis captured when the gesture begins.
struct TimelineAxisDragSession: Equatable {
    static let hysteresisFraction = 0.15

    let startGlobalY: CGFloat
    let originalMinute: Int
    let axisMap: TimelineAxisMap

    private(set) var rawMinuteDelta: Double = 0
    private(set) var minuteDelta: Int = 0
    private var anchorGlobalY: CGFloat
    private var anchorMinute: Int
    private var precision: TimelineSnapPrecision?

    init(startGlobalY: CGFloat, originalMinute: Int, axisMap: TimelineAxisMap) {
        self.startGlobalY = startGlobalY
        self.originalMinute = originalMinute
        self.axisMap = axisMap
        self.anchorGlobalY = startGlobalY
        self.anchorMinute = originalMinute
    }

    mutating func update(
        currentGlobalY: CGFloat,
        precision newPrecision: TimelineSnapPrecision
    ) -> Int {
        let anchorY = axisMap.y(forMinute: anchorMinute)
        let targetMinute = axisMap.minute(atY: anchorY + currentGlobalY - anchorGlobalY)
        let raw = Double(targetMinute) - Double(originalMinute)
        rawMinuteDelta = raw

        let step = newPrecision.minutes
        if precision != newPrecision {
            precision = newPrecision
            minuteDelta = Self.nearestStep(to: raw, step: step)
            return minuteDelta
        }

        let candidate = Self.nearestStep(to: raw, step: step)
        guard candidate != minuteDelta else { return minuteDelta }
        let threshold = Double(step) * (0.5 + Self.hysteresisFraction)
        if candidate > minuteDelta,
           raw >= Double(minuteDelta) + threshold {
            minuteDelta = candidate
        } else if candidate < minuteDelta,
                  raw <= Double(minuteDelta) - threshold {
            minuteDelta = candidate
        }
        return minuteDelta
    }

    mutating func saturate(currentGlobalY: CGFloat, appliedMinuteDelta: Int) {
        guard currentGlobalY.isFinite else { return }
        anchorGlobalY = currentGlobalY
        anchorMinute = min(
            TimelineAxisMap.minutesPerDay,
            max(0, originalMinute + appliedMinuteDelta)
        )
        rawMinuteDelta = Double(appliedMinuteDelta)
        minuteDelta = appliedMinuteDelta
    }

    private static func nearestStep(to rawMinuteDelta: Double, step: Int) -> Int {
        guard rawMinuteDelta.isFinite, step > 0 else { return 0 }
        return Int((rawMinuteDelta / Double(step)).rounded()) * step
    }
}

import CoreGraphics
import Foundation

enum TimelineSnapPrecision: Int, CaseIterable, Identifiable {
    case quarterHour = 15
    case fiveMinutes = 5
    case oneMinute = 1
    case tenMinutes = 10
    case halfHour = 30

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    static let sliderOptions: [Self] = [.oneMinute, .fiveMinutes, .tenMinutes, .quarterHour, .halfHour]
    static let userDefaultsKey = "timeline.snapPrecisionMinutes"

    static func normalized(minutes: Int) -> Self {
        Self(rawValue: minutes) ?? .quarterHour
    }

    var shortLabel: String {
        "\(rawValue)"
    }

    var accessibilityLabel: String {
        "\(rawValue)分刻み"
    }
}

enum TimelineSnapPolicy {
    /// Aligns a drag result to the selected wall-clock minute grid.
    ///
    /// A zero delta intentionally preserves an off-grid original minute so a
    /// touch-down never moves the plan by itself. Once the drag advances by a
    /// snap step, the resulting clock time is rounded to the nearest clean
    /// boundary (for example, 29 + 5 becomes 35 rather than 34).
    static func alignedMinute(
        originalMinute: Int,
        relativeDelta: Int,
        precision: TimelineSnapPrecision
    ) -> Int {
        guard relativeDelta != 0 else { return originalMinute }
        let step = precision.minutes
        guard step > 0 else { return originalMinute + relativeDelta }
        let proposed = originalMinute + relativeDelta
        return Int((Double(proposed) / Double(step)).rounded()) * step
    }

    static func alignedDelta(
        originalMinute: Int,
        relativeDelta: Int,
        precision: TimelineSnapPrecision
    ) -> Int {
        alignedMinute(
            originalMinute: originalMinute,
            relativeDelta: relativeDelta,
            precision: precision
        ) - originalMinute
    }
}

/// Converts one drag sequence into a minute delta from a stable origin.
///
/// The origin and hour height are captured once. Every frame is derived from
/// the current global coordinate, then quantized exactly once. A small
/// hysteresis around each boundary prevents finger noise from alternating
/// between adjacent snap points. When scheduling reaches a hard boundary, the
/// caller can explicitly saturate the origin so unreachable pointer travel does
/// not accumulate and make the reverse gesture feel frozen.
struct TimelineDragSession: Equatable {
    static let hysteresisFraction = 0.15

    let startGlobalY: CGFloat
    let hourHeight: CGFloat

    private(set) var rawMinuteDelta: Double = 0
    private(set) var minuteDelta: Int = 0
    private var anchorGlobalY: CGFloat
    private var anchorMinuteDelta: Double = 0
    private var precision: TimelineSnapPrecision?

    init(startGlobalY: CGFloat, hourHeight: CGFloat) {
        self.startGlobalY = startGlobalY
        self.hourHeight = hourHeight
        self.anchorGlobalY = startGlobalY
    }

    mutating func update(
        currentGlobalY: CGFloat,
        precision newPrecision: TimelineSnapPrecision
    ) -> Int {
        let raw = anchorMinuteDelta + Self.rawMinuteDelta(
            startGlobalY: anchorGlobalY,
            currentGlobalY: currentGlobalY,
            hourHeight: hourHeight
        )
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

    /// Rebases only after the scheduler has clamped the requested delta to a
    /// reachable one. Normal drags continue to use their original fixed anchor.
    mutating func saturate(currentGlobalY: CGFloat, appliedMinuteDelta: Int) {
        guard currentGlobalY.isFinite else { return }
        anchorGlobalY = currentGlobalY
        anchorMinuteDelta = Double(appliedMinuteDelta)
        rawMinuteDelta = Double(appliedMinuteDelta)
        minuteDelta = appliedMinuteDelta
    }

    static func rawMinuteDelta(
        startGlobalY: CGFloat,
        currentGlobalY: CGFloat,
        hourHeight: CGFloat
    ) -> Double {
        guard startGlobalY.isFinite,
              currentGlobalY.isFinite,
              hourHeight.isFinite,
              hourHeight > 0
        else { return 0 }

        return Double((currentGlobalY - startGlobalY) / hourHeight * 60)
    }

    private static func nearestStep(to rawMinuteDelta: Double, step: Int) -> Int {
        guard rawMinuteDelta.isFinite, step > 0 else { return 0 }
        return Int((rawMinuteDelta / Double(step)).rounded()) * step
    }
}

struct TimelineResizeHitRegion: Equatable {
    let minX: CGFloat
    let width: CGFloat

    var maxX: CGFloat {
        minX + width
    }

    func contains(x: CGFloat) -> Bool {
        x >= minX && x <= maxX
    }
}

enum TimelineResizeHitPolicy {
    /// Keeps the interactive width on the visible grip and inside its plan
    /// column, so a resize handle never steals a neighboring block-body drag.
    static func horizontalRegion(
        blockMinX: CGFloat,
        blockWidth: CGFloat,
        timelineMinX: CGFloat,
        timelineMaxX: CGFloat,
        preferredGripWidth: CGFloat
    ) -> TimelineResizeHitRegion {
        let safeTimelineMin = min(timelineMinX, timelineMaxX)
        let safeTimelineMax = max(timelineMinX, timelineMaxX)
        let safeBlockMin = max(safeTimelineMin, blockMinX)
        let safeBlockMax = min(safeTimelineMax, blockMinX + max(0, blockWidth))
        let availableWidth = max(0, safeBlockMax - safeBlockMin)
        let width = min(availableWidth, max(0, preferredGripWidth))
        let centeredX = blockMinX + max(0, blockWidth) / 2 - width / 2
        let maxOrigin = max(safeTimelineMin, safeTimelineMax - width)
        let origin = min(max(centeredX, safeTimelineMin), maxOrigin)
        let clampedOrigin = min(max(origin, safeBlockMin), max(safeBlockMin, safeBlockMax - width))
        return TimelineResizeHitRegion(minX: clampedOrigin, width: width)
    }
}

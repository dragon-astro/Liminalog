import CoreGraphics
import Foundation

enum TimelineBarLayout {
    static func xOffset(for target: Date, dayStart: Date, dayEnd: Date, width: CGFloat) -> CGFloat {
        guard width > 0, dayEnd > dayStart else { return 0 }
        let clipped = min(max(target, dayStart), dayEnd)
        let ratio = clipped.timeIntervalSince(dayStart) / dayEnd.timeIntervalSince(dayStart)
        return max(0, min(width, width * ratio))
    }

    static func segmentWidth(
        start: Date,
        end: Date,
        dayStart: Date,
        dayEnd: Date,
        width: CGFloat
    ) -> CGFloat {
        guard width > 0, dayEnd > dayStart else { return 0 }
        let clippedStart = min(max(start, dayStart), dayEnd)
        let clippedEnd = min(max(end, dayStart), dayEnd)
        let duration = max(clippedEnd.timeIntervalSince(clippedStart), 60)
        let ratio = duration / dayEnd.timeIntervalSince(dayStart)
        return max(width * ratio, 1)
    }

    static func shouldShowIcon(duration: TimeInterval, width: CGFloat) -> Bool {
        duration >= 15 * 60 && width >= 24
    }
}

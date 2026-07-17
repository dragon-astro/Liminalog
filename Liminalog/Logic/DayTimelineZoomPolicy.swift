import CoreGraphics
import Foundation

enum DayTimelineZoomPolicy {
    static let supportedScales: [CGFloat] = [0.75, 1, 1.5, 2]
    static let defaultScale: CGFloat = 1
    static let baseHourHeight: CGFloat = 38
    static let userDefaultsKey = "timeline.day.hourScale"

    private static let minutesPerDay: CGFloat = 24 * 60

    static func normalizedScale(_ raw: Double) -> CGFloat {
        guard raw.isFinite, raw > 0 else { return defaultScale }

        let proposed = CGFloat(raw)
        return supportedScales.dropFirst().reduce(supportedScales[0]) { nearest, candidate in
            abs(candidate - proposed) < abs(nearest - proposed) ? candidate : nearest
        }
    }

    static func magnifiedScale(baseScale: CGFloat, magnification: CGFloat) -> CGFloat {
        let normalizedBase = snappedScale(baseScale)
        guard magnification.isFinite, magnification > 0 else { return normalizedBase }

        return min(
            supportedScales.last ?? defaultScale,
            max(supportedScales.first ?? defaultScale, normalizedBase * magnification)
        )
    }

    static func snappedScale(_ proposed: CGFloat) -> CGFloat {
        normalizedScale(Double(proposed))
    }

    static func hourHeight(for scale: CGFloat) -> CGFloat {
        let safeScale: CGFloat
        if scale.isFinite, scale > 0 {
            safeScale = min(
                supportedScales.last ?? defaultScale,
                max(supportedScales.first ?? defaultScale, scale)
            )
        } else {
            safeScale = defaultScale
        }
        return baseHourHeight * safeScale
    }

    /// Returns the minute at the vertical center of the viewport.
    ///
    /// `visibleMinY` is the content origin measured in the scroll view coordinate
    /// space (zero at the top and negative after scrolling). `timelineTopInset`
    /// is excluded from the hour-axis calculation.
    static func centerMinute(
        visibleMinY: CGFloat,
        viewportHeight: CGFloat,
        hourHeight: CGFloat,
        timelineTopInset: CGFloat = 0
    ) -> CGFloat {
        let safeMinY = visibleMinY.isFinite ? visibleMinY : 0
        let safeViewportHeight = viewportHeight.isFinite ? max(0, viewportHeight) : 0
        let safeHourHeight = validHourHeight(hourHeight)
        let safeTopInset = timelineTopInset.isFinite ? max(0, timelineTopInset) : 0
        let scrollY = max(0, -safeMinY)
        let minute = (scrollY + safeViewportHeight / 2 - safeTopInset) / safeHourHeight * 60
        return min(minutesPerDay, max(0, minute))
    }

    /// Returns the scroll offset that keeps `centerMinute` at the viewport center.
    static func scrollY(
        preservingCenterMinute centerMinute: CGFloat,
        viewportHeight: CGFloat,
        hourHeight: CGFloat,
        contentHeight: CGFloat,
        timelineTopInset: CGFloat = 0
    ) -> CGFloat {
        let safeCenterMinute = centerMinute.isFinite
            ? min(minutesPerDay, max(0, centerMinute))
            : 0
        let safeViewportHeight = viewportHeight.isFinite ? max(0, viewportHeight) : 0
        let safeHourHeight = validHourHeight(hourHeight)
        let safeContentHeight = contentHeight.isFinite ? max(0, contentHeight) : 0
        let safeTopInset = timelineTopInset.isFinite ? max(0, timelineTopInset) : 0

        let proposed = safeTopInset
            + safeCenterMinute / 60 * safeHourHeight
            - safeViewportHeight / 2
        let maximum = max(0, safeContentHeight - safeViewportHeight)
        return min(maximum, max(0, proposed))
    }

    static func load(from defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: userDefaultsKey) != nil else { return defaultScale }
        return normalizedScale(defaults.double(forKey: userDefaultsKey))
    }

    static func save(_ scale: CGFloat, to defaults: UserDefaults = .standard) {
        defaults.set(Double(snappedScale(scale)), forKey: userDefaultsKey)
    }

    private static func validHourHeight(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite, proposed > 0 else { return baseHourHeight }
        return proposed
    }
}

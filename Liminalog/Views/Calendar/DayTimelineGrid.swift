import SwiftUI

/// Shared by the real day timeline and the virtual day preset editor.
struct DayTimelineGrid: View {
    @Environment(\.colorScheme) private var colorScheme
    let axisMap: TimelineAxisMap
    let topInset: CGFloat
    let contentHeight: CGFloat
    let colorStyle: EditablePlanTimelineColorStyle

    var body: some View {
        let colors = DayTimelineGridPalette(colorScheme: colorScheme, style: colorStyle)
        let hourWidth = TimelineHourAxisMetrics.columnWidth
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors.background))
            context.fill(
                Path(CGRect(x: 0, y: 0, width: hourWidth, height: contentHeight)),
                with: .color(colors.hourColumn)
            )
            context.fill(
                Path(CGRect(x: hourWidth, y: 0, width: 1, height: contentHeight)),
                with: .color(colors.primaryLine)
            )
            let gridWidth = max(0, size.width - hourWidth)
            for hour in 0...24 {
                let rawY = topInset + axisMap.y(forMinute: hour * 60)
                let tickY = min(max(0.5, rawY), max(0.5, contentHeight - 0.5))
                context.fill(
                    Path(CGRect(x: hourWidth, y: tickY - 0.5, width: gridWidth, height: 1)),
                    with: .color(colors.primaryLine)
                )
                guard hour < 24 else { continue }
                let secondaryY = topInset + axisMap.y(forMinute: hour * 60 + 30)
                context.fill(
                    Path(CGRect(x: hourWidth, y: secondaryY - 0.5, width: gridWidth, height: 1)),
                    with: .color(colors.secondaryLine)
                )
                context.draw(
                    Text(TimelineHourAxisMetrics.label(for: hour))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(colors.timeText),
                    at: CGPoint(x: hourWidth - 9, y: min(max(7, tickY), max(7, contentHeight - 7))),
                    anchor: .trailing
                )
            }
        }
    }
}

struct DayTimelineGridPalette {
    let colorScheme: ColorScheme
    let style: EditablePlanTimelineColorStyle

    var background: Color {
        guard colorScheme == .dark else { return Color(red: 0.985, green: 0.985, blue: 0.98) }
        return style == .calendarGrid
            ? Color(red: 0.035, green: 0.037, blue: 0.043)
            : Color(red: 0.125, green: 0.129, blue: 0.145)
    }
    var hourColumn: Color {
        guard colorScheme == .dark else { return Color(red: 0.955, green: 0.955, blue: 0.945) }
        return style == .calendarGrid
            ? Color(red: 0.05, green: 0.052, blue: 0.06)
            : Color(red: 0.105, green: 0.109, blue: 0.125)
    }
    var primaryLine: Color { colorScheme == .dark ? .white.opacity(0.20) : .black.opacity(0.16) }
    var secondaryLine: Color { colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07) }
    var timeText: Color { colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.52) }
    var outerStroke: Color { colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12) }
}

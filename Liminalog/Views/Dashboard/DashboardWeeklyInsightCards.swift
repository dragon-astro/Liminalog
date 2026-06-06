import SwiftUI

struct DashboardPeriodDeltaCard: View {
    let period: DashboardPeriod
    let summary: DashboardPeriodDeltaSummary

    private var rows: [DashboardDeltaDisplayRow] {
        [
            DashboardDeltaDisplayRow(
                title: "平均スコア",
                metric: summary.score,
                systemImage: "star.fill",
                tint: Color(hex: "#F2994A"),
                currentText: "\(Int(summary.score.current.rounded()))pt",
                deltaText: formatDashboardSignedScore(summary.score.delta)
            ),
            DashboardDeltaDisplayRow(
                title: "実績時間",
                metric: summary.recordedDuration,
                systemImage: "clock.fill",
                tint: LiminalTheme.accent,
                currentText: formatDashboardDuration(summary.recordedDuration.current),
                deltaText: formatDashboardSignedDuration(summary.recordedDuration.delta)
            ),
            DashboardDeltaDisplayRow(
                title: "予定時間",
                metric: summary.plannedDuration,
                systemImage: "calendar",
                tint: Color(hex: "#2F80ED"),
                currentText: formatDashboardDuration(summary.plannedDuration.current),
                deltaText: formatDashboardSignedDuration(summary.plannedDuration.delta)
            ),
            DashboardDeltaDisplayRow(
                title: "一致時間",
                metric: summary.matchedDuration,
                systemImage: "target",
                tint: Color(hex: "#27AE60"),
                currentText: formatDashboardDuration(summary.matchedDuration.current),
                deltaText: formatDashboardSignedDuration(summary.matchedDuration.delta)
            ),
            DashboardDeltaDisplayRow(
                title: "スコア日",
                metric: summary.scoredDayCount,
                systemImage: "calendar.badge.checkmark",
                tint: Color(hex: "#6C5CE7"),
                currentText: "\(Int(summary.scoredDayCount.current.rounded()))日",
                deltaText: formatDashboardSignedCount(summary.scoredDayCount.delta)
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: period.comparisonTitle, systemImage: "arrow.left.arrow.right", tint: Color(hex: "#F2994A"))

            VStack(spacing: 12) {
                ForEach(rows) { row in
                    DashboardDeltaMetricRow(period: period, row: row)
                }
            }
        }
        .dashboardCard()
    }
}

private extension DashboardPeriod {
    var comparisonTitle: String {
        switch self {
        case .today:
            "前日比"
        case .week:
            "先週比"
        case .month:
            "先月比"
        case .year:
            "前年比"
        }
    }

    var previousPeriodLabel: String {
        switch self {
        case .today:
            "前日"
        case .week:
            "前週"
        case .month:
            "前月"
        case .year:
            "前年"
        }
    }

    var missingPreviousPeriodText: String {
        "\(previousPeriodLabel)なし"
    }
}

struct DashboardDeltaDisplayRow: Identifiable {
    let title: String
    let metric: DashboardDeltaMetric
    let systemImage: String
    let tint: Color
    let currentText: String
    let deltaText: String

    var id: String { title }

    func currentText(for value: Double) -> String {
        switch title {
        case "平均スコア":
            return "\(Int(value.rounded()))pt"
        case "スコア日":
            return "\(Int(value.rounded()))日"
        default:
            return formatDashboardDuration(value)
        }
    }

    func deltaText(for value: Double) -> String {
        switch title {
        case "平均スコア":
            return formatDashboardSignedScore(value)
        case "スコア日":
            return formatDashboardSignedCount(value)
        default:
            return formatDashboardSignedDuration(value)
        }
    }
}

struct DashboardDeltaMetricRow: View {
    let period: DashboardPeriod
    let row: DashboardDeltaDisplayRow

    private var deltaColor: Color {
        if row.metric.isIncrease {
            return Color(hex: "#27AE60")
        }
        if row.metric.isDecrease {
            return Color(hex: "#EB5757")
        }
        return LiminalTheme.secondaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: row.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(row.tint)
                    .frame(width: 20, height: 20)
                    .background(row.tint.opacity(0.12), in: Circle())

                Text(row.title)
                    .font(.caption.weight(.bold))

                Spacer()

                Text(row.currentText)
                    .dashboardCountUp(value: row.metric.current) {
                        row.currentText(for: $0)
                    }
                    .font(.caption.weight(.bold).monospacedDigit())

                Text(row.deltaText)
                    .dashboardCountUp(value: row.metric.delta) {
                        row.deltaText(for: $0)
                    }
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(deltaColor)
            }

            DashboardDeltaBar(metric: row.metric, tint: deltaColor)
                .frame(height: 18)

            HStack {
                Text("\(period.previousPeriodLabel) \(formatDashboardDeltaBaseline(row.metric.previous, title: row.title))")
                Spacer()
                Text(formatDashboardPercentChange(row.metric.percentChange, missingText: period.missingPreviousPeriodText))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(LiminalTheme.secondaryText)
        }
    }
}

struct DashboardDeltaBar: View {
    let metric: DashboardDeltaMetric
    let tint: Color

    private var ratio: Double {
        let basis = max(abs(metric.current), abs(metric.previous), 1)
        return min(abs(metric.delta) / basis, 1)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text("±0")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(LiminalTheme.secondaryText.opacity(0.78))
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            GeometryReader { proxy in
                let halfWidth = max(0, (proxy.size.width - 2) / 2)
                HStack(spacing: 0) {
                    ZStack(alignment: .trailing) {
                        Capsule()
                            .fill(LiminalTheme.elevated)
                        if metric.isDecrease {
                            Capsule()
                                .fill(tint)
                                .frame(width: halfWidth * ratio)
                        }
                    }
                    .frame(width: halfWidth)

                    Rectangle()
                        .fill(LiminalTheme.divider.opacity(0.35))
                        .frame(width: 2)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LiminalTheme.elevated)
                        if metric.isIncrease {
                            Capsule()
                                .fill(tint)
                                .frame(width: halfWidth * ratio)
                        }
                    }
                    .frame(width: halfWidth)
                }
            }
            .frame(height: 9)
        }
    }
}

private func formatDashboardSignedScore(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    if rounded > 0 {
        return "+\(rounded)pt"
    }
    if rounded < 0 {
        return "\(rounded)pt"
    }
    return "±0pt"
}

private func formatDashboardSignedDuration(_ seconds: Double) -> String {
    let minutes = Int((abs(seconds) / 60).rounded())
    let body: String
    if minutes < 60 {
        body = "\(minutes)分"
    } else {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        body = remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
    }

    if seconds > 0 {
        return "+\(body)"
    }
    if seconds < 0 {
        return "-\(body)"
    }
    return "±0分"
}

private func formatDashboardSignedCount(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    if rounded > 0 {
        return "+\(rounded)日"
    }
    if rounded < 0 {
        return "\(rounded)日"
    }
    return "±0日"
}

private func formatDashboardPercentChange(_ value: Double?, missingText: String) -> String {
    guard let value else { return missingText }
    let percent = Int((value * 100).rounded())
    if percent > 0 {
        return "+\(percent)%"
    }
    if percent < 0 {
        return "\(percent)%"
    }
    return "±0%"
}

private func formatDashboardDeltaBaseline(_ value: Double, title: String) -> String {
    switch title {
    case "平均スコア":
        return "\(Int(value.rounded()))pt"
    case "スコア日":
        return "\(Int(value.rounded()))日"
    default:
        return formatDashboardDuration(value)
    }
}

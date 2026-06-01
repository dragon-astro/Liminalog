import SwiftUI

struct DashboardTimeOfDayTrendCard: View {
    let summary: DashboardTimeOfDaySummary

    private var dominantText: String {
        guard summary.totalDuration > 0, let dominant = summary.dominantSegment else {
            return "記録待ち"
        }
        return "\(dominant.label)に寄っています"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "時間帯別傾向", systemImage: "clock.fill", tint: Color(hex: "#00A8A8"))

            if summary.totalDuration <= 0 {
                EmptyStatText(text: "記録を始めると朝・昼・夜の比率が見えます")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: summary.dominantSegment?.systemImage ?? "clock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(summary.dominantSegment?.dashboardColor ?? Color.secondary)
                        .frame(width: 28, height: 28)
                        .background((summary.dominantSegment?.dashboardColor ?? Color.secondary).opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dominantText)
                            .font(.subheadline.weight(.bold))
                        Text(formatDashboardDuration(summary.totalDuration))
                            .dashboardCountUp(value: summary.totalDuration, formatter: formatDashboardDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    ForEach(summary.rows) { row in
                        DashboardTimeOfDayRowView(row: row)
                    }
                }
            }
        }
        .dashboardCard()
    }
}

struct DashboardTimeOfDayRowView: View {
    let row: DashboardTimeOfDayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: row.segment.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(row.segment.dashboardColor)
                    .frame(width: 20, height: 20)
                    .background(row.segment.dashboardColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.segment.label)
                        .font(.caption.weight(.bold))
                    Text(row.segment.rangeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatDashboardDuration(row.duration))
                        .dashboardCountUp(value: row.duration, formatter: formatDashboardDuration)
                        .font(.caption.weight(.bold).monospacedDigit())
                    Text("\(Int((row.ratio * 100).rounded()))%")
                        .dashboardCountUp(value: row.ratio * 100) {
                            "\(Int($0.rounded()))%"
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(row.segment.dashboardColor)
                            .frame(width: proxy.size.width * min(max(row.ratio, 0), 1))
                    }
            }
            .frame(height: 8)
        }
    }
}

struct DashboardPeriodDeltaCard: View {
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
                tint: Color.accentColor,
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
            DashboardSectionHeader(title: "先週比", systemImage: "arrow.left.arrow.right", tint: Color(hex: "#F2994A"))

            VStack(spacing: 12) {
                ForEach(rows) { row in
                    DashboardDeltaMetricRow(row: row)
                }
            }
        }
        .dashboardCard()
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
    let row: DashboardDeltaDisplayRow

    private var deltaColor: Color {
        if row.metric.isIncrease {
            return Color(hex: "#27AE60")
        }
        if row.metric.isDecrease {
            return Color(hex: "#EB5757")
        }
        return Color.secondary
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
                .frame(height: 9)

            HStack {
                Text("前週 \(formatDashboardDeltaBaseline(row.metric.previous, title: row.title))")
                Spacer()
                Text(formatDashboardPercentChange(row.metric.percentChange))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
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
        GeometryReader { proxy in
            let halfWidth = max(0, (proxy.size.width - 2) / 2)
            HStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                    if metric.isDecrease {
                        Capsule()
                            .fill(tint)
                            .frame(width: halfWidth * ratio)
                    }
                }
                .frame(width: halfWidth)

                Rectangle()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(width: 2)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                    if metric.isIncrease {
                        Capsule()
                            .fill(tint)
                            .frame(width: halfWidth * ratio)
                    }
                }
                .frame(width: halfWidth)
            }
        }
    }
}

private extension DashboardTimeOfDay {
    var dashboardColor: Color {
        switch self {
        case .morning:
            return Color(hex: "#F2C94C")
        case .afternoon:
            return Color(hex: "#2F80ED")
        case .night:
            return Color(hex: "#6C5CE7")
        }
    }

    var systemImage: String {
        switch self {
        case .morning:
            return "sunrise.fill"
        case .afternoon:
            return "sun.max.fill"
        case .night:
            return "moon.stars.fill"
        }
    }

    var rangeText: String {
        switch self {
        case .morning:
            return "5-12"
        case .afternoon:
            return "12-18"
        case .night:
            return "18-5"
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

private func formatDashboardPercentChange(_ value: Double?) -> String {
    guard let value else { return "前週なし" }
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

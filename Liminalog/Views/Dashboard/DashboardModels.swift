import SwiftUI

struct DashboardScoreAggregate {
    let totalScore: Double
    let categoryScore: Double
    let timelineScore: Double
    let plannedDuration: TimeInterval
    let recordedDuration: TimeInterval
    let matchedDuration: TimeInterval
    let scoredDayCount: Int

    init(summaries: [ScoreSummary]) {
        let scored = summaries.filter { $0.plannedDuration > 0 }
        scoredDayCount = scored.count
        if scored.isEmpty {
            totalScore = 0
            categoryScore = 0
            timelineScore = 0
        } else {
            totalScore = scored.map(\.totalScore).reduce(0, +) / Double(scored.count)
            categoryScore = scored.map(\.categoryScore).reduce(0, +) / Double(scored.count)
            timelineScore = scored.map(\.timelineScore).reduce(0, +) / Double(scored.count)
        }
        plannedDuration = summaries.reduce(0) { $0 + $1.plannedDuration }
        recordedDuration = summaries.reduce(0) { $0 + $1.recordedDuration }
        matchedDuration = summaries.reduce(0) { $0 + $1.matchedDuration }
    }

    var hasScore: Bool {
        scoredDayCount > 0
    }

    var gradeText: String {
        guard hasScore else { return "これから育つ" }
        switch totalScore {
        case 90...:
            return "かなり予定通り"
        case 75..<90:
            return "いい感じ"
        case 60..<75:
            return "合格ライン"
        case 30..<60:
            return "そこそこ"
        default:
            return "伸びしろあり"
        }
    }

    var scoreFormulaText: String {
        let categoryWeight = Int((ScoreCalculator.categoryWeight * 100).rounded())
        let timelineWeight = Int((ScoreCalculator.timelineWeight * 100).rounded())
        return "計算式: カテゴリ\(Int(categoryScore.rounded()))%×\(categoryWeight)% + 時間軸\(Int(timelineScore.rounded()))%×\(timelineWeight)% = \(Int(totalScore.rounded()))pt"
    }
}

struct DashboardCategoryStat: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let color: Color
    let duration: TimeInterval

    static func stats(from chapters: [Chapter], now: Date = Date()) -> [DashboardCategoryStat] {
        let grouped = Dictionary(grouping: chapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            return (category, max(0, (chapter.endTime ?? now).timeIntervalSince(chapter.startTime)))
        }, by: { $0.0.id })

        return grouped.compactMap { id, values in
            guard let category = values.first?.0 else { return nil }
            return DashboardCategoryStat(
                id: id,
                name: category.name,
                icon: category.icon ?? "circle.fill",
                color: category.displayColor,
                duration: values.reduce(0) { $0 + $1.1 }
            )
        }
        .sorted { $0.duration > $1.duration }
    }
}

struct HourStat: Identifiable {
    let hour: Int
    let duration: TimeInterval
    let segments: [HourRhythmSegment]

    var id: Int { hour }

    static func stats(
        from chapters: [Chapter],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [HourStat] {
        var durationsByHourAndCategory: [Int: [UUID?: (category: Category?, duration: TimeInterval)]] = [:]

        for chapter in chapters {
            let start = chapter.startTime
            let end = max(chapter.endTime ?? now, start)
            guard end > start else { continue }

            var cursor = calendar.dateInterval(of: .hour, for: start)?.start ?? start
            while cursor < end {
                guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
                let overlapStart = max(start, cursor)
                let overlapEnd = min(end, nextHour)
                let overlapDuration = max(0, overlapEnd.timeIntervalSince(overlapStart))
                if overlapDuration > 0 {
                    let hour = calendar.component(.hour, from: cursor)
                    let category = chapter.category
                    let categoryID = category?.id
                    let current = durationsByHourAndCategory[hour, default: [:]][categoryID]
                    durationsByHourAndCategory[hour, default: [:]][categoryID] = (
                        category: current?.category ?? category,
                        duration: (current?.duration ?? 0) + overlapDuration
                    )
                }
                cursor = nextHour
            }
        }

        return (0..<24).map { hour in
            let segments = (durationsByHourAndCategory[hour] ?? [:])
                .map { entry in
                    HourRhythmSegment(
                        category: entry.value.category,
                        duration: entry.value.duration
                    )
                }
                .sorted { $0.duration > $1.duration }
            return HourStat(
                hour: hour,
                duration: segments.reduce(0) { $0 + $1.duration },
                segments: segments
            )
        }
    }
}

struct HourRhythmSegment: Identifiable {
    let category: Category?
    let duration: TimeInterval

    var id: String {
        category?.id.uuidString ?? "uncategorized"
    }

    var color: Color {
        category?.displayColor ?? LiminalTheme.elevated
    }
}

enum DashboardScorePalette {
    static func color(for score: Double, hasScore: Bool) -> Color {
        guard hasScore else { return LiminalTheme.secondaryText }
        switch score {
        case 90...: return Color(hex: "#27AE60")
        case 75..<90: return Color(hex: "#2F80ED")
        case 60..<75: return Color(hex: "#F2994A")
        default: return Color(hex: "#EB5757")
        }
    }
}

func formatDashboardDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes < 60 {
        return "\(minutes)分"
    }
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
}

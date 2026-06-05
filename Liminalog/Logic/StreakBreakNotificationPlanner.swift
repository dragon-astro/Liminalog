import Foundation

struct StreakBreakNotificationPlan: Equatable {
    static let identifier = "streak-break-warning"

    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

enum StreakBreakNotificationPlanner {
    static let passingScore = StreakRules.passingScore

    static func makePlan(
        now: Date,
        todaySummary: ScoreSummary,
        currentStreakDays: Int,
        calendar: Calendar = .japanese,
        warningHour: Int = 21,
        warningMinute: Int = 0,
        latestWarningHour: Int = 23,
        latestWarningMinute: Int = 30
    ) -> StreakBreakNotificationPlan? {
        guard currentStreakDays > 0,
              todaySummary.plannedDuration > 0,
              todaySummary.totalScore < passingScore
        else { return nil }

        let boundary = DayBoundary(date: now, calendar: calendar)
        guard now < boundary.dayEnd,
              let warningDate = calendar.date(
                bySettingHour: warningHour,
                minute: warningMinute,
                second: 0,
                of: now
              ),
              let latestWarningDate = calendar.date(
                bySettingHour: latestWarningHour,
                minute: latestWarningMinute,
                second: 0,
                of: now
              ),
              now < latestWarningDate
        else { return nil }

        let fireDate = now < warningDate ? warningDate : now.addingTimeInterval(60)
        guard fireDate < boundary.dayEnd,
              fireDate <= latestWarningDate
        else { return nil }

        let currentScore = Int(todaySummary.totalScore.rounded(.down))
        return StreakBreakNotificationPlan(
            identifier: StreakBreakNotificationPlan.identifier,
            title: "ストリークが途切れそうです",
            body: "現在 \(currentScore) 点。\(currentStreakDays)日ストリークを守るなら、今日のスコアを30点まで戻しましょう。",
            fireDate: fireDate
        )
    }
}

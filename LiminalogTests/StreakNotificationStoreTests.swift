import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
@Suite("StreakNotificationStore")
struct StreakNotificationStoreTests {
    @Test("前日までのストリークがあり今日60点未満なら夜の警告を差し替える")
    func schedulesWarningWhenCurrentStreakCouldBreak() async throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let scheduler = FakeStreakNotificationScheduler(authorization: .authorized)
        let store = StreakNotificationStore(
            modelContext: context,
            scheduler: scheduler,
            calendar: calendar
        )
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 20)))
        let category = Liminalog.Category(name: "作業", colorHex: "#2F80ED")
        context.insert(category)

        insertScoredDay(
            day: try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))),
            category: category,
            context: context,
            calendar: calendar
        )
        insertPlanOnlyDay(
            day: now,
            category: category,
            context: context,
            calendar: calendar
        )

        await store.refreshStreakBreakWarning(now: now)

        let lastReplacement = try #require(scheduler.replacedPlans.last)
        let plan = try #require(lastReplacement)
        #expect(plan.identifier == StreakBreakNotificationPlan.identifier)
        #expect(calendar.component(.hour, from: plan.fireDate) == 21)
        #expect(plan.body.contains("1日ストリーク"))
    }

    @Test("通知が未許可なら保留中のストリーク警告を消す")
    func clearsWarningWhenNotificationsAreNotAuthorized() async throws {
        let container = try TestModelContainer.make()
        let scheduler = FakeStreakNotificationScheduler(authorization: .denied)
        let store = StreakNotificationStore(
            modelContext: container.mainContext,
            scheduler: scheduler,
            calendar: .liminalogTest
        )

        await store.refreshStreakBreakWarning(now: Date())

        #expect(scheduler.replacedPlans.count == 1)
        #expect(scheduler.replacedPlans[0] == nil)
    }

    @Test("今日すでに60点以上なら警告しない")
    func doesNotWarnAfterPassingToday() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 20)))
        let firePlan = StreakBreakNotificationPlanner.makePlan(
            now: now,
            todaySummary: summary(totalScore: 75, plannedDuration: 3_600),
            currentStreakDays: 3,
            calendar: calendar
        )

        #expect(firePlan == nil)
    }

    @Test("21時を過ぎていればすぐ警告し、遅すぎる時間は警告しない")
    func warningDateMovesNearNowAfterWarningHour() throws {
        let calendar = Calendar.liminalogTest
        let afterWarningHour = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 22)))
        let tooLate = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 23, minute: 45)))

        let nearNowPlan = try #require(StreakBreakNotificationPlanner.makePlan(
            now: afterWarningHour,
            todaySummary: summary(totalScore: 42, plannedDuration: 3_600),
            currentStreakDays: 3,
            calendar: calendar
        ))
        let tooLatePlan = StreakBreakNotificationPlanner.makePlan(
            now: tooLate,
            todaySummary: summary(totalScore: 42, plannedDuration: 3_600),
            currentStreakDays: 3,
            calendar: calendar
        )

        #expect(nearNowPlan.fireDate == afterWarningHour.addingTimeInterval(60))
        #expect(tooLatePlan == nil)
    }

    private func insertScoredDay(
        day: Date,
        category: Liminalog.Category,
        context: ModelContext,
        calendar: Calendar
    ) {
        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day) ?? start.addingTimeInterval(3_600)
        context.insert(PlanBlock(category: category, title: "予定", startTime: start, endTime: end))
        let chapter = Chapter(category: category, startTime: start)
        chapter.endTime = end
        context.insert(chapter)
    }

    private func insertPlanOnlyDay(
        day: Date,
        category: Liminalog.Category,
        context: ModelContext,
        calendar: Calendar
    ) {
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? start.addingTimeInterval(3_600)
        context.insert(PlanBlock(category: category, title: "予定", startTime: start, endTime: end))
    }

    private func summary(totalScore: Double, plannedDuration: TimeInterval) -> ScoreSummary {
        ScoreSummary(
            date: Date(),
            categoryScore: totalScore,
            timelineScore: totalScore,
            totalScore: totalScore,
            plannedDuration: plannedDuration,
            recordedDuration: 0,
            matchedDuration: 0
        )
    }
}

@MainActor
private final class FakeStreakNotificationScheduler: StreakNotificationScheduling {
    let authorization: LiminalNotificationAuthorization
    private(set) var replacedPlans: [StreakBreakNotificationPlan?] = []

    init(authorization: LiminalNotificationAuthorization) {
        self.authorization = authorization
    }

    func authorizationStatus() async -> LiminalNotificationAuthorization {
        authorization
    }

    func replacePendingStreakBreakNotification(with plan: StreakBreakNotificationPlan?) async throws {
        replacedPlans.append(plan)
    }
}

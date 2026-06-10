import Foundation
import SwiftData
import UserNotifications

enum LiminalNotificationAuthorization: Equatable {
    case authorized
    case provisional
    case ephemeral
    case denied
    case notDetermined

    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .denied, .notDetermined:
            false
        }
    }
}

protocol StreakNotificationScheduling {
    func authorizationStatus() async -> LiminalNotificationAuthorization
    func requestAuthorization() async -> Bool
    func replacePendingStreakBreakNotification(with plan: StreakBreakNotificationPlan?) async throws
}

final class UserNotificationStreakScheduler: StreakNotificationScheduling {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .japanese
    ) {
        self.center = center
        self.calendar = calendar
    }

    func authorizationStatus() async -> LiminalNotificationAuthorization {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("Liminalog: notification authorization request failed: \(String(describing: error))")
            return false
        }
    }

    func replacePendingStreakBreakNotification(with plan: StreakBreakNotificationPlan?) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [StreakBreakNotificationPlan.identifier])
        guard let plan else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = [
            "liminalogRoute": "profile",
            "liminalogDeepLink": "liminalog://profile"
        ]

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: plan.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}

@MainActor
final class StreakNotificationStore {
    /// ストリーク通知のユーザー有効フラグ（設定のトグルと共有）。既定はオフ＝明示的オプトイン。
    nonisolated static let streakReminderEnabledKey = "settings.notifications.streakReminderEnabled"
    nonisolated static var streakReminderEnabled: Bool {
        UserDefaults.standard.bool(forKey: streakReminderEnabledKey)
    }

    private let modelContext: ModelContext
    private let scheduler: any StreakNotificationScheduling
    private let calendar: Calendar
    private let isStreakReminderEnabled: () -> Bool

    init(
        modelContext: ModelContext,
        scheduler: (any StreakNotificationScheduling)? = nil,
        calendar: Calendar = .japanese,
        isStreakReminderEnabled: @escaping () -> Bool = { StreakNotificationStore.streakReminderEnabled }
    ) {
        self.modelContext = modelContext
        self.scheduler = scheduler ?? UserNotificationStreakScheduler()
        self.calendar = calendar
        self.isStreakReminderEnabled = isStreakReminderEnabled
    }

    /// 通知許可をリクエストし、許可されたら true。
    func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    /// 現在の通知許可状態。
    func authorizationStatus() async -> LiminalNotificationAuthorization {
        await scheduler.authorizationStatus()
    }

    func refreshStreakBreakWarning(now: Date = Date()) async {
        guard isStreakReminderEnabled() else {
            await replacePendingNotification(with: nil)
            return
        }

        let authorization = await scheduler.authorizationStatus()
        guard authorization.allowsScheduling else {
            await replacePendingNotification(with: nil)
            return
        }

        guard let todaySummary = ScoreSnapshotLoader.summaryIfAvailable(
            on: now,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        ) else {
            NSLog("Liminalog: skipped streak notification refresh because today's score could not be loaded")
            return
        }
        guard let priorStreakDays = streakCountEndingYesterday(from: now) else {
            NSLog("Liminalog: skipped streak notification refresh because streak scores could not be loaded")
            return
        }
        let plan = StreakBreakNotificationPlanner.makePlan(
            now: now,
            todaySummary: todaySummary,
            currentStreakDays: priorStreakDays,
            calendar: calendar
        )

        await replacePendingNotification(with: plan)
    }

    private func replacePendingNotification(with plan: StreakBreakNotificationPlan?) async {
        do {
            try await scheduler.replacePendingStreakBreakNotification(with: plan)
        } catch {
            NSLog("Liminalog: failed to refresh streak notification: \(String(describing: error))")
        }
    }

    private func streakCountEndingYesterday(from now: Date) -> Int? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return 0 }

        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: yesterday) else { break }
            guard let summary = ScoreSnapshotLoader.summaryIfAvailable(
                on: target,
                modelContext: modelContext,
                now: now,
                calendar: calendar
            ) else { return nil }
            guard summary.plannedDuration > 0,
                  summary.totalScore >= StreakBreakNotificationPlanner.passingScore
            else { break }
            count += 1
        }
        return count
    }
}

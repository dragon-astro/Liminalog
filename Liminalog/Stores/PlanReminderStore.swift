import Foundation
import SwiftData
import UserNotifications

struct PlanReminderRequest: Equatable {
    let id: String
    let title: String
    let fireDate: Date
    let planID: UUID
    let startDate: Date
    let isAllDay: Bool

    var body: String { isAllDay ? "\(startDate.japaneseMonthDayShortWeekday)・終日の予定です。" : "\(startDate.japaneseMonthDayShortWeekday) \(startDate.shortTime)からの予定です。" }

    static func make(for plan: PlanBlock, now: Date, calendar: Calendar = .current) -> Self? {
        let fire: Date
        if let date = plan.reminderDate {
            fire = date
        } else {
        guard let minutes = plan.reminderMinutesBefore, PlanReminderTiming.validMinutes.contains(minutes) else { return nil }
        let base = plan.isAllDay ? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: plan.startTime) : plan.startTime
        guard let base, let date = calendar.date(byAdding: .minute, value: -minutes, to: base) else { return nil }
        fire = date
        }
        guard fire > now else { return nil }
        return Self(id: "plan-reminder-\(plan.id)", title: plan.title, fireDate: fire, planID: plan.id, startDate: plan.startTime, isAllDay: plan.isAllDay)
    }
}

struct PlanReminderSchedule {
    static func desired(plans: [PlanBlock], now: Date, otherNotificationCount: Int, calendar: Calendar = .current) -> [PlanReminderRequest] {
        Array(plans.compactMap { PlanReminderRequest.make(for: $0, now: now, calendar: calendar) }
            .sorted { $0.fireDate < $1.fireDate }.prefix(max(0, 60 - otherNotificationCount)))
    }

    static func obsolete(pendingIDs: [String], desired: [PlanReminderRequest]) -> [String] {
        let wanted = Set(desired.map(\.id))
        return pendingIDs.filter { $0.hasPrefix("plan-reminder-") && !wanted.contains($0) }
    }
}

@MainActor
final class PlanReminderStore {
    private let context: ModelContext
    private let center: UNUserNotificationCenter
    private var generation = 0
    init(modelContext: ModelContext, center: UNUserNotificationCenter = .current()) {
        context = modelContext; self.center = center
    }

    func refresh(now: Date = Date()) async {
        guard !LiminalogRuntime.isRunningUITests && !LiminalogRuntime.isRunningUnitTests else { return }
        generation += 1
        let token = generation
        let status = await center.notificationSettings().authorizationStatus
        guard token == generation else { return }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let pending = await center.pendingNotificationRequests()
        guard token == generation else { return }
        let descriptor = FetchDescriptor<PlanBlock>(predicate: #Predicate {
            ($0.reminderDate != nil && $0.reminderDate! > now)
                || ($0.reminderMinutesBefore != nil && ($0.endTime > now || $0.reminderMinutesBefore! < 0))
        }, sortBy: [SortDescriptor(\.startTime)])
        do {
            let plans = try context.fetch(descriptor)
            // Leave room for the app's other notifications. Schedule only the nearest reminders.
            let otherCount = pending.filter { !$0.identifier.hasPrefix("plan-reminder-") }.count
            let wanted = PlanReminderSchedule.desired(plans: plans, now: now, otherNotificationCount: otherCount)
            let obsolete = PlanReminderSchedule.obsolete(pendingIDs: pending.map(\.identifier), desired: wanted)
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
            for item in wanted {
                guard token == generation, !Task.isCancelled else { return }
                let fingerprint = "\(item.title)|\(item.body)|\(item.fireDate.timeIntervalSince1970)"
                if pending.contains(where: { $0.identifier == item.id && $0.content.userInfo["planFingerprint"] as? String == fingerprint }) { continue }
                let content = UNMutableNotificationContent()
                content.title = item.title.isEmpty ? "予定のお知らせ" : item.title
                content.body = item.body
                content.sound = .default
                content.userInfo = ["planID": item.planID.uuidString, "planFingerprint": fingerprint,
                                    "liminalogRoute": "calendar"]
                var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
                components.timeZone = Calendar.current.timeZone
                try await center.add(UNNotificationRequest(identifier: item.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
        } catch {
            NSLog("Liminalog: plan reminder refresh failed: \(error)")
        }
    }
}

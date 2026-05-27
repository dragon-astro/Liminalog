import Foundation
import SwiftData
import Testing
@testable import Liminalog

@Suite("DayBoundary")
struct DayBoundaryTests {
    @Test("0:00から翌0:00までを1日として扱う")
    func fixedMidnightBoundary() throws {
        let calendar = Calendar.liminalogTest
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 15)))
        let boundary = DayBoundary(date: date, calendar: calendar)

        #expect(boundary.dayStart == calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 0)))
        #expect(boundary.dayEnd == calendar.date(from: DateComponents(year: 2026, month: 5, day: 29, hour: 0)))
    }

    @Test("日付またぎの時間範囲を対象日にクリップする")
    func clipsCrossDayInterval() throws {
        let calendar = Calendar.liminalogTest
        let boundary = DayBoundary(
            date: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12))),
            calendar: calendar
        )
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))
        let clipped = try #require(boundary.clipped(start: start, end: end))

        #expect(clipped.start == boundary.dayStart)
        #expect(clipped.end == calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 1)))
    }
}

@MainActor
@Suite("SeedCoordinator")
struct SeedCoordinatorTests {
    @Test("UserSettingsはdefaultキーを1件に統合し新しい設定値を引き継ぐ")
    func ensureUserSettingsConsolidatesDefaultDuplicates() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let older = UserSettings()
        older.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        older.updatedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        older.themeName = "default"
        older.defaultVisibility = .all
        older.calendarSyncEnabled = false
        older.showCalendarOverlay = false
        let newer = UserSettings()
        newer.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        newer.updatedAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        newer.themeName = "midnight"
        newer.defaultVisibility = .none
        newer.calendarSyncEnabled = true
        newer.showCalendarOverlay = true
        newer.dashboardCardOrder = ["score", "heatmap"]
        context.insert(older)
        context.insert(newer)
        try context.save()

        let merged = SeedCoordinator.ensureUserSettings(
            in: context,
            now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        )
        let settings = try context.fetch(FetchDescriptor<UserSettings>())

        #expect(settings.count == 1)
        #expect(merged.id == older.id)
        #expect(merged.themeName == "midnight")
        #expect(merged.defaultVisibility == .none)
        #expect(merged.calendarSyncEnabled)
        #expect(merged.showCalendarOverlay)
        #expect(merged.dashboardCardOrder == ["score", "heatmap"])
    }

    @Test("builtInKeyが同じVisibilityPresetを1件に統合する")
    func consolidateBuiltInVisibilityPresetDuplicates() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let first = VisibilityPreset(name: "", level: .all)
        first.builtInKey = "friends"
        first.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let duplicate = VisibilityPreset(name: "友達", level: .partial)
        duplicate.builtInKey = "friends"
        duplicate.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let separate = VisibilityPreset(name: "非公開", level: .none)
        separate.builtInKey = "private"
        context.insert(first)
        context.insert(duplicate)
        context.insert(separate)
        try context.save()

        SeedCoordinator.consolidateBuiltInVisibilityPresets(
            in: context,
            now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        )
        let presets = try context.fetch(FetchDescriptor<VisibilityPreset>(sortBy: [SortDescriptor(\.builtInKey)]))

        #expect(presets.count == 2)
        let friends = try #require(presets.first { $0.builtInKey == "friends" })
        #expect(friends.id == first.id)
        #expect(friends.name == "友達")
        #expect(presets.contains { $0.builtInKey == "private" })
    }
}

@Suite("DashboardPeriod")
struct DashboardPeriodTests {
    @Test("週間期間は今日を含む直近7日を返す")
    func weekIntervalIncludesTodayAndPreviousSixDays() throws {
        let calendar = Calendar.liminalogTest
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let interval = DashboardPeriod.week.dateInterval(containing: date, calendar: calendar)

        #expect(interval.start == calendar.date(from: DateComponents(year: 2026, month: 5, day: 22)))
        #expect(interval.end == calendar.date(from: DateComponents(year: 2026, month: 5, day: 29)))
    }

    @Test("月間と年間期間はカレンダー境界に揃う")
    func monthAndYearIntervalsUseCalendarBoundaries() throws {
        let calendar = Calendar.liminalogTest
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let month = DashboardPeriod.month.dateInterval(containing: date, calendar: calendar)
        let year = DashboardPeriod.year.dateInterval(containing: date, calendar: calendar)

        #expect(month.start == calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        #expect(month.end == calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        #expect(year.start == calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(year.end == calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
    }
}

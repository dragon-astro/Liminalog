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
        newer.dashboardHiddenCardKeys = ["recentTrend"]
        newer.seenUnlockItemKeys = ["badge.first_record", "theme.aurora"]
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
        #expect(merged.dashboardHiddenCardKeys == ["recentTrend"])
        #expect(merged.seenUnlockItemKeys == ["badge.first_record", "theme.aurora"])
    }

    @Test("VisibilityPresetのbuilt-in seedを作成しbuiltInKey重複だけを統合する")
    func seedAndConsolidateBuiltInVisibilityPresets() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let first = VisibilityPreset(name: "", level: .partial)
        first.builtInKey = "close_friends"
        first.hidePhoto = true
        first.hideLocation = true
        first.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let duplicate = VisibilityPreset(name: "友達", level: .none)
        duplicate.builtInKey = "close_friends"
        duplicate.createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let customA = VisibilityPreset(name: "カスタム", level: .partial)
        let customB = VisibilityPreset(name: "カスタム", level: .none)
        context.insert(first)
        context.insert(duplicate)
        context.insert(customA)
        context.insert(customB)
        try context.save()

        SeedCoordinator.consolidateBuiltInVisibilityPresets(
            in: context,
            now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        )
        let presets = try context.fetch(FetchDescriptor<VisibilityPreset>(sortBy: [SortDescriptor(\.builtInKey)]))

        #expect(presets.count == 5)
        let closeFriends = try #require(presets.first { $0.builtInKey == "close_friends" })
        #expect(closeFriends.id == first.id)
        #expect(closeFriends.name == "詳細")
        #expect(closeFriends.level == .all)
        #expect(closeFriends.publishMode == .realtime)
        #expect(!closeFriends.hidePhoto)
        #expect(!closeFriends.hideLocation)
        #expect(closeFriends.isBuiltIn)
        #expect(presets.contains { $0.builtInKey == "acquaintances" })
        #expect(presets.contains { $0.builtInKey == "off" })
        #expect(presets.filter { $0.builtInKey == nil }.count == 2)
    }

    @Test("ユーザーが詳細変更したbuilt-in VisibilityPresetはseedで中身を戻さない")
    func builtInVisibilityPresetSeedPreservesCustomizedDetails() throws {
        let calendar = Calendar.liminalogTest
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let customized = VisibilityPreset(
            name: "自分用の詳細",
            level: .partial,
            builtInKey: "close_friends",
            isBuiltIn: true,
            publishMode: .nextDay,
            hideMoodAndNote: true,
            hidePhoto: true,
            hideLocation: true,
            freeTimeOnly: true
        )
        VisibilityPresetCustomization.markCustomized(customized.id)
        context.insert(customized)
        try context.save()

        SeedCoordinator.consolidateBuiltInVisibilityPresets(
            in: context,
            now: try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        )

        let closeFriends = try #require(
            try context.fetch(FetchDescriptor<VisibilityPreset>()).first { $0.builtInKey == "close_friends" }
        )
        #expect(closeFriends.name == "詳細")
        #expect(closeFriends.publishMode == .nextDay)
        #expect(closeFriends.hideMoodAndNote)
        #expect(closeFriends.hidePhoto)
        #expect(closeFriends.hideLocation)
        #expect(closeFriends.freeTimeOnly)
    }
}

@Suite("DashboardPeriod")
struct DashboardPeriodTests {
    @Test("週間期間は選択日を含むカレンダー週を返す")
    func weekIntervalUsesCalendarWeekContainingSelectedDate() throws {
        var calendar = Calendar.liminalogTest
        calendar.firstWeekday = 1
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let interval = DashboardPeriod.week.dateInterval(containing: date, calendar: calendar)

        #expect(interval.start == calendar.date(from: DateComponents(year: 2026, month: 5, day: 24)))
        #expect(interval.end == calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
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

    @Test("前期間は現在期間の開始直前に揃う")
    func previousIntervalsEndAtCurrentStart() throws {
        var calendar = Calendar.liminalogTest
        calendar.firstWeekday = 1
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 12)))
        let week = DashboardPeriod.week.dateInterval(containing: date, calendar: calendar)
        let previousWeek = DashboardPeriod.week.previousDateInterval(before: week, calendar: calendar)
        let month = DashboardPeriod.month.dateInterval(containing: date, calendar: calendar)
        let previousMonth = DashboardPeriod.month.previousDateInterval(before: month, calendar: calendar)

        #expect(previousWeek.start == calendar.date(from: DateComponents(year: 2026, month: 5, day: 24)))
        #expect(previousWeek.end == week.start)
        #expect(previousMonth.start == calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        #expect(previousMonth.end == month.start)
    }
}

@Suite("DashboardCardKey")
struct DashboardCardKeyTests {
    @Test("保存されたカード順は無効値と重複を除いて不足分を補う")
    func displayOrderNormalizesStoredOrder() {
        let order = DashboardCardKey.displayOrder(
            from: [
                "recentTrend",
                "unknown",
                "periodDelta",
                "recentTrend",
                "hero"
            ],
            for: .week
        )

        #expect(Array(order.prefix(3)) == [.recentTrend, .periodDelta, .hero])
        #expect(order.count == DashboardCardKey.defaultOrder(for: .week).count)
        #expect(Set(order).count == order.count)
        #expect(order.contains(.scoreBreakdown))
    }

    @Test("期間にないカードは表示順から除外される")
    func displayOrderDropsUnavailableCardsForPeriod() {
        let order = DashboardCardKey.displayOrder(
            from: [
                "periodDelta",
                "timeOfDayTrend",
                "scoreTrend",
                "hero"
            ],
            for: .today
        )

        #expect(!order.contains(.periodDelta))
        #expect(!order.contains(.scoreTrend))
        #expect(order.contains(.hero))
    }

    @Test("非表示カードは除外しつつサマリーは残す")
    func visibleDisplayOrderKeepsHeroAndDropsHiddenCards() {
        let order = DashboardCardKey.visibleDisplayOrder(
            from: [
                "recentTrend",
                "hero",
                "metrics",
                "scoreBreakdown"
            ],
            hiddenKeys: [
                "hero",
                "metrics",
                "recentTrend",
                "unknown"
            ],
            for: .week
        )

        #expect(order.first == .hero)
        #expect(order.contains(.hero))
        #expect(!order.contains(.metrics))
        #expect(!order.contains(.recentTrend))
        #expect(order.contains(.scoreBreakdown))
    }
}

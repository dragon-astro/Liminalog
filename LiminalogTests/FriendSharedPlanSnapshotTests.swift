import Foundation
import Testing
@testable import Liminalog

struct FriendSharedPlanSnapshotTests {
    @Test
    func snapshotsOnlyIncludePublicPlansSortedByStartTime() {
        let calendar = Calendar.japanese
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let category = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")

        let laterPublic = PlanBlock(
            category: category,
            title: "午後の予定",
            startTime: calendar.date(byAdding: .hour, value: 3, to: base)!,
            endTime: calendar.date(byAdding: .hour, value: 4, to: base)!,
            isImportant: true,
            isPublic: true
        )
        let privatePlan = PlanBlock(
            category: category,
            title: "自分だけ",
            startTime: calendar.date(byAdding: .hour, value: 1, to: base)!,
            endTime: calendar.date(byAdding: .hour, value: 2, to: base)!,
            isImportant: true,
            isPublic: false
        )
        let earlierPublic = PlanBlock(
            category: nil,
            title: "朝の予定",
            startTime: base,
            endTime: calendar.date(byAdding: .hour, value: 1, to: base)!,
            isImportant: false,
            isPublic: true
        )

        let snapshots = FriendSharedPlanSnapshot.snapshots(from: [laterPublic, privatePlan, earlierPublic])

        #expect(snapshots.map(\.title) == ["朝の予定", "午後の予定"])
        #expect(snapshots[1].categoryTitle == "勉強")
        #expect(snapshots[1].categoryIconName == "book.fill")
        #expect(snapshots[1].categoryColorHex == "#4F8BFF")
        #expect(snapshots[0].categoryIconName == "calendar")
    }

    @Test
    func multiDayAllDayPlanOverlapsEachCoveredDay() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30))!
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        let plan = FriendSharedPlanSnapshot(
            title: "旅行",
            startTime: start,
            endTime: end,
            isAllDay: true,
            isImportant: true
        )

        let firstDay = start
        let secondDay = calendar.date(byAdding: .day, value: 1, to: start)!
        let thirdDay = calendar.date(byAdding: .day, value: 2, to: start)!
        let dayAfter = calendar.date(byAdding: .day, value: 3, to: start)!

        #expect(plan.spansMultipleCalendarDays)
        #expect(plan.overlaps(day: firstDay))
        #expect(plan.overlaps(day: secondDay))
        #expect(plan.overlaps(day: thirdDay))
        #expect(!plan.overlaps(day: dayAfter))
    }
}

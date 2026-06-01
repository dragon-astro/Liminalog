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
    func disabledVisibilityPresetSuppressesPlanSnapshots() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let plan = PlanBlock(
            category: Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill"),
            title: "公開予定",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            isPublic: true
        )
        let preset = VisibilityPreset(name: "オフ", level: .none, publishMode: .none)

        let snapshots = FriendSharedPlanSnapshot.snapshots(from: [plan], visibilityPreset: preset)

        #expect(snapshots.isEmpty)
    }

    @Test
    func freeTimeOnlyVisibilityPresetRedactsPlanDetails() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let end = calendar.date(byAdding: .hour, value: 1, to: start)!
        let category = Category(name: "病院", colorHex: "#EB5757", icon: "cross.case.fill")
        let plan = PlanBlock(
            category: category,
            title: "通院",
            startTime: start,
            endTime: end,
            isImportant: true,
            isPublic: true
        )
        let preset = VisibilityPreset(name: "空き時間のみ", freeTimeOnly: true)

        let snapshots = FriendSharedPlanSnapshot.snapshots(from: [plan], visibilityPreset: preset)

        #expect(snapshots.count == 1)
        #expect(snapshots[0].title == "予定あり")
        #expect(snapshots[0].startTime == start)
        #expect(snapshots[0].endTime == end)
        #expect(snapshots[0].isImportant)
        #expect(snapshots[0].categoryTitle.isEmpty)
        #expect(snapshots[0].categoryIconName == "calendar")
        #expect(snapshots[0].categoryColorHex == "#8E8E93")
    }

    @Test
    func excludedCategoriesSuppressPlanSnapshots() {
        let calendar = Calendar.japanese
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let visibleCategory = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")
        let hiddenCategory = Category(name: "秘密", colorHex: "#EB5757", icon: "lock.fill")
        let visiblePlan = PlanBlock(
            category: visibleCategory,
            title: "見せる予定",
            startTime: base,
            endTime: calendar.date(byAdding: .hour, value: 1, to: base)!,
            isPublic: true
        )
        let hiddenPlan = PlanBlock(
            category: hiddenCategory,
            title: "隠す予定",
            startTime: calendar.date(byAdding: .hour, value: 2, to: base)!,
            endTime: calendar.date(byAdding: .hour, value: 3, to: base)!,
            isPublic: true
        )
        let preset = VisibilityPreset(
            name: "一部だけ",
            excludedCategoryIDs: [hiddenCategory.id],
            freeTimeOnly: true
        )

        let snapshots = FriendSharedPlanSnapshot.snapshots(from: [hiddenPlan, visiblePlan], visibilityPreset: preset)

        #expect(snapshots.map(\.id) == [visiblePlan.id])
        #expect(snapshots.map(\.title) == ["予定あり"])
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

    @Test
    func activitySnapshotsOnlyIncludePublicChaptersAndUseNowForActiveChapter() {
        let calendar = Calendar.japanese
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let now = calendar.date(byAdding: .hour, value: 5, to: base)!
        let category = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")
        let privateCategory = Category(name: "秘密", colorHex: "#EB5757", icon: "lock.fill")

        let activePublic = Chapter(category: category, startTime: calendar.date(byAdding: .hour, value: 2, to: base)!)
        activePublic.isPublic = true

        let privateChapter = Chapter(category: privateCategory, startTime: calendar.date(byAdding: .hour, value: 1, to: base)!)
        privateChapter.endTime = calendar.date(byAdding: .hour, value: 2, to: base)!
        privateChapter.isPublic = false

        let earlierPublic = Chapter(category: category, startTime: base)
        earlierPublic.endTime = calendar.date(byAdding: .hour, value: 1, to: base)!
        earlierPublic.note = "集中できた"

        let snapshots = FriendSharedActivitySnapshot.snapshots(from: [activePublic, privateChapter, earlierPublic], now: now)

        #expect(snapshots.map(\.title) == ["勉強", "勉強"])
        #expect(snapshots[0].note == "集中できた")
        #expect(snapshots[1].endTime == now)
        #expect(snapshots[1].categoryIconName == "book.fill")
        #expect(snapshots[1].categoryColorHex == "#4F8BFF")
    }

    @Test
    func disabledVisibilityPresetSuppressesActivitySnapshots() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let chapter = Chapter(category: Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill"), startTime: start)
        chapter.endTime = calendar.date(byAdding: .hour, value: 1, to: start)!
        chapter.isPublic = true
        let preset = VisibilityPreset(name: "オフ", level: .none, publishMode: .none)

        let snapshots = FriendSharedActivitySnapshot.snapshots(from: [chapter], visibilityPreset: preset)

        #expect(snapshots.isEmpty)
    }

    @Test
    func visibilityPresetRedactsActivityMoodNoteAndLocation() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let chapter = Chapter(category: Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill"), startTime: start)
        chapter.endTime = calendar.date(byAdding: .hour, value: 1, to: start)!
        chapter.note = "集中できた"
        chapter.mood = "good"
        chapter.locationName = "図書館"
        let preset = VisibilityPreset(name: "知り合い", hideMoodAndNote: true, hideLocation: true)

        let snapshots = FriendSharedActivitySnapshot.snapshots(from: [chapter], visibilityPreset: preset)

        #expect(snapshots.count == 1)
        #expect(snapshots[0].note == nil)
        #expect(snapshots[0].mood == nil)
        #expect(snapshots[0].locationName == nil)
        #expect(snapshots[0].categoryTitle == "勉強")
    }

    @Test
    func excludedCategoriesSuppressActivitySnapshots() {
        let calendar = Calendar.japanese
        let base = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 9))!
        let visibleCategory = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")
        let hiddenCategory = Category(name: "秘密", colorHex: "#EB5757", icon: "lock.fill")
        let visibleChapter = Chapter(category: visibleCategory, startTime: base)
        visibleChapter.endTime = calendar.date(byAdding: .hour, value: 1, to: base)!
        let hiddenChapter = Chapter(category: hiddenCategory, startTime: calendar.date(byAdding: .hour, value: 2, to: base)!)
        hiddenChapter.endTime = calendar.date(byAdding: .hour, value: 3, to: base)!
        let preset = VisibilityPreset(name: "一部だけ", excludedCategoryIDs: [hiddenCategory.id])

        let snapshots = FriendSharedActivitySnapshot.snapshots(
            from: [hiddenChapter, visibleChapter],
            visibilityPreset: preset
        )

        #expect(snapshots.map(\.id) == [visibleChapter.id])
    }

    @Test
    func multiDayActivityOverlapsEachCoveredDay() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 23))!
        let end = calendar.date(byAdding: .hour, value: 3, to: start)!
        let activity = FriendSharedActivitySnapshot(
            title: "作業",
            startTime: start,
            endTime: end
        )

        let firstDay = calendar.startOfDay(for: start)
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: firstDay)!

        #expect(activity.spansMultipleCalendarDays)
        #expect(activity.overlaps(day: firstDay))
        #expect(activity.overlaps(day: secondDay))
        #expect(!activity.overlaps(day: dayAfter))
    }
}

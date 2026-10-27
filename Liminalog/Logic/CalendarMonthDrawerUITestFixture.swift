#if DEBUG || LIMINALOG_UI_TESTING
import Foundation
import SwiftData

enum CalendarMonthDrawerUITestFixture {
    static let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static var day: Date {
        let calendar = Calendar.current
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestMonthAppearance")
            || ProcessInfo.processInfo.arguments.contains("-LiminalogUITestPastPalette") {
            return calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestLockedDay") {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        }
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return calendar.date(byAdding: .day, value: 9, to: calendar.date(byAdding: .month, value: 1, to: month)!)!
    }

    @MainActor static func seed(in context: ModelContext) {
        UserDefaults.standard.set("calendar", forKey: "planEditor.datePickerStyle")
        let calendar = Calendar.current
        let longNote = ProcessInfo.processInfo.arguments.contains("-LiminalogUITestLongNote")
        let memoFixture = ProcessInfo.processInfo.arguments.contains("-LiminalogUITestPlanMemos")
        // Keep the familiar work category identical to the app's default palette.
        let work = memoFixture ? Category(name: "仕事", colorHex: "#6C5CE7", icon: "laptopcomputer") : nil
        let errands = memoFixture ? Category(name: "用事", colorHex: "#C37A42", icon: "shippingbox") : nil
        if let work { context.insert(work) }
        if let errands { context.insert(errands) }
        for index in 0..<(memoFixture ? 1 : 12) {
            let start = calendar.date(byAdding: .minute, value: 540 + index * 35, to: day)!
            let plan = PlanBlock(category: work, title: memoFixture ? "仕事" : index == 0 ? "UITest 移動予定" : "UITest 予定 \(index + 1)",
                startTime: start, endTime: start.addingTimeInterval(memoFixture ? 7200 : 1800),
                note: index == 0 && longNote ? String(repeating: "長いメモのスクロール検証\n", count: 25) : nil,
                isPublic: false)
            if index == 0 {
                plan.id = sourceID
                if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestPreviewSource") {
                    plan.sourceEventID = "debug.preview.plan.ui-test"
                }
            }
            context.insert(plan)
        }
        if memoFixture {
            let start = calendar.date(byAdding: .minute, value: 570, to: day)!
            if !ProcessInfo.processInfo.arguments.contains("-LiminalogUITestNarrowMemos") {
                let memo = PlanBlock(category: errands, title: "荷物の受け取り", startTime: start,
                    endTime: start.addingTimeInterval(3600), isMemo: true, isPublic: false)
                memo.id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
                context.insert(memo)
                let phone = PlanBlock(category: errands, title: "電話する", startTime: start.addingTimeInterval(900),
                    endTime: start.addingTimeInterval(2700), isMemo: true, isPublic: false)
                phone.id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
                context.insert(phone)
            }
            let memoPreset = PlanPreset(name: "配達のメモ", title: "配達のメモ", categoryID: errands?.id,
                startMinute: 570, endMinute: 630, isPublic: false, placementMode: .fixedTime)
            memoPreset.isMemo = true
            context.insert(memoPreset)
            let items = [
                PlanTemplateSnapshot(title: "午前の仕事", categoryID: work?.id, startMinute: 540, endMinute: 660,
                    isAllDay: false, isImportant: false, isPublic: false),
                PlanTemplateSnapshot(title: "持ち物確認", categoryID: errands?.id, startMinute: 570, endMinute: 600,
                    isAllDay: false, isImportant: false, isPublic: false, isMemo: true)
            ]
            context.insert(DayPreset(name: "メモを重ねた一日", itemsData: try! DayPresetItemsCodec.encode(items), itemCount: items.count))
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestDropOverlap") {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let start = calendar.date(byAdding: .minute, value: 550, to: nextDay)!
            context.insert(PlanBlock(category: nil, title: "UITest 重複予定",
                startTime: start, endTime: start.addingTimeInterval(2400), isPublic: false))
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestNarrowMemos") {
            for (hour, count) in [(9, 2), (10, 4), (11, 6)] {
                for index in 0..<count {
                    let start = calendar.date(byAdding: .hour, value: hour, to: day)!
                    context.insert(PlanBlock(category: errands, title: "重なり確認\(index + 1)", startTime: start,
                        endTime: start.addingTimeInterval(2400), isMemo: true))
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestFriendExtras") {
            let friend = Friend(displayName: "表示確認", status: .accepted)
            context.insert(friend)
            let plan = PlanBlock(category: nil, title: "図書館で待ち合わせ", startTime: day,
                endTime: calendar.date(byAdding: .day, value: 1, to: day)!, isAllDay: true, isImportant: true,
                locationName: "中央図書館", urlString: "example.com/event", isPublic: true)
            FriendSharedRecordStore(modelContext: context).reconcilePlans(friendID: friend.id,
                snapshots: [FriendSharedPlanSnapshot(plan: plan)])
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestChapters") {
            let category = Category(name: "読書", colorHex: "#537BC5", icon: "book.fill", sortOrder: -1)
            context.insert(category)
            let now = Date()
            let today = DayBoundary.dayStart(for: now)
            let elapsed = now.timeIntervalSince(today)
            let chapter = Chapter(category: category, startTime: today.addingTimeInterval(elapsed / 3))
            chapter.endTime = ProcessInfo.processInfo.arguments.contains("-LiminalogUITestActiveChapter")
                ? nil : today.addingTimeInterval(elapsed / 2)
            chapter.isPublic = false
            context.insert(chapter)
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestTemplateReplacement") {
            let work = Category(name: "仕事", colorHex: "#6C5CE7", icon: "laptopcomputer")
            let rest = Category(name: "休息", colorHex: "#2E9B71", icon: "cup.and.saucer.fill")
            let meeting = Category(name: "交流", colorHex: "#E58A36", icon: "person.2.fill")
            let outing = Category(name: "外出", colorHex: "#3287D1", icon: "figure.walk")
            [work, rest, meeting, outing].forEach { context.insert($0) }
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: day))!
            let start = calendar.date(byAdding: .hour, value: 9, to: firstDay)!
            let morning = PlanBlock(category: work, title: "作業", startTime: start,
                endTime: start.addingTimeInterval(3 * 3600), isPublic: false)
            morning.id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
            context.insert(morning)
            let afternoon = PlanBlock(category: meeting, title: "打ち合わせ", startTime: start.addingTimeInterval(4 * 3600),
                endTime: start.addingTimeInterval(7 * 3600), isPublic: false)
            afternoon.id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
            context.insert(afternoon)
            context.insert(PlanPreset(name: "休憩", title: "休憩", categoryID: rest.id, startMinute: 600, endMinute: 660,
                isPublic: false, placementMode: .fixedTime))
            context.insert(PlanPreset(name: "外出", title: "外出", categoryID: outing.id, startMinute: 660, endMinute: 840,
                isPublic: false, placementMode: .fixedTime, sortOrder: 1))
            context.insert(PlanPreset(name: "読書", title: "読書", categoryID: work.id, startMinute: 960, endMinute: 1020,
                isPublic: false, placementMode: .duration, sortOrder: 2))
            context.insert(PlanPreset(name: "休日", title: "休日", categoryID: rest.id, isAllDay: true,
                isPublic: false, sortOrder: 3))
            let items = [
                PlanTemplateSnapshot(title: "勉強", categoryID: work.id, startMinute: 600, endMinute: 660,
                    isAllDay: false, isImportant: false, isPublic: false),
                PlanTemplateSnapshot(title: "運動", categoryID: outing.id, startMinute: 840, endMinute: 900,
                    isAllDay: false, isImportant: false, isPublic: false),
                PlanTemplateSnapshot(title: "学習日", categoryID: rest.id, startMinute: 0, endMinute: 1440,
                    isAllDay: true, isImportant: false, isPublic: false)
            ]
            context.insert(DayPreset(name: "学習の日", itemsData: try! DayPresetItemsCodec.encode(items), itemCount: items.count))
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestMonthAppearance") {
            UserDefaults.standard.set(false, forKey: "calendarShowsPlanStartTime")
            UserDefaults.standard.set(false, forKey: "calendarStrikePastPlans")
            UserDefaults.standard.set(true, forKey: "calendarDimPastPlans")
            let category = work ?? Category(name: "仕事", colorHex: "#6C5CE7", icon: "laptopcomputer")
            if work == nil { context.insert(category) }
            for (index, offset) in [-2, 1, 10, 20, 27, 32].enumerated() {
                let target = calendar.date(byAdding: .day, value: offset, to: day)!
                let start = calendar.date(byAdding: .hour, value: 9, to: target)!
                let plan = PlanBlock(category: category, title: "月表示確認", startTime: start,
                    endTime: start.addingTimeInterval(3600), isImportant: true, isPublic: false)
                plan.id = UUID(uuidString: "00000000-0000-0000-0000-00000000080\(index)")!
                context.insert(plan)
            }
            let crossingStart = calendar.date(byAdding: .hour, value: 23 * 24 + 22, to: day)!
            context.insert(PlanBlock(category: category, title: "日をまたぐ確認", startTime: crossingStart,
                endTime: crossingStart.addingTimeInterval(28 * 3600), isImportant: true, isPublic: false))
            context.insert(PlanBlock(category: category, title: "終日の確認", startTime: day,
                endTime: calendar.date(byAdding: .day, value: 1, to: day)!, isAllDay: true, isImportant: true, isPublic: false))
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestInitialTimeline") {
            for offset in 0...2 {
                let targetDay = offset == 2 ? day : calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
                let start = calendar.date(byAdding: .hour, value: 7, to: targetDay)!
                let plan = PlanBlock(category: nil, title: "UITest 朝の予定", startTime: start,
                                     endTime: start.addingTimeInterval(3600), isPublic: false)
                plan.id = UUID(uuidString: "00000000-0000-0000-0000-00000000070\(offset + 1)")!
                context.insert(plan)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestPastPalette") {
            // The eight default category colors, the same plans before and after today.
            let palette = [("勉強", "#2F80ED"), ("仕事", "#6C5CE7"), ("趣味", "#EB5757"), ("休憩", "#27AE60"),
                ("睡眠", "#9B51E0"), ("移動", "#F2994A"), ("自由時間", "#F2C94C"), ("家事", "#56CCF2")]
            let categories = palette.enumerated().map { index, entry in
                Category(name: entry.0, colorHex: entry.1, icon: "circle.fill", sortOrder: index)
            }
            categories.forEach { context.insert($0) }
            let today = calendar.startOfDay(for: Date())
            func add(_ title: String, _ category: Int, day offset: Int, hour: Int, hours: Int = 1, allDayCount: Int? = nil) {
                let target = calendar.date(byAdding: .day, value: offset, to: today)!
                let start = allDayCount == nil ? calendar.date(byAdding: .hour, value: hour, to: target)! : target
                let end = allDayCount.map { calendar.date(byAdding: .day, value: $0, to: target)! }
                    ?? start.addingTimeInterval(TimeInterval(hours * 3600))
                context.insert(PlanBlock(category: categories[category], title: title, startTime: start, endTime: end,
                    isAllDay: allDayCount != nil, isImportant: true, isPublic: false))
            }
            for (offset, first) in [(-2, 0), (1, 0), (-1, 4), (2, 4)] {
                let set = first == 0
                    ? [("英語", 9), ("定例会議", 10), ("ギター", 13), ("散歩", 15)]
                    : [("仮眠", 8), ("出張", 10), ("映画", 13), ("洗濯", 18)]
                for (index, item) in set.enumerated() {
                    add(item.0, first + index, day: offset, hour: item.1)
                }
            }
            add("朝会", 1, day: 0, hour: 7)
            add("復習", 0, day: 0, hour: 23)
            add("帰省", 5, day: -9, hour: 0, allDayCount: 2)
            add("研修", 1, day: -5, hour: 0, allDayCount: 1)
            add("ライブ", 6, day: -4, hour: 19)
            add("掃除", 7, day: -3, hour: 10)
            add("旅行", 2, day: 3, hour: 0, allDayCount: 2)
            add("歯医者", 3, day: -13, hour: 11)
            add("読書会", 4, day: -16, hour: 14)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestEditingSamples") {
            PreviewSupport.seedEditingSamplesIfNeeded(in: context, defaults: nil)
        }
        #endif
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-LiminalogUITestTheme"), args.indices.contains(index + 1) {
            let theme = args[index + 1]
            let settings = UserSettings()
            settings.themeName = theme
            context.insert(settings)
            let unlock = UnlockItem()
            unlock.key = "theme.\(theme)"
            unlock.targetID = theme
            unlock.unlockedAt = Date()
            context.insert(unlock)
        }
        try! context.save()
    }
}
#endif

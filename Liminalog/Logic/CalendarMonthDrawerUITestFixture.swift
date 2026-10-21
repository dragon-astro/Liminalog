#if DEBUG || LIMINALOG_UI_TESTING
import Foundation
import SwiftData

enum CalendarMonthDrawerUITestFixture {
    static let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static var day: Date {
        let calendar = Calendar.current
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return calendar.date(byAdding: .day, value: 9, to: calendar.date(byAdding: .month, value: 1, to: month)!)!
    }

    @MainActor static func seed(in context: ModelContext) {
        let calendar = Calendar.current
        let longNote = ProcessInfo.processInfo.arguments.contains("-LiminalogUITestLongNote")
        let memoFixture = ProcessInfo.processInfo.arguments.contains("-LiminalogUITestPlanMemos")
        let work = memoFixture ? Category(name: "仕事", colorHex: "#537BC5", icon: "laptopcomputer") : nil
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
            let memo = PlanBlock(category: errands, title: "荷物の受け取り", startTime: start,
                endTime: start.addingTimeInterval(3600), isMemo: true, isPublic: false)
            memo.id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
            context.insert(memo)
            let phone = PlanBlock(category: errands, title: "電話する", startTime: start.addingTimeInterval(900),
                endTime: start.addingTimeInterval(2700), isMemo: true, isPublic: false)
            phone.id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
            context.insert(phone)
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
        if ProcessInfo.processInfo.arguments.contains("-LiminalogUITestTemplateReplacement") {
            let work = Category(name: "仕事", colorHex: "#7E57C2", icon: "laptopcomputer")
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
        try! context.save()
    }
}
#endif

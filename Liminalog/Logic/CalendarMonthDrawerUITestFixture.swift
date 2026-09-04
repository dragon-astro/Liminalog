#if DEBUG
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
        for index in 0..<12 {
            let start = calendar.date(byAdding: .minute, value: 540 + index * 35, to: day)!
            let plan = PlanBlock(category: nil, title: index == 0 ? "UITest 移動予定" : "UITest 予定 \(index + 1)",
                startTime: start, endTime: start.addingTimeInterval(1800),
                note: index == 0 && longNote ? String(repeating: "長いメモのスクロール検証\n", count: 25) : nil,
                isPublic: false)
            if index == 0 { plan.id = sourceID }
            context.insert(plan)
        }
        try! context.save()
    }
}
#endif

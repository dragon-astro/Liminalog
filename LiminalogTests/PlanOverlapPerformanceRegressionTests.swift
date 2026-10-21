import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct PlanOverlapPerformanceRegressionTests {
    @Test("履歴・終日・境界接触・自己除外を含め、絞ったクエリが従来判定と一致する")
    func boundedOverlapMatchesReference() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_900_000_000)
        var plans: [PlanBlock] = []
        for index in -250..<20 {
            let start = base.addingTimeInterval(Double(index) * 3600)
            let plan = PlanBlock(category: nil, title: "fixture", startTime: start,
                                 endTime: start.addingTimeInterval(index % 3 == 0 ? 7200 : 3600),
                                 isAllDay: index % 5 == 0)
            context.insert(plan)
            plans.append(plan)
        }
        try context.save()
        let store = PlanStore(modelContext: context, requestRefresh: { _, _, _ in })
        for offset in stride(from: -1800, through: 86_400, by: 900) {
            let start = base.addingTimeInterval(Double(offset))
            let end = start.addingTimeInterval(1800)
            for excluded in [nil, plans[252].id] {
                let expected = plans.contains {
                    !$0.isAllDay && $0.id != excluded && $0.startTime < end && $0.endTime > start
                }
                #expect(store.hasTimedPlanOverlap(startTime: start, endTime: end, excluding: excluded) == expected)
            }
        }
        #expect(!store.hasTimedPlanOverlap(startTime: base, endTime: base))
        #expect(!store.hasTimedPlanOverlap(startTime: base, endTime: base.addingTimeInterval(-1)))
    }

    @Test("明日の空き時間は終日予定を無視し従来の15分刻み探索と一致する")
    func firstAvailableHourMatchesReference() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let calendar = Calendar.liminalogTest
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        let store = PlanStore(modelContext: context, requestRefresh: { _, _, _ in })
        let end = day.addingTimeInterval(86400)
        let allDay = PlanBlock(category: nil, title: "終日", startTime: day, endTime: end, isAllDay: true)
        context.insert(allDay)
        let crossing = PlanBlock(category: nil, title: "日跨ぎ", startTime: day.addingTimeInterval(-3600),
                                 endTime: day.addingTimeInterval(9.25 * 3600))
        context.insert(crossing)
        try context.save()
        #expect(store.firstAvailableHourStart(on: day, calendar: calendar) == day.addingTimeInterval(9.25 * 3600))
        for hour in 10..<24 {
            let plan = PlanBlock(category: nil, title: "予定", startTime: day.addingTimeInterval(Double(hour) * 3600),
                                 endTime: day.addingTimeInterval(Double(hour + 1) * 3600))
            context.insert(plan)
            try context.save()
            let expected = stride(from: 9 * 60, through: 23 * 60, by: 15).map {
                day.addingTimeInterval(Double($0 * 60))
            }.first { !store.hasTimedPlanOverlap(startTime: $0, endTime: $0.addingTimeInterval(3600)) }
            #expect(store.firstAvailableHourStart(on: day, calendar: calendar) == expected)
        }
        #expect(store.firstAvailableHourStart(on: day, calendar: calendar) == nil)
    }
}

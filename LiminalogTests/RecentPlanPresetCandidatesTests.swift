import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct RecentPlanPresetCandidatesTests {
    private func plan(_ title: String, hour: Int, created: Int) -> PlanBlock {
        let day = Calendar.liminalogTest.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000))
        let start = day.addingTimeInterval(Double(hour) * 3600)
        let plan = PlanBlock(category: nil, title: title, startTime: start, endTime: start.addingTimeInterval(3600))
        plan.createdAt = Date(timeIntervalSince1970: Double(created))
        return plan
    }

    @Test func newestCreationWinsAndRepeatedContentCollapses() {
        let older = plan("制作", hour: 9, created: 1)
        older.updatedAt = .distantFuture
        let newer = plan("制作", hour: 14, created: 3)
        let other = plan("運動", hour: 8, created: 2)
        let result = RecentPlanPresetCandidates.make(plans: [older, other, newer], presets: [], calendar: .liminalogTest)
        #expect(result.map(\.id) == [newer.id, other.id])
        #expect(result.allSatisfy { $0.modelContext == nil })
    }

    @Test func registeredDurationIgnoresStartButFixedTimePreservesIt() {
        let source = plan("制作", hour: 14, created: 1)
        let registered = PlanPreset(name: "制作", title: "制作", startMinute: 540, endMinute: 600)
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [registered], calendar: .liminalogTest).isEmpty)
        registered.placementMode = .fixedTime
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [registered], calendar: .liminalogTest).count == 1)
        registered.startMinute = 840
        registered.endMinute = 900
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [registered], calendar: .liminalogTest).isEmpty)
    }

    @Test func categoryAndPayloadDifferencesArePreservedAndExternalPlansExcluded() {
        let source = plan("制作", hour: 9, created: 1)
        let registered = PlanPreset(name: "制作", title: "制作", categoryID: UUID())
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [registered], calendar: .liminalogTest).count == 1)
        registered.categoryID = nil
        source.note = "明日の準備"
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [registered], calendar: .liminalogTest).first?.note == source.note)
        source.sourceEventID = "eventkit-id"
        #expect(RecentPlanPresetCandidates.make(plans: [source], presets: [], calendar: .liminalogTest).isEmpty)
    }

    @Test func cappedAtSixAndUseDoesNotRegisterCandidate() throws {
        let plans = (0..<10).map { plan("予定\($0)", hour: 9, created: $0) }
        let candidates = RecentPlanPresetCandidates.make(plans: plans, presets: [], calendar: .liminalogTest)
        #expect(candidates.count == 6)
        #expect(candidates.first?.title == "予定9")
        let container = try TestModelContainer.make()
        let store = PlanPresetStore(modelContext: container.mainContext)
        #expect(store.markUsed(candidates[0]))
        #expect(store.planPresetsIfAvailable()?.isEmpty == true)
        #expect(candidates[0].useCount == 0)
    }
}

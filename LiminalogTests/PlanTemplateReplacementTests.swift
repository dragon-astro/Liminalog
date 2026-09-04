import Foundation
import Testing
@testable import Liminalog

@Suite("Plan template partial replacement")
struct PlanTemplateReplacementTests {
    private func span(_ start: Int, _ end: Int) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: Double(start * 60)),
                     end: Date(timeIntervalSince1970: Double(end * 60)))
    }
    @Test("先頭・末尾・中央・全体・接するだけの区間")
    func overlapShapes() {
        let original = span(60, 180)
        #expect(PlanTemplateReplacement.remainingParts(of: original, excluding: [span(30, 90)]) == [span(90, 180)])
        #expect(PlanTemplateReplacement.remainingParts(of: original, excluding: [span(150, 200)]) == [span(60, 150)])
        #expect(PlanTemplateReplacement.remainingParts(of: original, excluding: [span(90, 120)]) == [span(60, 90), span(120, 180)])
        #expect(PlanTemplateReplacement.remainingParts(of: original, excluding: [span(0, 240)]).isEmpty)
        #expect(PlanTemplateReplacement.remainingParts(of: original, excluding: [span(0, 60), span(180, 200)]) == [original])
    }
    @Test("複数の予定が入っても残りを重複なく保持し1分も捨てない")
    func multipleCuts() {
        #expect(PlanTemplateReplacement.remainingParts(of: span(0, 240),
            excluding: [span(120, 180), span(30, 90), span(60, 119)]) == [span(0, 30), span(119, 120), span(180, 240)])
    }
}

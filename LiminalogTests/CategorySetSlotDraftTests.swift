import Foundation
import Testing
@testable import Liminalog

@Suite("CategorySetSlotDraft")
struct CategorySetSlotDraftTests {
    @Test("カテゴリのドロップは指定スロットへ入り、重複スロットを空にする")
    func categoryDropAssignsDestinationAndRemovesDuplicate() throws {
        let study = UUID()
        let work = UUID()
        let rest = UUID()
        let slots: [UUID?] = [study, work, nil, rest, nil, nil, nil, nil]

        let next = try #require(CategorySetSlotDraft.applyDrop(
            [CategorySetSlotDraft.categoryPayload(for: rest)],
            to: 1,
            slots: slots,
            validCategoryIDs: [study, work, rest]
        ))

        #expect(next[0] == study)
        #expect(next[1] == rest)
        #expect(next[3] == nil)
    }

    @Test("既に使っているカテゴリを別スロットへ置くと元スロットは空になる")
    func existingCategoryDropMovesCategoryInsteadOfDuplicating() throws {
        let study = UUID()
        let work = UUID()
        let slots: [UUID?] = [study, work, nil, nil, nil, nil, nil, nil]

        let next = try #require(CategorySetSlotDraft.applyDrop(
            [CategorySetSlotDraft.categoryPayload(for: study)],
            to: 2,
            slots: slots,
            validCategoryIDs: [study, work]
        ))

        #expect(next[0] == nil)
        #expect(next[1] == work)
        #expect(next[2] == study)
    }

    @Test("スロット同士のドロップは中身を入れ替える")
    func slotDropSwapsSlots() throws {
        let study = UUID()
        let work = UUID()
        let slots: [UUID?] = [study, work, nil, nil, nil, nil, nil, nil]

        let next = try #require(CategorySetSlotDraft.applyDrop(
            [CategorySetSlotDraft.slotPayload(for: 0)],
            to: 1,
            slots: slots,
            validCategoryIDs: [study, work]
        ))

        #expect(next[0] == work)
        #expect(next[1] == study)
    }

    @Test("存在しないカテゴリや不正なスロットは受け付けない")
    func invalidDropPayloadsAreRejected() {
        let study = UUID()
        let unknown = UUID()
        let slots: [UUID?] = [study, nil, nil, nil, nil, nil, nil, nil]

        #expect(CategorySetSlotDraft.applyDrop(
            [CategorySetSlotDraft.categoryPayload(for: unknown)],
            to: 1,
            slots: slots,
            validCategoryIDs: [study]
        ) == nil)

        #expect(CategorySetSlotDraft.applyDrop(
            [CategorySetSlotDraft.slotPayload(for: 99)],
            to: 1,
            slots: slots,
            validCategoryIDs: [study]
        ) == nil)
    }
}

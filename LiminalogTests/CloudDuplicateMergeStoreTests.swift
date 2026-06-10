import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct CloudDuplicateMergeStoreTests {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("同名カテゴリが統合され、実績・予定・スロット・マッピングが勝者へ付け替わる")
    func mergesCategoriesAndRepointsReferences() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let winner = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill", isDefault: true)
        winner.createdAt = base
        let loser = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill", isDefault: true)
        loser.createdAt = base.addingTimeInterval(60)
        context.insert(winner)
        context.insert(loser)

        let chapter = Chapter(category: loser, startTime: base)
        chapter.endTime = base.addingTimeInterval(3_600)
        context.insert(chapter)
        let plan = PlanBlock(category: loser, title: "予習", startTime: base, endTime: base.addingTimeInterval(1_800))
        context.insert(plan)

        let set = CategorySet(name: "平日", isDefault: true)
        set.slots = [loser.id, nil, nil, nil, nil, nil, nil, nil]
        context.insert(set)

        let mapping = FriendCategoryMapping(myCategoryID: loser.id, friendCategoryID: UUID())
        context.insert(mapping)
        try context.save()

        let mergedCount = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        #expect(mergedCount == 1)
        let categories = try context.fetch(FetchDescriptor<Liminalog.Category>())
        #expect(categories.count == 1)
        #expect(categories.first?.id == winner.id)
        #expect(chapter.category?.id == winner.id)
        #expect(plan.category?.id == winner.id)
        #expect(set.slots.first == winner.id)
        #expect(mapping.myCategoryID == winner.id)
    }

    @Test("UserSettings はユーザーID確定済みの行が勝つ")
    func mergesUserSettingsPreferringConfirmedID() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let older = UserSettings()
        older.createdAt = base
        let confirmed = UserSettings()
        confirmed.createdAt = base.addingTimeInterval(60)
        confirmed.cloudUsernameNormalized = "ryulog"
        context.insert(older)
        context.insert(confirmed)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let all = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(all.count == 1)
        #expect(all.first?.cloudUsernameNormalized == "ryulog")
    }

    @Test("同じuserRecordIDの友達はacceptedが勝ち、行キャッシュ・観客・友達セットが付け替わる")
    func mergesFriendsAndRepointsReferences() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let winner = Friend(displayName: "Mika", status: .accepted)
        winner.userRecordID = "_mika"
        winner.createdAt = base.addingTimeInterval(120)
        let loser = Friend(displayName: "Mika(旧)", status: .pendingOutgoing)
        loser.userRecordID = "_mika"
        loser.createdAt = base
        context.insert(winner)
        context.insert(loser)

        let recordStore = FriendSharedRecordStore(modelContext: context)
        let sharedID = UUID()
        recordStore.reconcile(
            friendID: loser.id,
            plans: [
                FriendSharedPlanSnapshot(id: sharedID, title: "共通", startTime: base, endTime: base.addingTimeInterval(600), updatedAt: base),
                FriendSharedPlanSnapshot(title: "loser限定", startTime: base, endTime: base.addingTimeInterval(600), updatedAt: base)
            ],
            activities: []
        )
        recordStore.reconcile(
            friendID: winner.id,
            plans: [FriendSharedPlanSnapshot(id: sharedID, title: "共通(勝者)", startTime: base, endTime: base.addingTimeInterval(600), updatedAt: base)],
            activities: []
        )

        let friendSet = FriendSet(name: "親友", memberFriendIDs: [loser.id], sortOrder: 0)
        context.insert(friendSet)

        let plan = PlanBlock(category: nil, title: "限定公開", startTime: base, endTime: base.addingTimeInterval(600))
        plan.audienceFriendIDs = [loser.id]
        context.insert(plan)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let friends = try context.fetch(FetchDescriptor<Friend>())
        #expect(friends.count == 1)
        #expect(friends.first?.status == .accepted)
        let range = base.addingTimeInterval(-3_600)..<base.addingTimeInterval(3_600)
        let titles = Set(recordStore.plans(friendID: winner.id, overlapping: range).map(\.title))
        #expect(titles == ["共通(勝者)", "loser限定"])
        #expect(friendSet.memberFriendIDs == [winner.id])
        #expect(plan.audienceFriendIDs == [winner.id])
    }

    @Test("同名カテゴリセットと友達セットが統合される")
    func mergesSetsByName() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let winnerSet = CategorySet(name: "平日", isDefault: true)
        winnerSet.createdAt = base
        let loserSet = CategorySet(name: "平日", isDefault: true)
        loserSet.createdAt = base.addingTimeInterval(60)
        let filled = UUID()
        loserSet.slots = [filled, nil, nil, nil, nil, nil, nil, nil]
        context.insert(winnerSet)
        context.insert(loserSet)

        let memberA = UUID()
        let memberB = UUID()
        let winnerFriends = FriendSet(name: "家族", memberFriendIDs: [memberA], sortOrder: 0)
        winnerFriends.createdAt = base
        let loserFriends = FriendSet(name: "家族", memberFriendIDs: [memberA, memberB], sortOrder: 1)
        loserFriends.createdAt = base.addingTimeInterval(60)
        context.insert(winnerFriends)
        context.insert(loserFriends)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let categorySets = try context.fetch(FetchDescriptor<CategorySet>())
        #expect(categorySets.count == 1)
        #expect(categorySets.first?.slots.first == filled)
        let friendSets = try context.fetch(FetchDescriptor<FriendSet>())
        #expect(friendSets.count == 1)
        #expect(Set(friendSets.first?.memberFriendIDs ?? []) == [memberA, memberB])
    }

    @Test("重複が無ければ何もしない（冪等）")
    func noopWithoutDuplicates() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let category = Category(name: "勉強", colorHex: "#4F8BFF", isDefault: true)
        context.insert(category)
        try context.save()

        #expect(CloudDuplicateMergeStore(modelContext: context).mergeAll() == 0)
        #expect(CloudDuplicateMergeStore(modelContext: context).mergeAll() == 0)
        #expect(try context.fetch(FetchDescriptor<Liminalog.Category>()).count == 1)
    }
}

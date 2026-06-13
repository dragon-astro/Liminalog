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
        let loserFriendSetID = UUID()
        let loserIncludedFriendID = UUID()
        let loserExcludedFriendID = UUID()
        loser.defaultAudienceFriendSetIDs = [loserFriendSetID]
        loser.defaultAudienceIncludedFriendIDs = [loserIncludedFriendID]
        loser.defaultAudienceExcludedFriendIDs = [loserExcludedFriendID]
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
        #expect(categories.first?.defaultAudienceFriendSetIDs == [loserFriendSetID])
        #expect(categories.first?.defaultAudienceIncludedFriendIDs == [loserIncludedFriendID])
        #expect(categories.first?.defaultAudienceExcludedFriendIDs == [loserExcludedFriendID])
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
        let filled = Category(name: "勉強", colorHex: "#4F8BFF", isDefault: true)
        context.insert(filled)
        loserSet.slots = [filled.id, nil, nil, nil, nil, nil, nil, nil]
        context.insert(winnerSet)
        context.insert(loserSet)

        let memberA = Friend(displayName: "A", status: .accepted)
        let memberB = Friend(displayName: "B", status: .accepted)
        context.insert(memberA)
        context.insert(memberB)
        let winnerFriends = FriendSet(name: "家族", memberFriendIDs: [memberA.id], sortOrder: 0)
        winnerFriends.createdAt = base
        let loserFriends = FriendSet(name: "家族", memberFriendIDs: [memberA.id, memberB.id], sortOrder: 1)
        loserFriends.createdAt = base.addingTimeInterval(60)
        context.insert(winnerFriends)
        context.insert(loserFriends)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let categorySets = try context.fetch(FetchDescriptor<CategorySet>())
        #expect(categorySets.count == 1)
        #expect(categorySets.first?.slots.first == filled.id)
        let friendSets = try context.fetch(FetchDescriptor<FriendSet>())
        #expect(friendSets.count == 1)
        #expect(Set(friendSets.first?.memberFriendIDs ?? []) == [memberA.id, memberB.id])
    }

    @Test("同一予定は1件に統合され、最新勝者の共有設定は保持される")
    func mergesDuplicatePlanBlocks() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let category = Category(name: "勉強", colorHex: "#4F8BFF", isDefault: true)
        context.insert(category)
        let friendA = Friend(displayName: "A", status: .accepted)
        let friendB = Friend(displayName: "B", status: .accepted)
        context.insert(friendA)
        context.insert(friendB)
        let start = base.addingTimeInterval(3_600)
        let end = base.addingTimeInterval(7_200)

        let older = PlanBlock(category: category, title: "試験対策", startTime: start, endTime: end, isAllDay: false, isImportant: false, note: nil, isPublic: false)
        older.createdAt = base
        older.updatedAt = base
        older.audienceFriendIDs = [friendA.id]
        context.insert(older)

        let newer = PlanBlock(category: category, title: " 試験対策 ", startTime: start, endTime: end, isAllDay: false, isImportant: true, note: nil, isPublic: true)
        newer.createdAt = base.addingTimeInterval(60)
        newer.updatedAt = base.addingTimeInterval(120)
        newer.audienceFriendIDs = [friendB.id]
        context.insert(newer)
        try context.save()

        #expect(CloudDuplicateMergeStore(modelContext: context).mergeAll() >= 1)

        let plans = try context.fetch(FetchDescriptor<PlanBlock>())
        let plan = try #require(plans.first)
        #expect(plans.count == 1)
        #expect(plan.isImportant)
        #expect(plan.isPublic)
        #expect(plan.audienceFriendIDs == [friendB.id])
    }

    @Test("同一実績は1件に統合され、最新勝者の共有設定は保持される")
    func mergesDuplicateChapters() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let category = Category(name: "勉強", colorHex: "#4F8BFF", isDefault: true)
        context.insert(category)
        let friendA = Friend(displayName: "A", status: .accepted)
        let friendB = Friend(displayName: "B", status: .accepted)
        context.insert(friendA)
        context.insert(friendB)
        let start = base.addingTimeInterval(3_600)
        let end = base.addingTimeInterval(7_200)

        let older = Chapter(category: category, startTime: start)
        older.endTime = end
        older.createdAt = base
        older.updatedAt = base
        older.note = "集中"
        older.isPublic = true
        older.audienceFriendIDs = [friendA.id]
        older.hasAudienceSnapshot = true
        context.insert(older)

        let newer = Chapter(category: category, startTime: start)
        newer.endTime = end
        newer.createdAt = base.addingTimeInterval(60)
        newer.updatedAt = base.addingTimeInterval(120)
        newer.note = " 集中 "
        newer.isPublic = false
        newer.audienceFriendIDs = [friendB.id]
        newer.hasAudienceSnapshot = true
        context.insert(newer)
        try context.save()

        #expect(CloudDuplicateMergeStore(modelContext: context).mergeAll() >= 1)

        let chapters = try context.fetch(FetchDescriptor<Chapter>())
        let chapter = try #require(chapters.first)
        #expect(chapters.count == 1)
        #expect(chapter.id == newer.id)
        #expect(!chapter.isPublic)
        #expect(chapter.audienceFriendIDs == [friendB.id])
    }

    @Test("同じユーザー名の友達重複を統合し、参照を勝者へ付け替える")
    func mergesFriendsByCloudUsernameWhenRecordIDIsMissing() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let accepted = Friend(displayName: "Mika", handle: "@mika", status: .accepted)
        accepted.userRecordID = "_mika"
        accepted.createdAt = base.addingTimeInterval(60)
        let pending = Friend(displayName: "Mika old", handle: "@MIKA", status: .pendingOutgoing)
        pending.createdAt = base
        context.insert(accepted)
        context.insert(pending)

        let plan = PlanBlock(category: nil, title: "限定公開", startTime: base, endTime: base.addingTimeInterval(600))
        plan.audienceFriendIDs = [pending.id]
        context.insert(plan)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let friends = try context.fetch(FetchDescriptor<Friend>())
        #expect(friends.count == 1)
        #expect(friends.first?.id == accepted.id)
        #expect(friends.first?.status == .accepted)
        #expect(plan.audienceFriendIDs == [accepted.id])
    }

    @Test("復帰時マージは友達共有行キャッシュの同一sourceID重複も畳む")
    func mergeAllPurgesFriendSharedRecordDuplicates() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friendID = UUID()
        let planID = UUID()
        let chapterID = UUID()

        context.insert(FriendSharedPlanRecord(
            friendID: friendID,
            snapshot: FriendSharedPlanSnapshot(
                id: planID,
                title: "朝会",
                startTime: base,
                endTime: base.addingTimeInterval(1_800),
                updatedAt: base
            )
        ))
        context.insert(FriendSharedPlanRecord(
            friendID: friendID,
            snapshot: FriendSharedPlanSnapshot(
                id: planID,
                title: "朝会",
                startTime: base,
                endTime: base.addingTimeInterval(1_800),
                updatedAt: base.addingTimeInterval(60)
            )
        ))
        context.insert(FriendSharedChapterRecord(
            friendID: friendID,
            snapshot: FriendSharedActivitySnapshot(
                id: chapterID,
                title: "作業",
                startTime: base.addingTimeInterval(3_600),
                endTime: base.addingTimeInterval(7_200),
                updatedAt: base
            )
        ))
        context.insert(FriendSharedChapterRecord(
            friendID: friendID,
            snapshot: FriendSharedActivitySnapshot(
                id: chapterID,
                title: "作業",
                startTime: base.addingTimeInterval(3_600),
                endTime: base.addingTimeInterval(7_200),
                updatedAt: base.addingTimeInterval(60)
            )
        ))
        try context.save()

        #expect(CloudDuplicateMergeStore(modelContext: context).mergeAll() == 2)

        let planRecords = try context.fetch(FetchDescriptor<FriendSharedPlanRecord>())
        let chapterRecords = try context.fetch(FetchDescriptor<FriendSharedChapterRecord>())
        #expect(planRecords.count == 1)
        #expect(chapterRecords.count == 1)
        #expect(planRecords.first?.updatedAt == base.addingTimeInterval(60))
        #expect(chapterRecords.first?.updatedAt == base.addingTimeInterval(60))
    }

    @Test("欠けた公開プリセットを直し、参照配列は重複だけ畳む")
    func repairsDanglingReferencesAndVisibilityPresetSelection() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let friend = Friend(displayName: "Mika", handle: "@mika", status: .accepted)
        friend.userRecordID = "_mika"
        friend.visibilityPresetID = UUID()
        context.insert(friend)

        let staleFriendID = UUID()
        let friendSet = FriendSet(name: "仲良し", memberFriendIDs: [friend.id, staleFriendID, friend.id], sortOrder: 0)
        context.insert(friendSet)

        let category = Category(name: "勉強", colorHex: "#4F8BFF", isDefault: true)
        let staleCategoryID = UUID()
        let staleFriendSetID = UUID()
        category.defaultAudienceFriendSetIDs = [friendSet.id, staleFriendSetID, friendSet.id]
        category.defaultAudienceIncludedFriendIDs = [friend.id, staleFriendID]
        category.defaultAudienceExcludedFriendIDs = [staleFriendID, staleFriendID]
        context.insert(category)

        let preset = VisibilityPreset(name: "カスタム", excludedCategoryIDs: [category.id, staleCategoryID, category.id])
        context.insert(preset)

        let categorySet = CategorySet(name: "平日", isDefault: true)
        categorySet.slots = [category.id, staleCategoryID, category.id, nil, nil, nil, nil, nil]
        context.insert(categorySet)

        let settings = UserSettings()
        let staleCategorySetID = UUID()
        settings.enabledCategorySetID = staleCategorySetID
        context.insert(settings)

        let plan = PlanBlock(category: category, title: "限定公開", startTime: base, endTime: base.addingTimeInterval(600))
        plan.audienceFriendIDs = [friend.id, staleFriendID, friend.id]
        context.insert(plan)
        let chapter = Chapter(category: category, startTime: base)
        chapter.audienceFriendIDs = [staleFriendID]
        context.insert(chapter)
        try context.save()

        _ = CloudDuplicateMergeStore(modelContext: context).mergeAll()

        let presets = try context.fetch(FetchDescriptor<VisibilityPreset>())
        let fallbackID = try #require(presets.first { $0.builtInKey == "acquaintances" }?.id)
        #expect(friend.visibilityPresetID == fallbackID)
        #expect(friendSet.memberFriendIDs == [friend.id, staleFriendID])
        #expect(category.defaultAudienceFriendSetIDs == [friendSet.id, staleFriendSetID])
        #expect(category.defaultAudienceIncludedFriendIDs == [friend.id, staleFriendID])
        #expect(category.defaultAudienceExcludedFriendIDs == [staleFriendID])
        #expect(preset.excludedCategoryIDs == [category.id, staleCategoryID])
        #expect(categorySet.slots == [category.id, staleCategoryID, nil, nil, nil, nil, nil, nil])
        #expect(settings.enabledCategorySetID == staleCategorySetID)
        #expect(plan.audienceFriendIDs == [friend.id, staleFriendID])
        #expect(chapter.audienceFriendIDs == [staleFriendID])
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

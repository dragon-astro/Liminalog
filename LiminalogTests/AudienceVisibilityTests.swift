import Foundation
import Testing
@testable import Liminalog

struct AudienceVisibilityTests {
    @Test("カテゴリデフォルトは友達セットと個別追加除外を展開する")
    func categoryAudienceResolvesFriendSetsAndOverrides() {
        let mika = Friend(displayName: "Mika", status: .accepted)
        let sora = Friend(displayName: "Sora", status: .accepted)
        let ren = Friend(displayName: "Ren", status: .accepted)
        let blocked = Friend(displayName: "Blocked", status: .blocked)
        let set = FriendSet(name: "研究室", memberFriendIDs: [mika.id, sora.id, blocked.id])
        let category = Category(name: "勉強", colorHex: "#2F80ED")
        category.defaultAudienceFriendSetIDs = [set.id]
        category.defaultAudienceIncludedFriendIDs = [ren.id]
        category.defaultAudienceExcludedFriendIDs = [sora.id]

        let resolved = AudienceResolver.categoryDefaultAudience(
            for: category,
            friendSets: [set],
            friends: [mika, sora, ren, blocked]
        )

        #expect(Set(resolved) == [mika.id, ren.id])
    }

    @Test("audienceスナップショットは対象外の友達に共有しない")
    func planSnapshotsRespectAudienceSnapshot() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 10))!
        let allowedFriendID = UUID()
        let deniedFriendID = UUID()
        let plan = PlanBlock(
            category: Category(name: "仕事", colorHex: "#6C5CE7"),
            title: "共有予定",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            isPublic: true
        )
        plan.audienceFriendIDs = [allowedFriendID]
        plan.hasAudienceSnapshot = true

        let allowed = FriendSharedPlanSnapshot.snapshots(
            from: [plan],
            recipientFriendID: allowedFriendID,
            acceptedFriendIDs: [allowedFriendID, deniedFriendID]
        )
        let denied = FriendSharedPlanSnapshot.snapshots(
            from: [plan],
            recipientFriendID: deniedFriendID,
            acceptedFriendIDs: [allowedFriendID, deniedFriendID]
        )

        #expect(allowed.map(\.title) == ["共有予定"])
        #expect(denied.isEmpty)
    }

    @Test("legacyデータはaudience未設定なら公開中の全承認友達に見える")
    func legacyPublicRecordsRemainVisibleToAcceptedFriends() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9))!
        let friendID = UUID()
        let chapter = Chapter(category: Category(name: "勉強", colorHex: "#2F80ED"), startTime: start)
        chapter.endTime = calendar.date(byAdding: .hour, value: 1, to: start)!
        chapter.isPublic = true
        chapter.hasAudienceSnapshot = false

        let snapshots = FriendSharedActivitySnapshot.snapshots(
            from: [chapter],
            recipientFriendID: friendID,
            acceptedFriendIDs: [friendID]
        )

        #expect(snapshots.map(\.title) == ["勉強"])
    }

    @Test("オフの見え方プリセットはaudienceに含まれていても共有しない")
    func offPresetSuppressesAudienceMember() {
        let calendar = Calendar.japanese
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 10))!
        let friendID = UUID()
        let plan = PlanBlock(
            category: Category(name: "仕事", colorHex: "#6C5CE7"),
            title: "公開予定",
            startTime: start,
            endTime: calendar.date(byAdding: .hour, value: 1, to: start)!,
            isPublic: true
        )
        plan.audienceFriendIDs = [friendID]
        plan.hasAudienceSnapshot = true
        let preset = VisibilityPreset(name: "オフ", level: .none, publishMode: .none)

        let snapshots = FriendSharedPlanSnapshot.snapshots(
            from: [plan],
            visibilityPreset: preset,
            recipientFriendID: friendID,
            acceptedFriendIDs: [friendID]
        )

        #expect(snapshots.isEmpty)
    }
}

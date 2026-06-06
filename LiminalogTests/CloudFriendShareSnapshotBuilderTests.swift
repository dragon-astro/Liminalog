import Foundation
import Testing
@testable import Liminalog

struct CloudFriendShareSnapshotBuilderTests {
    @Test
    func disabledPresetSuppressesSharedDataAndScores() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")
        let friend = Friend(displayName: "A", handle: "@friend", status: .accepted)
        friend.userRecordID = "_friend"
        let preset = VisibilityPreset(name: "オフ", level: .none, publishMode: .none)
        friend.visibilityPresetID = preset.id
        let plan = PlanBlock(
            category: category,
            title: "公開予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isPublic: true
        )
        let chapter = Chapter(category: category, startTime: now)
        chapter.mood = "集中"

        let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [preset],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 },
            streakProvider: { 12 }
        )

        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(snapshot.currentMoodText.isEmpty)
        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.streakCount == 0)
        #expect(snapshot.sharedPlans.isEmpty)
        #expect(snapshot.sharedActivities.isEmpty)
    }

    @Test
    func presetRedactsPlanAndMoodDetailsInSnapshot() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "病院", colorHex: "#EB5757", icon: "cross.case.fill")
        let friend = Friend(displayName: "A", handle: "@friend", status: .accepted)
        friend.userRecordID = "_friend"
        let preset = VisibilityPreset(
            name: "控えめ",
            publishMode: .realtime,
            hideMoodAndNote: true,
            hideLocation: true,
            freeTimeOnly: true
        )
        friend.visibilityPresetID = preset.id
        let plan = PlanBlock(
            category: category,
            title: "通院",
            startTime: now.addingTimeInterval(3_600),
            endTime: now.addingTimeInterval(7_200),
            isImportant: true,
            isPublic: true
        )
        let chapter = Chapter(category: category, startTime: now)
        chapter.note = "メモ"
        chapter.mood = "不安"
        chapter.locationName = "駅前"

        let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [preset],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 42 },
            streakProvider: { 7 }
        )

        #expect(snapshot.currentStatusTitle == "病院")
        #expect(snapshot.currentMoodText.isEmpty)
        #expect(snapshot.todayScore == 42)
        #expect(snapshot.streakCount == 7)
        #expect(snapshot.sharedPlans.map(\.title) == ["予定あり"])
        #expect(snapshot.sharedPlans.first?.categoryID == nil)
        #expect(snapshot.sharedActivities.first?.note == nil)
        #expect(snapshot.sharedActivities.first?.mood == nil)
        #expect(snapshot.sharedActivities.first?.locationName == nil)
    }

    @Test
    func audienceSnapshotSharesOnlyWithSelectedAcceptedFriend() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "仕事", colorHex: "#2F80ED", icon: "briefcase.fill")
        let selectedFriend = Friend(displayName: "A", handle: "@selected", status: .accepted)
        selectedFriend.userRecordID = "_selected"
        let otherFriend = Friend(displayName: "B", handle: "@other", status: .accepted)
        otherFriend.userRecordID = "_other"
        let preset = VisibilityPreset(name: "詳細")
        selectedFriend.visibilityPresetID = preset.id
        otherFriend.visibilityPresetID = preset.id
        let plan = PlanBlock(
            category: category,
            title: "限定予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isPublic: true
        )
        plan.audienceFriendIDs = [selectedFriend.id]
        plan.hasAudienceSnapshot = true
        let acceptedFriendIDs: Set<UUID> = [selectedFriend.id, otherFriend.id]

        let selectedSnapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: selectedFriend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [preset],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: acceptedFriendIDs,
            now: now,
            scoreProvider: { _ in 0 }
        )
        let otherSnapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: otherFriend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [preset],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: acceptedFriendIDs,
            now: now,
            scoreProvider: { _ in 0 }
        )

        #expect(selectedSnapshot.sharedPlans.map(\.title) == ["限定予定"])
        #expect(otherSnapshot.sharedPlans.isEmpty)
    }

    @Test
    func missingPresetDoesNotPublishSharedTimelineOrScores() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "仕事", colorHex: "#2F80ED", icon: "briefcase.fill")
        let friend = Friend(displayName: "A", handle: "@friend", status: .accepted)
        friend.userRecordID = "_friend"
        friend.visibilityPresetID = UUID()
        let plan = PlanBlock(
            category: category,
            title: "限定予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isPublic: true
        )
        plan.audienceFriendIDs = [friend.id]
        plan.hasAudienceSnapshot = true

        let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 }
        )

        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(snapshot.sharedPlans.isEmpty)
        #expect(snapshot.sharedActivities.isEmpty)
    }

    @Test
    func unsetPresetDoesNotPublishSharedTimelineOrScores() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "仕事", colorHex: "#2F80ED", icon: "briefcase.fill")
        let friend = Friend(displayName: "A", handle: "@friend", status: .accepted)
        friend.userRecordID = "_friend"
        let plan = PlanBlock(
            category: category,
            title: "公開予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isPublic: true
        )
        let chapter = Chapter(category: category, startTime: now)

        let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 }
        )

        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(snapshot.sharedPlans.isEmpty)
        #expect(snapshot.sharedActivities.isEmpty)
    }
}

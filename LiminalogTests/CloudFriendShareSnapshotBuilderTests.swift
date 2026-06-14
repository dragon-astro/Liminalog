import Foundation
import Testing
import UIKit
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
            ownProfileBio: "朝に強いログ",
            ownProfileImageData: Self.sampleProfileImageData(),
            ownProfileAccentColorHex: "#FF9F0A",
            ownProfileBadgeID: "planner",
            ownProfileIconFrameID: "sunset_ring",
            ownProfileStreakIconID: "spark",
            ownProfileCardStyleID: "generated_evening",
            visibilityPresets: [preset],
            chapters: [chapter],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 },
            streakProvider: { 12 }
        )
        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [preset],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(snapshot.currentMoodText.isEmpty)
        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.streakCount == 0)
        #expect(items.plans.isEmpty)
        #expect(items.activities.isEmpty)
    }

    @Test
    func presetRedactsPlanAndMoodDetailsInSharedItems() throws {
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
            ownProfileBio: "朝に強いログ",
            ownProfileImageData: Self.sampleProfileImageData(),
            ownProfileAccentColorHex: "#FF9F0A",
            ownProfileBadgeID: "planner",
            ownProfileIconFrameID: "sunset_ring",
            ownProfileStreakIconID: "spark",
            ownProfileCardStyleID: "generated_evening",
            visibilityPresets: [preset],
            chapters: [chapter],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 42 },
            streakProvider: { 7 },
            cumulativeScoreProvider: { 4_321 }
        )
        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [preset],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(snapshot.currentStatusTitle == "病院")
        #expect(snapshot.currentMoodText.isEmpty)
        #expect(snapshot.profileBio == "朝に強いログ")
        let profileImageData = try #require(snapshot.profileImageData)
        #expect(profileImageData.count <= ProfileImageShareEncoder.maxByteCount)
        #expect(UIImage(data: profileImageData) != nil)
        #expect(snapshot.profileAccentColorHex == "#FF9F0A")
        #expect(snapshot.profileBadgeID == "planner")
        #expect(snapshot.profileIconFrameID == "sunset_ring")
        #expect(snapshot.profileStreakIconID == "spark")
        #expect(snapshot.profileCardStyleID == "generated_evening")
        #expect(snapshot.todayScore == 42)
        #expect(snapshot.streakCount == 7)
        #expect(snapshot.cumulativeScore == 4_321)
        #expect(items.plans.map(\.title) == ["予定あり"])
        #expect(items.plans.first?.categoryID == nil)
        #expect(items.activities.first?.note == nil)
        #expect(items.activities.first?.mood == nil)
        #expect(items.activities.first?.locationName == nil)
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

        let selectedItems = CloudFriendShareSnapshotBuilder.sharedItems(
            for: selectedFriend,
            visibilityPresets: [preset],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )
        let otherItems = CloudFriendShareSnapshotBuilder.sharedItems(
            for: otherFriend,
            visibilityPresets: [preset],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: acceptedFriendIDs,
            now: now
        )

        #expect(selectedItems.plans.map(\.title) == ["限定予定"])
        #expect(otherItems.plans.isEmpty)
    }

    @Test
    func sharedItemsDropOverlappingPlansAndActivitiesBeforePublishing() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let category = Category(name: "勉強", colorHex: "#4F8BFF", icon: "book.fill")
        let friend = Friend(displayName: "A", handle: "@friend", status: .accepted)
        friend.userRecordID = "_friend"
        let preset = VisibilityPreset(name: "詳細")
        friend.visibilityPresetID = preset.id

        let firstPlan = PlanBlock(
            category: category,
            title: "先の予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isPublic: true
        )
        let overlappingPlan = PlanBlock(
            category: category,
            title: "重なる予定",
            startTime: now.addingTimeInterval(1_800),
            endTime: now.addingTimeInterval(5_400),
            isPublic: true
        )
        let touchingPlan = PlanBlock(
            category: category,
            title: "隣接予定",
            startTime: now.addingTimeInterval(3_600),
            endTime: now.addingTimeInterval(7_200),
            isPublic: true
        )
        let firstChapter = Chapter(category: category, startTime: now)
        firstChapter.endTime = now.addingTimeInterval(1_800)
        let overlappingChapter = Chapter(category: category, startTime: now.addingTimeInterval(900))
        overlappingChapter.endTime = now.addingTimeInterval(2_700)
        let touchingChapter = Chapter(category: category, startTime: now.addingTimeInterval(1_800))
        touchingChapter.endTime = now.addingTimeInterval(3_600)

        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [preset],
            chapters: [firstChapter, overlappingChapter, touchingChapter],
            planBlocks: [firstPlan, overlappingPlan, touchingPlan],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(items.plans.map(\.title) == ["先の予定", "隣接予定"])
        #expect(items.activities.map(\.id) == [firstChapter.id, touchingChapter.id])
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
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 }
        )
        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [],
            chapters: [],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(items.plans.isEmpty)
        #expect(items.activities.isEmpty)
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
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 99 }
        )
        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [],
            chapters: [chapter],
            planBlocks: [plan],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(snapshot.todayScore == 0)
        #expect(snapshot.weekScore == 0)
        #expect(snapshot.currentStatusTitle.isEmpty)
        #expect(items.plans.isEmpty)
        #expect(items.activities.isEmpty)
    }

    @Test
    func activeChapterStaysInCurrentStatusButNotCalendarItems() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let preset = VisibilityPreset(name: "全部公開", level: .all, publishMode: .realtime, now: now)
        let friend = Friend(displayName: "Mika", status: .accepted, now: now)
        friend.userRecordID = "_target"
        friend.visibilityPresetID = preset.id

        let focus = Category(name: "集中", colorHex: "#2F80ED", icon: "bolt.fill")
        let active = Chapter(category: focus, startTime: now.addingTimeInterval(-1_800))
        active.endTime = nil
        active.updatedAt = now.addingTimeInterval(-1_800)

        let finished = Chapter(category: focus, startTime: now.addingTimeInterval(-7_200))
        finished.endTime = now.addingTimeInterval(-3_600)
        finished.updatedAt = now.addingTimeInterval(-3_600)

        let snapshot = CloudFriendShareSnapshotBuilder.snapshot(
            for: friend,
            ownUsername: "owner",
            ownDisplayName: "Owner",
            visibilityPresets: [preset],
            chapters: [active, finished],
            acceptedFriendIDs: [friend.id],
            now: now,
            scoreProvider: { _ in 0 }
        )
        let items = CloudFriendShareSnapshotBuilder.sharedItems(
            for: friend,
            visibilityPresets: [preset],
            chapters: [active, finished],
            planBlocks: [],
            acceptedFriendIDs: [friend.id],
            now: now
        )

        #expect(snapshot.currentStatusTitle == "集中")
        #expect(items.activities.map(\.id) == [finished.id])
    }

    private static func sampleProfileImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 120, y: 120, width: 400, height: 400))
        }
        return image.jpegData(compressionQuality: 0.95) ?? Data()
    }
}

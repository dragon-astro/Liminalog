import Foundation
import SwiftData
import Testing
@testable import Liminalog

@MainActor
struct CloudFriendShareSnapshotApplierTests {
    @Test
    func appliesIncomingSnapshotToFriendCache() throws {
        let container = try TestModelContainer.make()
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let friend = Friend(displayName: "Before", handle: "@before", status: .accepted)
        container.mainContext.insert(friend)
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "owner",
            ownerDisplayName: "Owner",
            targetUserRecordName: "_target",
            currentStatusTitle: "勉強",
            currentStatusIcon: "book.fill",
            currentStatusColorHex: "#4F8BFF",
            currentMoodText: "集中",
            currentStatusStartedAt: now.addingTimeInterval(-1_800),
            todayScore: 88,
            yesterdayScore: 70,
            weekScore: 66,
            monthScore: 55,
            yearScore: 44,
            streakCount: 12,
            updatedAt: now
        )

        CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)

        #expect(friend.displayName == "Owner")
        #expect(friend.handle == "@owner")
        #expect(friend.currentStatusTitle == "勉強")
        #expect(friend.currentStatusIcon == "book.fill")
        #expect(friend.currentStatusColorHex == "#4F8BFF")
        #expect(friend.currentMoodText == "集中")
        #expect(friend.currentStatusStartedAt == now.addingTimeInterval(-1_800))
        #expect(friend.todayScore == 88)
        #expect(friend.yesterdayScore == 70)
        #expect(friend.weekScore == 66)
        #expect(friend.monthScore == 55)
        #expect(friend.yearScore == 44)
        #expect(friend.streakCount == 12)
        #expect(friend.lastSeenAt == now)
    }

    @Test
    func clearsCachedShareWhenAccessIsLost() throws {
        let container = try TestModelContainer.make()
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let friend = Friend(displayName: "Before", handle: "@before", status: .accepted)
        container.mainContext.insert(friend)
        friend.currentStatusTitle = "勉強"
        friend.currentStatusIcon = "book.fill"
        friend.currentStatusColorHex = "#4F8BFF"
        friend.currentMoodText = "集中"
        friend.currentStatusStartedAt = now.addingTimeInterval(-1_800)
        friend.currentStatusUpdatedAt = now
        friend.todayScore = 88
        friend.yesterdayScore = 70
        friend.weekScore = 66
        friend.monthScore = 55
        friend.yearScore = 44
        friend.streakCount = 12
        friend.lastSeenAt = now

        CloudFriendShareSnapshotApplier.clearCachedShare(from: friend)

        #expect(friend.currentStatusTitle.isEmpty)
        #expect(friend.currentStatusIcon == "circle.dashed")
        #expect(friend.currentStatusColorHex == "#8E8E93")
        #expect(friend.currentMoodText.isEmpty)
        #expect(friend.currentStatusStartedAt == nil)
        #expect(friend.currentStatusUpdatedAt == nil)
        #expect(friend.todayScore == 0)
        #expect(friend.yesterdayScore == 0)
        #expect(friend.weekScore == 0)
        #expect(friend.monthScore == 0)
        #expect(friend.yearScore == 0)
        #expect(friend.streakCount == 0)
        #expect(friend.lastSeenAt == nil)
    }
}

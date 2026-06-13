import Foundation
import SwiftData

@MainActor
enum CloudFriendShareSnapshotApplier {
    static func apply(_ snapshot: CloudFriendShareSnapshot, to friend: Friend) {
        // await 跨ぎでCloudKitインポート/重複統合に消されたモデルへ書くとクラッシュするため弾く。
        guard friend.modelContext != nil, !friend.isDeleted else { return }
        friend.displayName = snapshot.ownerDisplayName
        friend.handle = "@\(snapshot.ownerUsername)"
        friend.currentStatusTitle = snapshot.currentStatusTitle
        friend.currentStatusIcon = snapshot.currentStatusIcon
        friend.currentStatusColorHex = snapshot.currentStatusColorHex
        friend.currentMoodText = snapshot.currentMoodText
        friend.currentStatusStartedAt = snapshot.currentStatusStartedAt
        friend.currentStatusUpdatedAt = snapshot.updatedAt
        friend.bio = snapshot.profileBio.isEmpty ? nil : snapshot.profileBio
        friend.profileImageData = snapshot.profileImageData
        friend.accentColorHex = snapshot.profileAccentColorHex
        friend.profileBadgeID = snapshot.profileBadgeID
        friend.profileIconFrameID = snapshot.profileIconFrameID
        friend.profileStreakIconID = snapshot.profileStreakIconID
        friend.profileCardStyleID = snapshot.profileCardStyleID
        friend.todayScore = snapshot.todayScore
        friend.yesterdayScore = snapshot.yesterdayScore
        friend.weekScore = snapshot.weekScore
        friend.monthScore = snapshot.monthScore
        friend.yearScore = snapshot.yearScore
        friend.streakCount = snapshot.streakCount
        friend.cumulativeScore = snapshot.cumulativeScore
        friend.lastSeenAt = snapshot.updatedAt
        friend.updatedAt = Date()
    }

    static func clearCachedShare(from friend: Friend) {
        guard friend.modelContext != nil, !friend.isDeleted else { return }
        friend.currentStatusTitle = ""
        friend.currentStatusIcon = "circle.dashed"
        friend.currentStatusColorHex = "#8E8E93"
        friend.currentMoodText = ""
        friend.currentStatusStartedAt = nil
        friend.currentStatusUpdatedAt = nil
        friend.bio = nil
        friend.profileImageData = nil
        friend.todayScore = 0
        friend.yesterdayScore = 0
        friend.weekScore = 0
        friend.monthScore = 0
        friend.yearScore = 0
        friend.streakCount = 0
        friend.cumulativeScore = 0
        if let modelContext = friend.modelContext {
            FriendSharedRecordStore(modelContext: modelContext).deleteAll(friendID: friend.id)
        }
        friend.lastSeenAt = nil
        friend.updatedAt = Date()
    }
}

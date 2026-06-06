import Foundation

enum CloudFriendShareSnapshotApplier {
    static func apply(_ snapshot: CloudFriendShareSnapshot, to friend: Friend) {
        friend.displayName = snapshot.ownerDisplayName
        friend.handle = "@\(snapshot.ownerUsername)"
        friend.currentStatusTitle = snapshot.currentStatusTitle
        friend.currentStatusIcon = snapshot.currentStatusIcon
        friend.currentStatusColorHex = snapshot.currentStatusColorHex
        friend.currentMoodText = snapshot.currentMoodText
        friend.currentStatusStartedAt = snapshot.currentStatusStartedAt
        friend.currentStatusUpdatedAt = snapshot.updatedAt
        friend.todayScore = snapshot.todayScore
        friend.yesterdayScore = snapshot.yesterdayScore
        friend.weekScore = snapshot.weekScore
        friend.monthScore = snapshot.monthScore
        friend.yearScore = snapshot.yearScore
        friend.streakCount = snapshot.streakCount
        friend.setSharedPlans(snapshot.sharedPlans)
        friend.setSharedActivities(snapshot.sharedActivities)
        friend.lastSeenAt = snapshot.updatedAt
        friend.updatedAt = Date()
    }

    static func clearCachedShare(from friend: Friend) {
        friend.currentStatusTitle = ""
        friend.currentStatusIcon = "circle.dashed"
        friend.currentStatusColorHex = "#8E8E93"
        friend.currentMoodText = ""
        friend.currentStatusStartedAt = nil
        friend.currentStatusUpdatedAt = nil
        friend.todayScore = 0
        friend.yesterdayScore = 0
        friend.weekScore = 0
        friend.monthScore = 0
        friend.yearScore = 0
        friend.streakCount = 0
        friend.setSharedPlans([])
        friend.setSharedActivities([])
        friend.lastSeenAt = nil
        friend.updatedAt = Date()
    }
}

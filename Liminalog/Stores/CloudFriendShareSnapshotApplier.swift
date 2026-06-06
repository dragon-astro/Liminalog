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
}

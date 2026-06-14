import Foundation

struct CloudFriendShareRefreshRequest: Equatable {
    var reason: String
    var changedPlanSourceIDs: Set<UUID> = []
    var changedChapterSourceIDs: Set<UUID> = []
    var changedScoreDayStarts: Set<Date> = []
    var incomingFriendIDs: Set<UUID> = []
    var requiresFullPublish = true
    var resetsPublishedItemState = false

    var isTargetedPublish: Bool {
        !requiresFullPublish && (!changedPlanSourceIDs.isEmpty || !changedChapterSourceIDs.isEmpty || !changedScoreDayStarts.isEmpty)
    }

    var isTargetedIncomingRefresh: Bool {
        !incomingFriendIDs.isEmpty
    }

    mutating func merge(_ other: CloudFriendShareRefreshRequest) {
        reason = other.reason
        requiresFullPublish = requiresFullPublish || other.requiresFullPublish
        resetsPublishedItemState = resetsPublishedItemState || other.resetsPublishedItemState
        changedPlanSourceIDs.formUnion(other.changedPlanSourceIDs)
        changedChapterSourceIDs.formUnion(other.changedChapterSourceIDs)
        changedScoreDayStarts.formUnion(other.changedScoreDayStarts)
        incomingFriendIDs.formUnion(other.incomingFriendIDs)
    }
}

/// One refresh lane should run at most one CloudKit operation at a time.
/// Requests arriving while the lane is running are coalesced into one follow-up run.
struct CloudFriendShareRefreshLane {
    private(set) var isInFlight = false
    private(set) var queuedRequest: CloudFriendShareRefreshRequest?

    mutating func begin(request: CloudFriendShareRefreshRequest) -> Bool {
        guard !isInFlight else {
            if var existing = queuedRequest {
                existing.merge(request)
                queuedRequest = existing
            } else {
                queuedRequest = request
            }
            return false
        }
        isInFlight = true
        queuedRequest = nil
        return true
    }

    mutating func prepareForOperation() {
        queuedRequest = nil
    }

    mutating func finishOperation() -> CloudFriendShareRefreshRequest? {
        guard let nextRequest = queuedRequest else {
            isInFlight = false
            return nil
        }
        queuedRequest = nil
        return nextRequest
    }
}

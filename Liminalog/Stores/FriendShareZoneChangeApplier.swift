import CloudKit
import Foundation
import SwiftData

struct FriendShareZoneChangeApplyResult {
    let impact: FriendSharedRecordChangeImpact
    let shouldNotify: Bool
}

@MainActor
struct FriendShareZoneChangeApplier {
    func apply(
        _ changes: FriendShareZoneChanges,
        to friend: Friend,
        ownUserRecordName: String,
        modelContext: ModelContext,
        stateStore: FriendSharePublishStateStore
    ) -> FriendShareZoneChangeApplyResult? {
        guard friend.modelContext != nil, !friend.isDeleted else { return nil }
        let recordStore = FriendSharedRecordStore(modelContext: modelContext)
        var changedPlans: [FriendSharedPlanSnapshot] = []
        var changedChapters: [FriendSharedActivitySnapshot] = []
        var changedScores: [FriendSharedDailyScoreSnapshot] = []
        var didChangeRoot = false

        for record in changes.changedRecords {
            if let plan = FriendSharedItemRecordPolicy.planSnapshot(from: record) {
                changedPlans.append(plan)
            } else if let activity = FriendSharedItemRecordPolicy.activitySnapshot(from: record) {
                changedChapters.append(activity)
            } else if let score = FriendSharedItemRecordPolicy.scoreSnapshot(from: record) {
                changedScores.append(score)
            } else if record.recordType == CloudFriendShareStore.rootRecordType {
                if let snapshot = try? CloudFriendShareStore.incomingStatusSnapshot(
                    from: record,
                    currentUserRecordName: ownUserRecordName
                ) {
                    CloudFriendShareSnapshotApplier.apply(snapshot, to: friend)
                    didChangeRoot = true
                }
            }
        }

        let impact: FriendSharedRecordChangeImpact
        if changes.didFetchFullZone {
            impact = recordStore.reconcile(
                friendID: friend.id,
                plans: changedPlans,
                activities: changedChapters,
                scores: changedScores
            )
        } else {
            var partialImpact = recordStore.applyChanges(
                friendID: friend.id,
                upsertPlans: changedPlans,
                upsertChapters: changedChapters,
                upsertScores: changedScores,
                deletePlanSourceIDs: Set(
                    changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.planSourceID(fromRecordName:))
                ),
                deleteChapterSourceIDs: Set(
                    changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.chapterSourceID(fromRecordName:))
                ),
                deleteScoreSourceIDs: Set(
                    changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.scoreSourceID(fromRecordName:))
                )
            )
            if didChangeRoot {
                partialImpact.merge(Self.todayAndYesterdayImpact())
            }
            impact = partialImpact
        }

        if let token = changes.changeToken {
            stateStore.setChangeToken(token, ownerUserRecordName: friend.userRecordID)
        }

        let shouldNotify = changes.didFetchFullZone
            || !changes.changedRecords.isEmpty
            || !changes.deletedRecordNames.isEmpty
        return FriendShareZoneChangeApplyResult(impact: impact, shouldNotify: shouldNotify)
    }

    private static func todayAndYesterdayImpact(now: Date = Date(), calendar: Calendar = .japanese) -> FriendSharedRecordChangeImpact {
        var impact = FriendSharedRecordChangeImpact()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        impact.add(start: todayStart, end: tomorrowStart)
        if let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) {
            impact.add(start: yesterdayStart, end: todayStart)
        }
        return impact
    }
}

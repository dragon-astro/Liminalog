import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Liminalog

struct CloudFriendShareSnapshotTests {
    @Test
    func statusSnapshotRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "ryu",
            ownerDisplayName: "Ryu",
            targetUserRecordName: "_target",
            currentStatusTitle: "読書",
            currentStatusIcon: "book.fill",
            currentStatusColorHex: "#34C759",
            currentMoodText: "落ち着いた",
            currentStatusStartedAt: now,
            profileBio: "朝に強いログ",
            profileImageData: Data([0x10, 0x20, 0x30]),
            profileAccentColorHex: "#FF9F0A",
            profileBadgeID: "planner",
            profileIconFrameID: "sunset_ring",
            profileStreakIconID: "spark",
            profileCardStyleID: "generated_evening",
            todayScore: 82,
            yesterdayScore: 77,
            weekScore: 69,
            monthScore: 71,
            yearScore: 73,
            streakCount: 12,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CloudFriendShareSnapshot.self, from: try encoder.encode(snapshot))

        #expect(decoded == snapshot)
    }

    @Test
    func legacyStatusSnapshotDecodesWithDefaultProfileDecoration() throws {
        let json = """
        {
          "ownerUsername": "ryu",
          "ownerDisplayName": "Ryu",
          "targetUserRecordName": "_target",
          "currentStatusTitle": "Reading",
          "currentStatusIcon": "book.fill",
          "currentStatusColorHex": "#34C759",
          "currentMoodText": "calm",
          "currentStatusStartedAt": "2026-06-13T00:00:00Z",
          "todayScore": 82,
          "yesterdayScore": 77,
          "weekScore": 69,
          "monthScore": 71,
          "yearScore": 73,
          "streakCount": 12,
          "updatedAt": "2026-06-13T00:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CloudFriendShareSnapshot.self, from: Data(json.utf8))

        #expect(decoded.profileAccentColorHex == "#2F80ED")
        #expect(decoded.profileBadgeID == "starter")
        #expect(decoded.profileIconFrameID == "clear_air")
        #expect(decoded.profileStreakIconID == "flame")
        #expect(decoded.profileCardStyleID == "quiet_sky")
        #expect(decoded.profileBio.isEmpty)
        #expect(decoded.profileImageData == nil)
        #expect(decoded.cumulativeScore == 0)
    }
}

struct CloudFriendShareRefreshLaneTests {
    @Test
    func startsFirstRefreshImmediately() {
        var lane = CloudFriendShareRefreshLane()
        let didBegin = lane.begin(request: CloudFriendShareRefreshRequest(reason: "launch"))

        #expect(didBegin)
        #expect(lane.isInFlight)
        #expect(lane.queuedRequest == nil)
    }

    @Test
    func coalescesRequestsWhileRefreshIsRunning() {
        var lane = CloudFriendShareRefreshLane()
        let firstPlanID = UUID()
        let secondPlanID = UUID()
        let chapterID = UUID()
        let didBegin = lane.begin(request: CloudFriendShareRefreshRequest(reason: "launch"))
        let didBeginSecond = lane.begin(request: CloudFriendShareRefreshRequest(
            reason: "push-1",
            changedPlanSourceIDs: [firstPlanID],
            requiresFullPublish: false
        ))
        let didBeginThird = lane.begin(request: CloudFriendShareRefreshRequest(
            reason: "push-2",
            changedPlanSourceIDs: [secondPlanID],
            changedChapterSourceIDs: [chapterID],
            requiresFullPublish: false
        ))

        #expect(didBegin)
        #expect(!didBeginSecond)
        #expect(!didBeginThird)
        #expect(lane.isInFlight)
        #expect(lane.queuedRequest?.reason == "push-2")
        #expect(lane.queuedRequest?.changedPlanSourceIDs == [firstPlanID, secondPlanID])
        #expect(lane.queuedRequest?.changedChapterSourceIDs == [chapterID])
        #expect(lane.queuedRequest?.requiresFullPublish == false)
    }

    @Test
    func queuedRequestRunsOnceAfterCurrentOperation() {
        var lane = CloudFriendShareRefreshLane()
        let didBegin = lane.begin(request: CloudFriendShareRefreshRequest(reason: "launch"))

        #expect(didBegin)
        lane.prepareForOperation()
        let didBeginSecond = lane.begin(request: CloudFriendShareRefreshRequest(reason: "push"))

        #expect(!didBeginSecond)
        let nextRequest = lane.finishOperation()
        #expect(nextRequest?.reason == "push")
        #expect(lane.isInFlight)
        #expect(lane.queuedRequest == nil)
    }

    @Test
    func laneBecomesIdleWhenNoRequestArrivesDuringOperation() {
        var lane = CloudFriendShareRefreshLane()
        let didBegin = lane.begin(request: CloudFriendShareRefreshRequest(reason: "launch"))

        #expect(didBegin)
        lane.prepareForOperation()

        let nextRequest = lane.finishOperation()
        #expect(nextRequest == nil)
        #expect(!lane.isInFlight)
        #expect(lane.queuedRequest == nil)
    }

    @Test
    func fullPublishRequestWinsWhenCoalescingWithTargetedRequests() {
        var lane = CloudFriendShareRefreshLane()
        let planID = UUID()
        let didBegin = lane.begin(request: CloudFriendShareRefreshRequest(reason: "targeted"))
        let didBeginSecond = lane.begin(request: CloudFriendShareRefreshRequest(
            reason: "plan",
            changedPlanSourceIDs: [planID],
            requiresFullPublish: false
        ))
        let didBeginThird = lane.begin(request: CloudFriendShareRefreshRequest(reason: "visibility changed"))

        #expect(didBegin)
        #expect(!didBeginSecond)
        #expect(!didBeginThird)
        #expect(lane.queuedRequest?.reason == "visibility changed")
        #expect(lane.queuedRequest?.changedPlanSourceIDs == [planID])
        #expect(lane.queuedRequest?.requiresFullPublish == true)
    }
}

struct FriendSharedItemRecordPolicyTests {
    private let zoneID = CKRecordZone.ID(zoneName: "LiminalogFriendShares", ownerName: "_owner")
    private let now = Date(timeIntervalSince1970: 1_780_764_000)

    private var rootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: "friend-share:_owner:_target", zoneID: zoneID)
    }

    @Test
    func planRecordRoundTrips() throws {
        let snapshot = FriendSharedPlanSnapshot(
            id: UUID(),
            categoryID: UUID(),
            title: "集中する",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isAllDay: false,
            isImportant: true,
            categoryTitle: "仕事",
            categoryIconName: "briefcase.fill",
            categoryColorHex: "#2F80ED",
            updatedAt: now
        )
        let recordName = FriendSharedItemRecordPolicy.planRecordName(
            targetUserRecordName: "_target",
            sourceID: snapshot.id
        )
        let record = CKRecord(
            recordType: FriendSharedItemRecordPolicy.planRecordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
        FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: rootRecordID)

        let decoded = try #require(FriendSharedItemRecordPolicy.planSnapshot(from: record))
        #expect(decoded == snapshot)
        #expect(record.parent?.recordID == rootRecordID)
    }

    @Test
    func chapterRecordRoundTrips() throws {
        let snapshot = FriendSharedActivitySnapshot(
            id: UUID(),
            categoryID: nil,
            title: "読書",
            startTime: now,
            endTime: now.addingTimeInterval(1_800),
            categoryTitle: "休憩",
            categoryIconName: "book.fill",
            categoryColorHex: "#34C759",
            note: "よかった",
            mood: "落ち着いた",
            locationName: nil,
            updatedAt: now
        )
        let recordName = FriendSharedItemRecordPolicy.chapterRecordName(
            targetUserRecordName: "_target",
            sourceID: snapshot.id
        )
        let record = CKRecord(
            recordType: FriendSharedItemRecordPolicy.chapterRecordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
        FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: rootRecordID)

        let decoded = try #require(FriendSharedItemRecordPolicy.activitySnapshot(from: record))
        #expect(decoded == snapshot)
    }

    @Test
    func recordNameParsesSourceID() {
        let sourceID = UUID()
        let planName = FriendSharedItemRecordPolicy.planRecordName(
            targetUserRecordName: "_target",
            sourceID: sourceID
        )
        let chapterName = FriendSharedItemRecordPolicy.chapterRecordName(
            targetUserRecordName: "_target",
            sourceID: sourceID
        )

        #expect(FriendSharedItemRecordPolicy.planSourceID(fromRecordName: planName) == sourceID)
        #expect(FriendSharedItemRecordPolicy.chapterSourceID(fromRecordName: chapterName) == sourceID)
        // 種別違い・無関係のレコード名は nil
        #expect(FriendSharedItemRecordPolicy.planSourceID(fromRecordName: chapterName) == nil)
        #expect(FriendSharedItemRecordPolicy.chapterSourceID(fromRecordName: planName) == nil)
        #expect(FriendSharedItemRecordPolicy.planSourceID(fromRecordName: "friend-share:_o:_t") == nil)
    }

    @Test
    func wrongRecordTypeIsRejected() {
        let record = CKRecord(
            recordType: "FriendShareSnapshot",
            recordID: CKRecord.ID(recordName: "friend-share:_o:_t", zoneID: zoneID)
        )
        #expect(FriendSharedItemRecordPolicy.planSnapshot(from: record) == nil)
        #expect(FriendSharedItemRecordPolicy.activitySnapshot(from: record) == nil)
    }
}

struct FriendSharePublishDiffPolicyTests {
    @Test
    func diffSplitsUpsertAndDelete() {
        let unchanged = UUID()
        let changed = UUID()
        let removed = UUID()
        let added = UUID()

        let plan = FriendSharePublishDiffPolicy.plan(
            desired: [
                unchanged: "fp-1",
                changed: "fp-2-new",
                added: "fp-3"
            ],
            published: [
                unchanged: "fp-1",
                changed: "fp-2-old",
                removed: "fp-4"
            ]
        )

        #expect(plan.upsertSourceIDs == [changed, added])
        #expect(plan.deleteSourceIDs == [removed])
    }

    @Test
    func fingerprintIsStableAndContentSensitive() {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let id = UUID()
        let snapshot = FriendSharedPlanSnapshot(
            id: id,
            title: "予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            updatedAt: now
        )
        var redacted = snapshot
        redacted.title = "予定あり"

        #expect(FriendSharePublishDiffPolicy.fingerprint(snapshot) == FriendSharePublishDiffPolicy.fingerprint(snapshot))
        #expect(FriendSharePublishDiffPolicy.fingerprint(snapshot) != FriendSharePublishDiffPolicy.fingerprint(redacted))
    }
}

@MainActor
struct FriendSharePublishStateStoreTests {
    @Test
    func manifestUpsertDeleteAndClear() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharePublishStateStore(modelContext: container.mainContext)
        let kept = UUID()
        let removed = UUID()

        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [kept: "fp-1", removed: "fp-2"],
            deleted: []
        )
        try container.mainContext.save()
        #expect(store.publishedFingerprints(targetUserRecordName: "_target", kind: FriendSharePublishStateStore.planKind) == [kept: "fp-1", removed: "fp-2"])

        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [kept: "fp-1-updated"],
            deleted: [removed]
        )
        try container.mainContext.save()
        #expect(store.publishedFingerprints(targetUserRecordName: "_target", kind: FriendSharePublishStateStore.planKind) == [kept: "fp-1-updated"])

        store.clearPublishedItems(targetUserRecordName: "_target")
        try container.mainContext.save()
        #expect(store.publishedFingerprints(targetUserRecordName: "_target", kind: FriendSharePublishStateStore.planKind).isEmpty)
    }

    @Test
    func manifestIsScopedByTargetAndKind() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharePublishStateStore(modelContext: container.mainContext)
        let id = UUID()

        store.applyPublishResult(
            targetUserRecordName: "_a",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [id: "fp-plan"],
            deleted: []
        )
        store.applyPublishResult(
            targetUserRecordName: "_a",
            kind: FriendSharePublishStateStore.chapterKind,
            upserted: [id: "fp-chapter"],
            deleted: []
        )
        try container.mainContext.save()

        #expect(store.publishedFingerprints(targetUserRecordName: "_a", kind: FriendSharePublishStateStore.planKind) == [id: "fp-plan"])
        #expect(store.publishedFingerprints(targetUserRecordName: "_a", kind: FriendSharePublishStateStore.chapterKind) == [id: "fp-chapter"])
        #expect(store.publishedFingerprints(targetUserRecordName: "_b", kind: FriendSharePublishStateStore.planKind).isEmpty)
    }

    @Test
    func manifestCanReadOnlyRequestedSourceIDs() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharePublishStateStore(modelContext: container.mainContext)
        let requested = UUID()
        let untouched = UUID()

        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [
                requested: "fp-requested",
                untouched: "fp-untouched"
            ],
            deleted: []
        )
        try container.mainContext.save()

        let fingerprints = store.publishedFingerprints(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            sourceIDs: [requested]
        )
        #expect(fingerprints == [requested: "fp-requested"])
    }

    @Test
    func manifestCanReadManyRequestedSourceIDsWithoutLeakingOtherTargetsOrKinds() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharePublishStateStore(modelContext: container.mainContext)
        let requestedIDs = (0..<30).map { _ in UUID() }
        let requested = Dictionary(
            uniqueKeysWithValues: requestedIDs.enumerated().map { index, id in
                (id, "fp-\(index)")
            }
        )
        let otherTargetID = requestedIDs[0]
        let otherKindID = requestedIDs[1]

        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            upserted: requested,
            deleted: []
        )
        store.applyPublishResult(
            targetUserRecordName: "_other",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [otherTargetID: "wrong-target"],
            deleted: []
        )
        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.chapterKind,
            upserted: [otherKindID: "wrong-kind"],
            deleted: []
        )
        try container.mainContext.save()

        let fingerprints = store.publishedFingerprints(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            sourceIDs: Set(requestedIDs)
        )
        #expect(fingerprints == requested)
    }

    @Test
    func manifestApplyResultCompactsDuplicateSourceRows() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = FriendSharePublishStateStore(modelContext: context)
        let sourceID = UUID()

        context.insert(FriendSharePublishedItem(
            targetUserRecordName: "_target",
            kindRawValue: FriendSharePublishStateStore.planKind,
            sourceID: sourceID,
            fingerprint: "stale-a"
        ))
        context.insert(FriendSharePublishedItem(
            targetUserRecordName: "_target",
            kindRawValue: FriendSharePublishStateStore.planKind,
            sourceID: sourceID,
            fingerprint: "stale-b"
        ))
        try context.save()

        store.applyPublishResult(
            targetUserRecordName: "_target",
            kind: FriendSharePublishStateStore.planKind,
            upserted: [sourceID: "fresh"],
            deleted: []
        )
        try context.save()

        let planKind = FriendSharePublishStateStore.planKind
        let records = try context.fetch(FetchDescriptor<FriendSharePublishedItem>(
            predicate: #Predicate {
                $0.targetUserRecordName == "_target"
                    && $0.kindRawValue == planKind
                    && $0.sourceID == sourceID
            }
        ))
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == "fresh")
    }

    @Test
    func zoneSyncStateWritesCompactDuplicateOwners() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = FriendSharePublishStateStore(modelContext: context)
        let oldState = FriendShareZoneSyncState(ownerUserRecordName: "_owner")
        oldState.updatedAt = Date(timeIntervalSince1970: 1)
        let newState = FriendShareZoneSyncState(ownerUserRecordName: "_owner")
        newState.updatedAt = Date(timeIntervalSince1970: 2)
        context.insert(oldState)
        context.insert(newState)
        try context.save()

        store.setChangeToken(nil, ownerUserRecordName: "_owner")
        try context.save()

        let states = try context.fetch(FetchDescriptor<FriendShareZoneSyncState>(
            predicate: #Predicate { $0.ownerUserRecordName == "_owner" }
        ))
        #expect(states.count == 1)
    }
}

@MainActor
struct FriendShareZoneChangeApplierTests {
    private let zoneID = CKRecordZone.ID(zoneName: CloudFriendShareStore.shareZoneName, ownerName: "_owner")
    private let ownUserRecordName = "_recipient"
    private let ownerUserRecordName = "_owner"
    private let now = Date(timeIntervalSince1970: 1_780_764_000)

    @Test
    func fullZoneFetchReconcilesMissingRowsAndAppliesRootSnapshot() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friend = Friend(displayName: "Before", handle: "@before", status: .accepted, shareURL: "https://example.com/share")
        friend.userRecordID = ownerUserRecordName
        context.insert(friend)
        try context.save()

        let stalePlanID = UUID()
        let keptPlan = FriendSharedPlanSnapshot(
            title: "Still Shared",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isImportant: true,
            updatedAt: now
        )
        let recordStore = FriendSharedRecordStore(modelContext: context)
        recordStore.reconcile(
            friendID: friend.id,
            plans: [
                FriendSharedPlanSnapshot(
                    id: stalePlanID,
                    title: "Stale Before Full Fetch",
                    startTime: now.addingTimeInterval(-7_200),
                    endTime: now.addingTimeInterval(-3_600),
                    isImportant: true,
                    updatedAt: now
                ),
                keptPlan
            ],
            activities: []
        )
        try context.save()

        let changes = FriendShareZoneChanges(
            changedRecords: [
                rootRecord(
                    statusTitle: "Live",
                    mood: "Synced",
                    todayScore: 91
                ),
                planRecord(keptPlan)
            ],
            deletedRecordNames: [],
            changeToken: nil,
            didFetchFullZone: true
        )

        let result = try #require(FriendShareZoneChangeApplier().apply(
            changes,
            to: friend,
            ownUserRecordName: ownUserRecordName,
            modelContext: context,
            stateStore: FriendSharePublishStateStore(modelContext: context)
        ))
        try context.save()

        let plans = recordStore.plans(friendID: friend.id, overlapping: Date.distantPast..<Date.distantFuture)
        #expect(result.shouldNotify)
        #expect(result.impact.requiresFullReload)
        #expect(plans.map(\.id) == [keptPlan.id])
        #expect(!plans.contains { $0.id == stalePlanID })
        #expect(friend.displayName == "Live Owner")
        #expect(friend.handle == "@liveowner")
        #expect(friend.currentStatusTitle == "Live")
        #expect(friend.currentMoodText == "Synced")
        #expect(friend.todayScore == 91)
    }

    @Test
    func incrementalRootChangeNotifiesTodayAndYesterdayWithoutFullReload() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friend = Friend(displayName: "Before", handle: "@before", status: .accepted)
        friend.userRecordID = ownerUserRecordName
        context.insert(friend)
        try context.save()

        let changes = FriendShareZoneChanges(
            changedRecords: [
                rootRecord(
                    statusTitle: "Focus",
                    mood: "",
                    todayScore: 77
                )
            ],
            deletedRecordNames: [],
            changeToken: nil,
            didFetchFullZone: false
        )

        let result = try #require(FriendShareZoneChangeApplier().apply(
            changes,
            to: friend,
            ownUserRecordName: ownUserRecordName,
            modelContext: context,
            stateStore: FriendSharePublishStateStore(modelContext: context)
        ))

        #expect(result.shouldNotify)
        #expect(!result.impact.requiresFullReload)
        #expect(!result.impact.affectedIntervals.isEmpty)
        #expect(friend.currentStatusTitle == "Focus")
        #expect(friend.todayScore == 77)
    }

    private var rootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: "friend-share:\(ownerUserRecordName):\(ownUserRecordName)", zoneID: zoneID)
    }

    private func rootRecord(
        statusTitle: String,
        mood: String,
        todayScore: Double
    ) -> CKRecord {
        let record = CKRecord(
            recordType: CloudFriendShareStore.rootRecordType,
            recordID: rootRecordID
        )
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "liveowner",
            ownerDisplayName: "Live Owner",
            targetUserRecordName: ownUserRecordName,
            currentStatusTitle: statusTitle,
            currentStatusIcon: statusTitle.isEmpty ? "circle.dashed" : "bolt.fill",
            currentStatusColorHex: statusTitle.isEmpty ? "#8E8E93" : "#2F80ED",
            currentMoodText: mood,
            profileBio: "夜に強いログ",
            profileImageData: Data([0x10, 0x20, 0x30]),
            profileAccentColorHex: "#FF9F0A",
            profileBadgeID: "planner",
            profileIconFrameID: "sunset_ring",
            profileStreakIconID: "spark",
            profileCardStyleID: "generated_evening",
            todayScore: todayScore,
            yesterdayScore: 66,
            weekScore: 70,
            monthScore: 72,
            yearScore: 74,
            streakCount: 4,
            updatedAt: now
        )
        record["ownerUsername"] = snapshot.ownerUsername as CKRecordValue
        record["ownerDisplayName"] = snapshot.ownerDisplayName as CKRecordValue
        record["targetUserRecordName"] = snapshot.targetUserRecordName as CKRecordValue
        record["currentStatusTitle"] = snapshot.currentStatusTitle as CKRecordValue
        record["currentStatusIcon"] = snapshot.currentStatusIcon as CKRecordValue
        record["currentStatusColorHex"] = snapshot.currentStatusColorHex as CKRecordValue
        record["currentMoodText"] = snapshot.currentMoodText as CKRecordValue
        record["profileBio"] = snapshot.profileBio as CKRecordValue
        record["profileImageData"] = snapshot.profileImageData as CKRecordValue?
        record["profileAccentColorHex"] = snapshot.profileAccentColorHex as CKRecordValue
        record["profileBadgeID"] = snapshot.profileBadgeID as CKRecordValue
        record["profileIconFrameID"] = snapshot.profileIconFrameID as CKRecordValue
        record["profileStreakIconID"] = snapshot.profileStreakIconID as CKRecordValue
        record["profileCardStyleID"] = snapshot.profileCardStyleID as CKRecordValue
        record["todayScore"] = snapshot.todayScore as CKRecordValue
        record["yesterdayScore"] = snapshot.yesterdayScore as CKRecordValue
        record["weekScore"] = snapshot.weekScore as CKRecordValue
        record["monthScore"] = snapshot.monthScore as CKRecordValue
        record["yearScore"] = snapshot.yearScore as CKRecordValue
        record["streakCount"] = snapshot.streakCount as CKRecordValue
        record["updatedAt"] = snapshot.updatedAt as CKRecordValue
        return record
    }

    private func planRecord(_ snapshot: FriendSharedPlanSnapshot) -> CKRecord {
        let record = CKRecord(
            recordType: FriendSharedItemRecordPolicy.planRecordType,
            recordID: CKRecord.ID(
                recordName: FriendSharedItemRecordPolicy.planRecordName(
                    targetUserRecordName: ownUserRecordName,
                    sourceID: snapshot.id
                ),
                zoneID: zoneID
            )
        )
        FriendSharedItemRecordPolicy.apply(snapshot, to: record, parentRecordID: rootRecordID)
        return record
    }
}

struct FriendShareZoneChangeFetchRecoveryPolicyTests {
    @Test
    func successfulFetchWithoutPreviousTokenIsMarkedFullZone() async throws {
        var requestedTokens: [CKServerChangeToken?] = []

        let changes = try await FriendShareZoneChangeFetchRecoveryPolicy.fetch(previousToken: nil) { token in
            requestedTokens.append(token)
            return FriendShareZoneChanges(changedRecords: [], deletedRecordNames: ["deleted-plan"], changeToken: nil)
        }

        #expect(requestedTokens.count == 1)
        #expect(requestedTokens[0] == nil)
        #expect(changes.didFetchFullZone)
        #expect(changes.deletedRecordNames == ["deleted-plan"])
    }

    @Test
    func changeTokenExpiredRetriesWithNilTokenAndMarksFullZone() async throws {
        var requestedTokens: [String?] = []

        let changes = try await FriendShareZoneChangeFetchRecoveryPolicy.fetch(
            previousToken: "stale-token",
            isChangeTokenExpired: { error in
                guard case FetchRecoveryTestError.changeTokenExpired = error else { return false }
                return true
            }
        ) { token in
            requestedTokens.append(token)
            if requestedTokens.count == 1 {
                throw FetchRecoveryTestError.changeTokenExpired
            }
            return FriendShareZoneChanges(changedRecords: [], deletedRecordNames: ["after-recovery"], changeToken: nil)
        }

        #expect(requestedTokens.count == 2)
        #expect(requestedTokens[0] == "stale-token")
        #expect(requestedTokens[1] == nil)
        #expect(changes.didFetchFullZone)
        #expect(changes.deletedRecordNames == ["after-recovery"])
    }

    @Test
    func nonTokenExpiredErrorDoesNotRetry() async throws {
        var attemptCount = 0

        do {
            _ = try await FriendShareZoneChangeFetchRecoveryPolicy.fetch(previousToken: nil) { _ in
                attemptCount += 1
                throw CKError(.networkUnavailable)
            }
            Issue.record("Expected non-token CloudKit error to be rethrown.")
        } catch let error as CKError {
            #expect(error.code == .networkUnavailable)
        }

        #expect(attemptCount == 1)
    }

    private enum FetchRecoveryTestError: Error {
        case changeTokenExpired
    }
}

@MainActor
struct FriendSharedRecordChangeImpactTests {
    @Test
    func applyChangesReportsUpsertAndDeleteIntervals() throws {
        let container = try TestModelContainer.make()
        let store = FriendSharedRecordStore(modelContext: container.mainContext)
        let friendID = UUID()
        let deletedID = UUID()
        let upsertedID = UUID()
        let deletedStart = Date(timeIntervalSince1970: 1_780_764_000)
        let upsertedStart = deletedStart.addingTimeInterval(86_400)

        store.reconcile(
            friendID: friendID,
            plans: [
                FriendSharedPlanSnapshot(
                    id: deletedID,
                    title: "消える予定",
                    startTime: deletedStart,
                    endTime: deletedStart.addingTimeInterval(3_600),
                    updatedAt: deletedStart
                )
            ],
            activities: []
        )
        try container.mainContext.save()

        let impact = store.applyChanges(
            friendID: friendID,
            upsertPlans: [
                FriendSharedPlanSnapshot(
                    id: upsertedID,
                    title: "増える予定",
                    startTime: upsertedStart,
                    endTime: upsertedStart.addingTimeInterval(1_800),
                    updatedAt: upsertedStart
                )
            ],
            upsertChapters: [],
            deletePlanSourceIDs: [deletedID],
            deleteChapterSourceIDs: []
        )

        #expect(!impact.requiresFullReload)
        #expect(impact.affectedIntervals.contains(DateInterval(start: deletedStart, end: deletedStart.addingTimeInterval(3_600))))
        #expect(impact.affectedIntervals.contains(DateInterval(start: upsertedStart, end: upsertedStart.addingTimeInterval(1_800))))
    }

    @Test
    func notificationScopesCalendarPageMonthsAndDays() throws {
        let friendID = UUID()
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 23)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 1)))
        let notification = Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeFriendIDKey: friendID.uuidString,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: false,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedStartDatesKey: [start],
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedEndDatesKey: [end]
            ]
        )

        let change = SharedRecordChangeNotification(notification)
        let affectedMonths = try #require(change.affectedCalendarPageMonths())
        let may = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let june = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let july = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let august = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        #expect(change.affects(friendID: friendID))
        #expect(change.affects(day: start))
        #expect(change.affects(day: end))
        #expect(affectedMonths.isSuperset(of: [may, june, july, august]))
    }

    @Test
    func notificationEndingAtMidnightDoesNotInvalidateNextDay() throws {
        let friendID = UUID()
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 22)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let notification = Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeFriendIDKey: friendID.uuidString,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: false,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedStartDatesKey: [start],
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedEndDatesKey: [end]
            ]
        )

        let change = SharedRecordChangeNotification(notification)
        let june30 = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let july1 = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12)))
        let affectedMonths = try #require(change.affectedCalendarPageMonths())
        let may = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let june = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let july = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1)))

        #expect(change.affects(day: june30))
        #expect(!change.affects(day: july1))
        #expect(affectedMonths == Set([may, june, july]))
    }

    @Test
    func fullReloadNotificationInvalidatesAllCalendarPagesForOnlyThatFriend() throws {
        let friendID = UUID()
        let otherFriendID = UUID()
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10)))
        let notification = Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeFriendIDKey: friendID.uuidString,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: true,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedStartDatesKey: [start],
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedEndDatesKey: [end]
            ]
        )

        let change = SharedRecordChangeNotification(notification)
        #expect(change.requiresFullReload)
        #expect(change.affects(friendID: friendID))
        #expect(!change.affects(friendID: otherFriendID))
        #expect(change.affects(day: start))
        #expect(change.affectedCalendarPageMonths() == nil)
    }

    @Test
    @MainActor
    func postSharedRecordsDidChangeHelperPostsFullReloadForFriend() throws {
        let friendID = UUID()
        let otherFriendID = UUID()
        let center = NotificationCenter.default
        var received: Notification?
        let observer = center.addObserver(
            forName: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            object: nil,
            queue: nil
        ) { notification in
            received = notification
        }
        defer {
            center.removeObserver(observer)
        }

        CloudFriendShareRefreshCoordinator.postSharedRecordsDidChange(friendID: friendID)

        let change = SharedRecordChangeNotification(try #require(received))
        #expect(change.requiresFullReload)
        #expect(change.affects(friendID: friendID))
        #expect(!change.affects(friendID: otherFriendID))
        #expect(change.affectedCalendarPageMonths() == nil)
    }

    @Test
    func friendCalendarInvalidationPlanClearsAllOnFullReload() throws {
        let notification = Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: true
            ]
        )
        let anchorMonth = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: SharedRecordChangeNotification(notification),
            anchorMonth: anchorMonth,
            currentOffset: 0
        )

        #expect(plan.shouldClearAll)
        #expect(plan.monthsToRemove.isEmpty)
        #expect(plan.shouldEnsureVisibleData)
    }

    @Test
    func friendCalendarInvalidationPlanRefillsVisibleAffectedMonths() throws {
        let anchorMonth = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10)))
        let notification = partialChangeNotification(start: start, end: end)
        let may = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let june = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let july = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 7, day: 1)))

        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: SharedRecordChangeNotification(notification),
            anchorMonth: anchorMonth,
            currentOffset: 0
        )

        #expect(!plan.shouldClearAll)
        #expect(plan.monthsToRemove == Set([may, june, july]))
        #expect(plan.shouldEnsureVisibleData)
    }

    @Test
    func friendCalendarInvalidationPlanDoesNotRefillOffscreenAffectedMonths() throws {
        let anchorMonth = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 15, hour: 9)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 15, hour: 10)))
        let notification = partialChangeNotification(start: start, end: end)
        let november = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let december = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let january = try #require(Calendar.japanese.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: SharedRecordChangeNotification(notification),
            anchorMonth: anchorMonth,
            currentOffset: 0
        )

        #expect(!plan.shouldClearAll)
        #expect(plan.monthsToRemove == Set([november, december, january]))
        #expect(!plan.shouldEnsureVisibleData)
    }

    @Test
    func friendCalendarInvalidationPlanUsesCurrentOffsetForVisibleMonths() throws {
        let anchorMonth = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let start = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 15, hour: 9)))
        let end = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 15, hour: 10)))
        let notification = partialChangeNotification(start: start, end: end)
        let november = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let december = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let january = try #require(Calendar.japanese.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: SharedRecordChangeNotification(notification),
            anchorMonth: anchorMonth,
            currentOffset: 6
        )

        #expect(!plan.shouldClearAll)
        #expect(plan.monthsToRemove == Set([november, december, january]))
        #expect(plan.shouldEnsureVisibleData)
    }

    @Test
    func friendCalendarInvalidationPlanNoopsWhenPartialChangeHasNoIntervals() throws {
        let anchorMonth = try #require(Calendar.japanese.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let notification = Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: false
            ]
        )

        let plan = FriendCalendarCacheInvalidationPolicy.plan(
            for: SharedRecordChangeNotification(notification),
            anchorMonth: anchorMonth,
            currentOffset: 0
        )

        #expect(plan == .noOp)
    }

    private func partialChangeNotification(start: Date, end: Date) -> Notification {
        Notification(
            name: CloudFriendShareRefreshCoordinator.sharedRecordsDidChange,
            userInfo: [
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeRequiresFullReloadKey: false,
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedStartDatesKey: [start],
                CloudFriendShareRefreshCoordinator.sharedRecordsDidChangeAffectedEndDatesKey: [end]
            ]
        )
    }
}

struct CloudKitTransientRetryPolicyTests {
    private func makeCKError(_ code: CKError.Code, retryAfter: Double? = nil) -> CKError {
        var userInfo: [String: Any] = [:]
        if let retryAfter {
            userInfo[CKErrorRetryAfterKey] = retryAfter
        }
        return CKError(code, userInfo: userInfo)
    }

    @Test
    func honorsServerRetryAfterForZoneBusy() {
        // 実機で観測した形: Zone Busy + Retry after 2.0 seconds
        let error = makeCKError(.zoneBusy, retryAfter: 2.0)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: 1) == 2.0)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: 2) == 2.0)
    }

    @Test
    func fallsBackToBackoffWithoutRetryAfter() {
        let error = makeCKError(.serviceUnavailable)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: 1) == 2)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: 2) == 4)
    }

    @Test
    func stopsAfterMaxAttempts() {
        let error = makeCKError(.zoneBusy, retryAfter: 2.0)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: CloudKitTransientRetryPolicy.maxAttempts) == nil)
    }

    @Test
    func permanentErrorsAreNotRetried() {
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: makeCKError(.unknownItem), attempt: 1) == nil)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: makeCKError(.permissionFailure), attempt: 1) == nil)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: CloudFriendShareError.missingShareURL, attempt: 1) == nil)
    }

    @Test
    func clampsExcessiveRetryAfter() {
        let error = makeCKError(.requestRateLimited, retryAfter: 600)
        #expect(CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: 1) == 30)
    }
}

struct CloudFriendShareOperationTimeoutPolicyTests {
    @Test
    func keepsSharedZoneIncrementalFetchLongerThanStandardOperations() {
        #expect(CloudFriendShareOperationTimeoutPolicy.standardOperation == 12)
        #expect(
            CloudFriendShareOperationTimeoutPolicy.incomingShareAccept
                > CloudFriendShareOperationTimeoutPolicy.standardOperation
        )
        #expect(
            CloudFriendShareOperationTimeoutPolicy.sharedZoneFetchTimeout(hasPreviousToken: true)
                > CloudFriendShareOperationTimeoutPolicy.standardOperation
        )
    }

    @Test
    func allowsFullSharedZoneFetchToCoverRealDeviceRecoveryFetches() {
        #expect(
            CloudFriendShareOperationTimeoutPolicy.sharedZoneFetchTimeout(hasPreviousToken: false)
                >= 150
        )
    }
}

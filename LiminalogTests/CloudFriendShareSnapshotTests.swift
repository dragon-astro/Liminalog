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

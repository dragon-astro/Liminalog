import CloudKit
import SwiftData
import XCTest
@testable import Liminalog

final class CloudKitLiveDeviceSmokeTests: XCTestCase {
    private enum LiveE2E {
        static let runIDKey = "LIMINALOG_LIVE_E2E_RUN_ID"
        static let participantRecordType = "LiveCloudKitE2EParticipant"
        static let shareRecordType = "LiveCloudKitE2EShare"
        static let runIDField = "runID"
        static let roleField = "role"
        static let userRecordNameField = "userRecordName"
        static let ownerUserRecordNameField = "ownerUserRecordName"
        static let recipientUserRecordNameField = "recipientUserRecordName"
        static let shareURLField = "shareURL"
        static let rootRecordNameField = "rootRecordName"
        static let planIDField = "planID"
        static let chapterIDField = "chapterID"
        static let secondPlanIDField = "secondPlanID"
        static let updatedPlanTitleField = "updatedPlanTitle"
        static let baselineZoneTokenField = "baselineZoneToken"
        static let postMutationZoneTokenField = "postMutationZoneToken"
        static let postRedactionZoneTokenField = "postRedactionZoneToken"
        static let updatedAtField = "updatedAt"
        static let recipientRole = "recipient"
        static let ownerRole = "owner"

        static var runID: String? {
            [
                ProcessInfo.processInfo.environment[runIDKey],
                Bundle(for: CloudKitLiveDeviceSmokeTests.self).object(forInfoDictionaryKey: runIDKey) as? String,
                Bundle.main.object(forInfoDictionaryKey: runIDKey) as? String
            ]
                .compactMap(normalizedRunID)
                .first
        }

        nonisolated static func normalizedRunID(_ rawValue: String?) -> String? {
            guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.hasPrefix("$(")
            else { return nil }
            return value
        }

        static func recipientRecordName(runID: String) -> String {
            "liminalog-live-e2e:\(runID):recipient"
        }

        static func shareRecordName(runID: String) -> String {
            "liminalog-live-e2e:\(runID):share"
        }
    }

    func testLiveE2ERunIDNormalizationIgnoresEmptyAndUnexpandedBuildSettings() {
        XCTAssertNil(LiveE2E.normalizedRunID(nil))
        XCTAssertNil(LiveE2E.normalizedRunID(""))
        XCTAssertNil(LiveE2E.normalizedRunID("   "))
        XCTAssertNil(LiveE2E.normalizedRunID("$(LIMINALOG_LIVE_E2E_RUN_ID)"))
        XCTAssertEqual(LiveE2E.normalizedRunID("  codex-run  "), "codex-run")
    }

    /// docs/20 §8.3-1,4,5: 個別アイテムレコード（parent=ルート参照）の保存・取得・削除と、
    /// 新レコード型 SharedPlan/SharedChapter のスキーマ自動作成を実CloudKitで確認する。
    /// 自分のプライベートDB内だけで完結し、実在の友達データには触れない（target=スモーク専用ID）。
    func testSharedItemRecordsRoundTripOnRealCloudKit() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit smoke test requires a signed app on a real iOS device.")
#else
        let store = CloudFriendShareStore()
        let socialStore = CloudKitSocialStore()
        let ownRecordName = try await socialStore.currentUserRecordName()
        let smokeTarget = "smoke-test-\(UUID().uuidString.prefix(8))"
        let now = Date()

        // ルート（ステータス専用）を作成。CKShare は張らず、レコード階層だけ検証する。
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "smoketest",
            ownerDisplayName: "Smoke Test",
            targetUserRecordName: smokeTarget,
            updatedAt: now
        )
        let result = try await store.upsertOutgoingShareRootForSmokeTest(snapshot: snapshot)

        // 個別アイテムを parent=ルート参照付きで upsert → 削除
        let plan = FriendSharedPlanSnapshot(
            title: "スモーク予定",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            updatedAt: now
        )
        let chapter = FriendSharedActivitySnapshot(
            title: "スモーク実績",
            startTime: now.addingTimeInterval(-1_800),
            endTime: now,
            updatedAt: now
        )
        let request = FriendShareItemModifyRequest(
            upsertPlans: [plan],
            upsertChapters: [chapter]
        )
        let outcome = await store.modifySharedItems(
            targetUserRecordName: smokeTarget,
            rootRecordID: result.rootRecordID,
            request: request
        )
        if let failure = outcome.failure {
            XCTFail("shared item upsert failed: \(failure)")
        }
        XCTAssertEqual(outcome.appliedPlanUpserts, [plan.id])
        XCTAssertEqual(outcome.appliedChapterUpserts, [chapter.id])

        // 後片付け: アイテム削除 → ルート削除
        let cleanup = await store.modifySharedItems(
            targetUserRecordName: smokeTarget,
            rootRecordID: result.rootRecordID,
            request: FriendShareItemModifyRequest(
                deletePlanSourceIDs: [plan.id],
                deleteChapterSourceIDs: [chapter.id]
            )
        )
        XCTAssertNil(cleanup.failure)
        XCTAssertEqual(cleanup.appliedPlanDeletes, [plan.id])
        try await store.deleteOutgoingShareRootForSmokeTest(rootRecordID: result.rootRecordID)
        _ = ownRecordName
#endif
    }

    /// docs/20 §8.3-5: ある程度まとまった履歴量でも個別レコードpublish/deleteが破綻しないことを、
    /// CKShareなしの専用ルートで実CloudKitに対して確認する。
    func testBulkSharedItemModifyPerformanceOnRealCloudKit() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit bulk smoke test requires a signed app on a real iOS device.")
#else
        let store = CloudFriendShareStore()
        let target = "bulk-smoke-\(UUID().uuidString.prefix(8))"
        let now = Date()
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "bulksmoke",
            ownerDisplayName: "Bulk Smoke",
            targetUserRecordName: target,
            updatedAt: now
        )
        let root = try await store.upsertOutgoingShareRootForSmokeTest(snapshot: snapshot)
        let plans = Self.makeBulkPlans(count: 240, now: now)
        let chapters = Self.makeBulkChapters(count: 120, now: now)
        let totalRecordCount = plans.count + chapters.count

        do {
            let publishStartedAt = Date()
            let publish = await store.modifySharedItems(
                targetUserRecordName: target,
                rootRecordID: root.rootRecordID,
                request: FriendShareItemModifyRequest(
                    upsertPlans: plans,
                    upsertChapters: chapters
                )
            )
            let publishDuration = Date().timeIntervalSince(publishStartedAt)
            print("CloudKit bulk publish: \(totalRecordCount) records in \(publishDuration)s")
            XCTAssertNil(publish.failure)
            XCTAssertEqual(publish.appliedPlanUpserts.count, plans.count)
            XCTAssertEqual(publish.appliedChapterUpserts.count, chapters.count)
            XCTAssertLessThan(
                publishDuration,
                180,
                "Bulk shared item publish took \(publishDuration)s for \(totalRecordCount) records."
            )

            let deleteStartedAt = Date()
            let cleanup = await store.modifySharedItems(
                targetUserRecordName: target,
                rootRecordID: root.rootRecordID,
                request: FriendShareItemModifyRequest(
                    deletePlanSourceIDs: Set(plans.map(\.id)),
                    deleteChapterSourceIDs: Set(chapters.map(\.id))
                )
            )
            let deleteDuration = Date().timeIntervalSince(deleteStartedAt)
            print("CloudKit bulk delete: \(totalRecordCount) records in \(deleteDuration)s")
            XCTAssertNil(cleanup.failure)
            XCTAssertEqual(cleanup.appliedPlanDeletes.count, plans.count)
            XCTAssertEqual(cleanup.appliedChapterDeletes.count, chapters.count)
            XCTAssertLessThan(
                deleteDuration,
                180,
                "Bulk shared item delete took \(deleteDuration)s for \(totalRecordCount) records."
            )

            try await store.deleteOutgoingShareRootForSmokeTest(rootRecordID: root.rootRecordID)
        } catch {
            _ = await store.modifySharedItems(
                targetUserRecordName: target,
                rootRecordID: root.rootRecordID,
                request: FriendShareItemModifyRequest(
                    deletePlanSourceIDs: Set(plans.map(\.id)),
                    deleteChapterSourceIDs: Set(chapters.map(\.id))
                )
            )
            try? await store.deleteOutgoingShareRootForSmokeTest(rootRecordID: root.rootRecordID)
            throw error
        }
#endif
    }


    func testRealDeviceCanReachCloudKitFriendInfrastructure() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit smoke test requires a signed app on a real iOS device.")
#else
        let store = CloudKitSocialStore()
        let ownRecordName = try await store.currentUserRecordName()
        XCTAssertFalse(ownRecordName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        try await store.ensureConsentSubscriptions(forOwnUserRecordName: ownRecordName)
        _ = try await store.incomingConsents(forOwnUserRecordName: ownRecordName)
        _ = try await store.outgoingConsents(forOwnUserRecordName: ownRecordName)

        // ユーザーIDは最大20文字制限があるため、ダミーIDも収める
        let missingUsername = "smk_\(UUID().uuidString.prefix(12).lowercased())"
        do {
            _ = try await store.fetchProfile(username: missingUsername)
            XCTFail("A random smoke-test username should not resolve to a CloudKit profile.")
        } catch CloudKitSocialError.profileNotFound {
            // Expected: the public database is reachable and returns a normal not-found result.
        }
#endif
    }

    /// Two-device live E2E step 1 (run on the recipient device first).
    /// Publishes the recipient iCloud record name into a deterministic public test marker.
    func testLiveTwoDeviceRecipientAnnouncesRecordName() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let socialStore = CloudKitSocialStore()
        let ownRecordName = try await socialStore.currentUserRecordName()
        let publicDatabase = CKContainer(identifier: SharedModelContainer.cloudKitContainerID).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: LiveE2E.recipientRecordName(runID: runID))
        let record = try await fetchPublicRecordIfExists(recordID, from: publicDatabase)
            ?? CKRecord(recordType: LiveE2E.participantRecordType, recordID: recordID)
        record[LiveE2E.runIDField] = runID as CKRecordValue
        record[LiveE2E.roleField] = LiveE2E.recipientRole as CKRecordValue
        record[LiveE2E.userRecordNameField] = ownRecordName as CKRecordValue
        record[LiveE2E.updatedAtField] = Date() as CKRecordValue
        _ = try await publicDatabase.save(record)
#endif
    }

    /// Two-device live E2E step 2 (run on the owner device after the recipient announces).
    /// Creates a real CKShare for the recipient, writes SharedPlan/SharedChapter children,
    /// then publishes the share URL via a public test marker.
    func testLiveTwoDeviceOwnerPublishesShareForAnnouncedRecipient() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        let recipientUserRecordName = try stringField(
            LiveE2E.userRecordNameField,
            from: recipientMarker
        )

        let socialStore = CloudKitSocialStore(container: container)
        let shareStore = CloudFriendShareStore(container: container)
        let ownerRecordName = try await socialStore.currentUserRecordName()
        XCTAssertNotEqual(ownerRecordName, recipientUserRecordName)

        let now = Date()
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "liveowner",
            ownerDisplayName: "Live Owner",
            targetUserRecordName: recipientUserRecordName,
            currentStatusTitle: "Live E2E",
            todayScore: 91,
            updatedAt: now
        )
        let result = try await shareStore.upsertOutgoingShare(snapshot: snapshot)
        guard let shareURL = result.shareURL else {
            XCTFail("Owner share URL was nil.")
            return
        }

        let plan = FriendSharedPlanSnapshot(
            title: "Live E2E Plan \(runID)",
            startTime: now.addingTimeInterval(600),
            endTime: now.addingTimeInterval(4_200),
            isImportant: true,
            updatedAt: now
        )
        let chapter = FriendSharedActivitySnapshot(
            title: "Live E2E Chapter \(runID)",
            startTime: now.addingTimeInterval(-3_600),
            endTime: now.addingTimeInterval(-300),
            updatedAt: now
        )
        let outcome = await shareStore.modifySharedItems(
            targetUserRecordName: recipientUserRecordName,
            rootRecordID: result.rootRecordID,
            request: FriendShareItemModifyRequest(
                upsertPlans: [plan],
                upsertChapters: [chapter]
            )
        )
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.appliedPlanUpserts, [plan.id])
        XCTAssertEqual(outcome.appliedChapterUpserts, [chapter.id])

        let shareRecordID = CKRecord.ID(recordName: LiveE2E.shareRecordName(runID: runID))
        let shareRecord = try await fetchPublicRecordIfExists(shareRecordID, from: publicDatabase)
            ?? CKRecord(recordType: LiveE2E.shareRecordType, recordID: shareRecordID)
        shareRecord[LiveE2E.runIDField] = runID as CKRecordValue
        shareRecord[LiveE2E.roleField] = LiveE2E.ownerRole as CKRecordValue
        shareRecord[LiveE2E.ownerUserRecordNameField] = ownerRecordName as CKRecordValue
        shareRecord[LiveE2E.recipientUserRecordNameField] = recipientUserRecordName as CKRecordValue
        shareRecord[LiveE2E.shareURLField] = shareURL.absoluteString as CKRecordValue
        shareRecord[LiveE2E.rootRecordNameField] = result.rootRecordName as CKRecordValue
        shareRecord[LiveE2E.planIDField] = plan.id.uuidString as CKRecordValue
        shareRecord[LiveE2E.chapterIDField] = chapter.id.uuidString as CKRecordValue
        shareRecord[LiveE2E.updatedAtField] = now as CKRecordValue
        _ = try await publicDatabase.save(shareRecord)
#endif
    }

    /// Two-device live E2E step 3 (run on the recipient device after the owner publishes).
    /// Accepts the real CKShare, fetches shared-zone changes, and proves the child records
    /// can be reconciled into the local row cache.
    func testLiveTwoDeviceRecipientAcceptsShareAndFetchesSharedItems() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(
            LiveE2E.ownerUserRecordNameField,
            from: shareMarker
        )
        let recipientUserRecordName = try stringField(
            LiveE2E.recipientUserRecordNameField,
            from: shareMarker
        )
        let shareURLString = try stringField(LiveE2E.shareURLField, from: shareMarker)
        let expectedPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let expectedChapterID = try uuidField(LiveE2E.chapterIDField, from: shareMarker)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, recipientUserRecordName)
        guard let shareURL = URL(string: shareURLString) else {
            XCTFail("Invalid share URL: \(shareURLString)")
            return
        }

        let shareStore = CloudFriendShareStore(container: container)
        let snapshot = try await shareStore.acceptIncomingShare(url: shareURL)
        XCTAssertEqual(snapshot.targetUserRecordName, ownRecordName)

        let changes = try await shareStore.fetchSharedZoneChanges(
            ownerUserRecordName: ownerUserRecordName,
            previousToken: nil
        )
        let plans = changes.changedRecords.compactMap(FriendSharedItemRecordPolicy.planSnapshot(from:))
        let chapters = changes.changedRecords.compactMap(FriendSharedItemRecordPolicy.activitySnapshot(from:))
        XCTAssertTrue(plans.contains { $0.id == expectedPlanID })
        XCTAssertTrue(chapters.contains { $0.id == expectedChapterID })
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        recipientMarker[LiveE2E.baselineZoneTokenField] = try data(from: changes.changeToken) as CKRecordValue?
        recipientMarker[LiveE2E.updatedAtField] = Date() as CKRecordValue
        _ = try await publicDatabase.save(recipientMarker)

        let modelContainer = try TestModelContainer.make()
        let friendID = UUID()
        let recordStore = FriendSharedRecordStore(modelContext: modelContainer.mainContext)
        recordStore.reconcile(friendID: friendID, plans: plans, activities: chapters)
        try modelContainer.mainContext.save()
        let allRange = Date.distantPast..<Date.distantFuture
        XCTAssertTrue(recordStore.plans(friendID: friendID, overlapping: allRange).contains { $0.id == expectedPlanID })
        XCTAssertTrue(recordStore.chapters(friendID: friendID, overlapping: allRange).contains { $0.id == expectedChapterID })
#endif
    }

    /// Two-device live E2E step 4 (run on the owner device after the recipient stores a baseline token).
    /// Mutates child records after the initial full fetch: update an existing plan, add a plan, and delete a chapter.
    func testLiveTwoDeviceOwnerMutatesSharedItemsAfterRecipientBaseline() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(LiveE2E.ownerUserRecordNameField, from: shareMarker)
        let recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        let expectedRootRecordName = try stringField(LiveE2E.rootRecordNameField, from: shareMarker)
        let existingPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let existingChapterID = try uuidField(LiveE2E.chapterIDField, from: shareMarker)
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        _ = try changeToken(from: recipientMarker[LiveE2E.baselineZoneTokenField] as? Data)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, ownerUserRecordName)

        let now = Date()
        let shareStore = CloudFriendShareStore(container: container)
        let result = try await shareStore.upsertOutgoingShare(
            snapshot: CloudFriendShareSnapshot(
                ownerUsername: "liveowner",
                ownerDisplayName: "Live Owner",
                targetUserRecordName: recipientUserRecordName,
                currentStatusTitle: "Live E2E Updated",
                todayScore: 93,
                updatedAt: now
            )
        )
        XCTAssertEqual(result.rootRecordName, expectedRootRecordName)

        let updatedTitle = "Live E2E Plan Updated \(runID)"
        let updatedPlan = FriendSharedPlanSnapshot(
            id: existingPlanID,
            title: updatedTitle,
            startTime: now.addingTimeInterval(1_200),
            endTime: now.addingTimeInterval(4_800),
            isImportant: false,
            updatedAt: now
        )
        let secondPlan = FriendSharedPlanSnapshot(
            title: "Live E2E Plan Added \(runID)",
            startTime: now.addingTimeInterval(7_200),
            endTime: now.addingTimeInterval(9_000),
            isImportant: true,
            updatedAt: now
        )
        let outcome = await shareStore.modifySharedItems(
            targetUserRecordName: recipientUserRecordName,
            rootRecordID: result.rootRecordID,
            request: FriendShareItemModifyRequest(
                upsertPlans: [updatedPlan, secondPlan],
                deleteChapterSourceIDs: [existingChapterID]
            )
        )
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.appliedPlanUpserts, [updatedPlan.id, secondPlan.id])
        XCTAssertEqual(outcome.appliedChapterDeletes, [existingChapterID])

        shareMarker[LiveE2E.secondPlanIDField] = secondPlan.id.uuidString as CKRecordValue
        shareMarker[LiveE2E.updatedPlanTitleField] = updatedTitle as CKRecordValue
        shareMarker[LiveE2E.updatedAtField] = now as CKRecordValue
        _ = try await publicDatabase.save(shareMarker)
#endif
    }

    /// Two-device live E2E step 5 (run on the recipient device after the owner mutates items).
    /// Fetches from the stored zone token and proves updates/deletions arrive as incremental changes.
    func testLiveTwoDeviceRecipientFetchesIncrementalSharedItemChanges() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(LiveE2E.ownerUserRecordNameField, from: shareMarker)
        let recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        let expectedPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let expectedChapterID = try uuidField(LiveE2E.chapterIDField, from: shareMarker)
        let expectedSecondPlanID = try uuidField(LiveE2E.secondPlanIDField, from: shareMarker)
        let expectedUpdatedTitle = try stringField(LiveE2E.updatedPlanTitleField, from: shareMarker)
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        let baselineToken = try changeToken(from: recipientMarker[LiveE2E.baselineZoneTokenField] as? Data)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, recipientUserRecordName)

        let shareStore = CloudFriendShareStore(container: container)
        let changes = try await shareStore.fetchSharedZoneChanges(
            ownerUserRecordName: ownerUserRecordName,
            previousToken: baselineToken
        )
        XCTAssertFalse(changes.didFetchFullZone)
        let plans = changes.changedRecords.compactMap(FriendSharedItemRecordPolicy.planSnapshot(from:))
        XCTAssertTrue(plans.contains { $0.id == expectedPlanID && $0.title == expectedUpdatedTitle })
        XCTAssertTrue(plans.contains { $0.id == expectedSecondPlanID })
        XCTAssertTrue(changes.deletedRecordNames.contains {
            FriendSharedItemRecordPolicy.chapterSourceID(fromRecordName: $0) == expectedChapterID
        })
        recipientMarker[LiveE2E.postMutationZoneTokenField] = try data(from: changes.changeToken) as CKRecordValue?
        recipientMarker[LiveE2E.updatedAtField] = Date() as CKRecordValue
        _ = try await publicDatabase.save(recipientMarker)

        let modelContainer = try TestModelContainer.make()
        let friendID = UUID()
        let recordStore = FriendSharedRecordStore(modelContext: modelContainer.mainContext)
        recordStore.reconcile(
            friendID: friendID,
            plans: [
                FriendSharedPlanSnapshot(
                    id: expectedPlanID,
                    title: "Before Incremental Update",
                    startTime: Date().addingTimeInterval(600),
                    endTime: Date().addingTimeInterval(4_200)
                )
            ],
            activities: [
                FriendSharedActivitySnapshot(
                    id: expectedChapterID,
                    title: "Before Incremental Delete",
                    startTime: Date().addingTimeInterval(-3_600),
                    endTime: Date().addingTimeInterval(-300)
                )
            ]
        )
        let impact = recordStore.applyChanges(
            friendID: friendID,
            upsertPlans: plans,
            upsertChapters: [],
            deletePlanSourceIDs: [],
            deleteChapterSourceIDs: [expectedChapterID]
        )
        XCTAssertFalse(impact.affectedIntervals.isEmpty)
        try modelContainer.mainContext.save()
        let allRange = Date.distantPast..<Date.distantFuture
        let cachedPlans = recordStore.plans(friendID: friendID, overlapping: allRange)
        XCTAssertTrue(cachedPlans.contains { $0.id == expectedPlanID && $0.title == expectedUpdatedTitle })
        XCTAssertTrue(cachedPlans.contains { $0.id == expectedSecondPlanID })
        XCTAssertFalse(recordStore.chapters(friendID: friendID, overlapping: allRange).contains { $0.id == expectedChapterID })
#endif
    }

    /// Two-device live E2E step 6 (run on the owner device after the recipient stores the post-mutation token).
    /// Simulates visibility being turned off: root status is redacted and shared item records are deleted.
    func testLiveTwoDeviceOwnerRedactsShareAfterRecipientPostMutationBaseline() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(LiveE2E.ownerUserRecordNameField, from: shareMarker)
        let recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        let expectedRootRecordName = try stringField(LiveE2E.rootRecordNameField, from: shareMarker)
        let firstPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let secondPlanID = try uuidField(LiveE2E.secondPlanIDField, from: shareMarker)
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        _ = try changeToken(from: recipientMarker[LiveE2E.postMutationZoneTokenField] as? Data)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, ownerUserRecordName)

        let now = Date()
        let shareStore = CloudFriendShareStore(container: container)
        let result = try await shareStore.upsertOutgoingShare(
            snapshot: CloudFriendShareSnapshot(
                ownerUsername: "liveowner",
                ownerDisplayName: "Live Owner",
                targetUserRecordName: recipientUserRecordName,
                currentStatusTitle: "",
                currentStatusIcon: "circle.dashed",
                currentStatusColorHex: "#8E8E93",
                currentMoodText: "",
                currentStatusStartedAt: nil,
                todayScore: 0,
                yesterdayScore: 0,
                weekScore: 0,
                monthScore: 0,
                yearScore: 0,
                streakCount: 0,
                updatedAt: now
            )
        )
        XCTAssertEqual(result.rootRecordName, expectedRootRecordName)

        let outcome = await shareStore.modifySharedItems(
            targetUserRecordName: recipientUserRecordName,
            rootRecordID: result.rootRecordID,
            request: FriendShareItemModifyRequest(
                deletePlanSourceIDs: [firstPlanID, secondPlanID]
            )
        )
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(Set(outcome.appliedPlanDeletes), [firstPlanID, secondPlanID])
        shareMarker[LiveE2E.updatedAtField] = now as CKRecordValue
        _ = try await publicDatabase.save(shareMarker)
#endif
    }

    /// Two-device live E2E step 7 (run on the recipient device after the owner redacts the share).
    /// Proves visibility-off style changes arrive as incremental root update + item tombstones.
    func testLiveTwoDeviceRecipientFetchesVisibilityRedactionChanges() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(LiveE2E.ownerUserRecordNameField, from: shareMarker)
        let recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        let firstPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let secondPlanID = try uuidField(LiveE2E.secondPlanIDField, from: shareMarker)
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        let postMutationToken = try changeToken(from: recipientMarker[LiveE2E.postMutationZoneTokenField] as? Data)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, recipientUserRecordName)

        let shareStore = CloudFriendShareStore(container: container)
        let changes = try await shareStore.fetchSharedZoneChanges(
            ownerUserRecordName: ownerUserRecordName,
            previousToken: postMutationToken
        )
        XCTAssertFalse(changes.didFetchFullZone)
        let deletedPlanIDs = Set(changes.deletedRecordNames.compactMap(FriendSharedItemRecordPolicy.planSourceID(fromRecordName:)))
        XCTAssertTrue(deletedPlanIDs.isSuperset(of: [firstPlanID, secondPlanID]))
        let rootSnapshots = changes.changedRecords.compactMap {
            try? CloudFriendShareStore.incomingStatusSnapshot(from: $0, currentUserRecordName: ownRecordName)
        }
        XCTAssertTrue(rootSnapshots.contains {
            $0.currentStatusTitle.isEmpty
                && $0.currentMoodText.isEmpty
                && $0.todayScore == 0
                && $0.weekScore == 0
                && $0.streakCount == 0
        })
        recipientMarker[LiveE2E.postRedactionZoneTokenField] = try data(from: changes.changeToken) as CKRecordValue?
        recipientMarker[LiveE2E.updatedAtField] = Date() as CKRecordValue
        _ = try await publicDatabase.save(recipientMarker)

        let modelContainer = try TestModelContainer.make()
        let friendID = UUID()
        let recordStore = FriendSharedRecordStore(modelContext: modelContainer.mainContext)
        recordStore.reconcile(
            friendID: friendID,
            plans: [
                FriendSharedPlanSnapshot(
                    id: firstPlanID,
                    title: "Visible Before Redaction",
                    startTime: Date().addingTimeInterval(600),
                    endTime: Date().addingTimeInterval(4_200)
                ),
                FriendSharedPlanSnapshot(
                    id: secondPlanID,
                    title: "Also Visible Before Redaction",
                    startTime: Date().addingTimeInterval(7_200),
                    endTime: Date().addingTimeInterval(9_000)
                )
            ],
            activities: []
        )
        _ = recordStore.applyChanges(
            friendID: friendID,
            upsertPlans: [],
            upsertChapters: [],
            deletePlanSourceIDs: deletedPlanIDs,
            deleteChapterSourceIDs: []
        )
        try modelContainer.mainContext.save()
        XCTAssertTrue(recordStore.plans(friendID: friendID, overlapping: Date.distantPast..<Date.distantFuture).isEmpty)
#endif
    }

    /// Two-device live E2E step 8 (run on the recipient device after the owner redacts the share).
    /// Proves a real shared-zone full fetch can reconcile away stale local rows even when the
    /// deleted records are not represented as tombstones. This is the same app-side recovery path
    /// used after CloudKit reports `changeTokenExpired`.
    func testLiveTwoDeviceRecipientFullFetchReconcileDeletesMissingSharedItems() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareMarker = try await waitForPublicRecord(
            named: LiveE2E.shareRecordName(runID: runID),
            in: publicDatabase
        )
        let ownerUserRecordName = try stringField(LiveE2E.ownerUserRecordNameField, from: shareMarker)
        let recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        let firstPlanID = try uuidField(LiveE2E.planIDField, from: shareMarker)
        let secondPlanID = try uuidField(LiveE2E.secondPlanIDField, from: shareMarker)
        let recipientMarker = try await waitForPublicRecord(
            named: LiveE2E.recipientRecordName(runID: runID),
            in: publicDatabase
        )
        let postRedactionToken = try changeToken(from: recipientMarker[LiveE2E.postRedactionZoneTokenField] as? Data)

        let socialStore = CloudKitSocialStore(container: container)
        let ownRecordName = try await socialStore.currentUserRecordName()
        XCTAssertEqual(ownRecordName, recipientUserRecordName)

        let shareStore = CloudFriendShareStore(container: container)
        let modelContainer = try TestModelContainer.make()
        let stateStore = FriendSharePublishStateStore(modelContext: modelContainer.mainContext)
        stateStore.setChangeToken(postRedactionToken, ownerUserRecordName: ownerUserRecordName)
        try modelContainer.mainContext.save()
        XCTAssertNotNil(stateStore.changeToken(ownerUserRecordName: ownerUserRecordName))

        // Simulate the app-side recovery step used after `changeTokenExpired`: discard the stale
        // token and fetch the shared zone from scratch, then persist the replacement token.
        stateStore.clearChangeToken(ownerUserRecordName: ownerUserRecordName)
        try modelContainer.mainContext.save()
        XCTAssertNil(stateStore.changeToken(ownerUserRecordName: ownerUserRecordName))
        let fallbackChanges = try await shareStore.fetchSharedZoneChanges(
            ownerUserRecordName: ownerUserRecordName,
            previousToken: stateStore.changeToken(ownerUserRecordName: ownerUserRecordName)
        )
        XCTAssertTrue(fallbackChanges.didFetchFullZone)
        XCTAssertNotNil(fallbackChanges.changeToken)
        stateStore.setChangeToken(fallbackChanges.changeToken, ownerUserRecordName: ownerUserRecordName)
        try modelContainer.mainContext.save()
        XCTAssertNotNil(stateStore.changeToken(ownerUserRecordName: ownerUserRecordName))

        let currentPlans = fallbackChanges.changedRecords.compactMap(FriendSharedItemRecordPolicy.planSnapshot(from:))
        XCTAssertFalse(currentPlans.contains { $0.id == firstPlanID })
        XCTAssertFalse(currentPlans.contains { $0.id == secondPlanID })

        let friendID = UUID()
        let recordStore = FriendSharedRecordStore(modelContext: modelContainer.mainContext)
        recordStore.reconcile(
            friendID: friendID,
            plans: [
                FriendSharedPlanSnapshot(
                    id: firstPlanID,
                    title: "Stale Plan Before Full Fetch",
                    startTime: Date().addingTimeInterval(600),
                    endTime: Date().addingTimeInterval(4_200)
                ),
                FriendSharedPlanSnapshot(
                    id: secondPlanID,
                    title: "Second Stale Plan Before Full Fetch",
                    startTime: Date().addingTimeInterval(7_200),
                    endTime: Date().addingTimeInterval(9_000)
                )
            ],
            activities: []
        )
        let impact = recordStore.reconcile(friendID: friendID, plans: currentPlans, activities: [])
        XCTAssertTrue(impact.requiresFullReload)
        try modelContainer.mainContext.save()
        let reconciledPlans = recordStore.plans(friendID: friendID, overlapping: Date.distantPast..<Date.distantFuture)
        XCTAssertFalse(reconciledPlans.contains { $0.id == firstPlanID })
        XCTAssertFalse(reconciledPlans.contains { $0.id == secondPlanID })
#endif
    }

    /// Two-device live E2E cleanup (run on the owner device after the recipient passes).
    func testLiveTwoDeviceOwnerCleansUpShare() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let container = CKContainer(identifier: SharedModelContainer.cloudKitContainerID)
        let publicDatabase = container.publicCloudDatabase
        let shareRecordID = CKRecord.ID(recordName: LiveE2E.shareRecordName(runID: runID))
        let recipientRecordID = CKRecord.ID(recordName: LiveE2E.recipientRecordName(runID: runID))
        let shareMarker = try await fetchPublicRecordIfExists(shareRecordID, from: publicDatabase)
        let recipientMarker = try await fetchPublicRecordIfExists(recipientRecordID, from: publicDatabase)
        let recipientUserRecordName: String
        if let shareMarker {
            recipientUserRecordName = try stringField(LiveE2E.recipientUserRecordNameField, from: shareMarker)
        } else if let recipientMarker {
            recipientUserRecordName = try stringField(LiveE2E.userRecordNameField, from: recipientMarker)
        } else {
            throw CloudKitSocialError.requestNotFound
        }
        try await CloudFriendShareStore(container: container).revokeOutgoingShare(
            targetUserRecordName: recipientUserRecordName
        )
        try await deletePublicRecordIfExists(shareRecordID, from: publicDatabase)
#endif
    }

    /// Two-device live E2E cleanup (run on the recipient device after owner cleanup).
    func testLiveTwoDeviceRecipientCleansUpMarker() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Live CloudKit E2E requires signed apps on two real iOS devices.")
#else
        let runID = try requireLiveE2ERunID()
        let publicDatabase = CKContainer(identifier: SharedModelContainer.cloudKitContainerID).publicCloudDatabase
        try await deletePublicRecordIfExists(
            CKRecord.ID(recordName: LiveE2E.recipientRecordName(runID: runID)),
            from: publicDatabase
        )
#endif
    }

    private func requireLiveE2ERunID() throws -> String {
        guard let runID = LiveE2E.runID else {
            throw XCTSkip("Set \(LiveE2E.runIDKey) to run the two-device live CloudKit E2E steps.")
        }
        return runID
    }

    private func waitForPublicRecord(
        named recordName: String,
        in database: CKDatabase,
        timeout: TimeInterval = 60
    ) async throws -> CKRecord {
        let deadline = Date().addingTimeInterval(timeout)
        let recordID = CKRecord.ID(recordName: recordName)
        var lastError: Error?
        while Date() < deadline {
            do {
                if let record = try await fetchPublicRecordIfExists(recordID, from: database) {
                    return record
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if let lastError {
            throw lastError
        }
        throw CloudKitSocialError.requestNotFound
    }

    private func fetchPublicRecordIfExists(_ recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord? {
        do {
            let results = try await database.records(for: [recordID], desiredKeys: nil)
            guard let result = results[recordID] else { return nil }
            return try result.get()
        } catch {
            guard CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(error) else {
                throw error
            }
            return nil
        }
    }

    private func deletePublicRecordIfExists(_ recordID: CKRecord.ID, from database: CKDatabase) async throws {
        guard try await fetchPublicRecordIfExists(recordID, from: database) != nil else { return }
        _ = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: true
        )
    }

    private func stringField(_ field: String, from record: CKRecord) throws -> String {
        guard let value = record[field] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CloudKitSocialError.missingRecordField(field)
        }
        return value
    }

    private func uuidField(_ field: String, from record: CKRecord) throws -> UUID {
        let rawValue = try stringField(field, from: record)
        guard let uuid = UUID(uuidString: rawValue) else {
            throw CloudKitSocialError.missingRecordField(field)
        }
        return uuid
    }

    private func data(from token: CKServerChangeToken?) throws -> Data? {
        guard let token else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private func changeToken(from data: Data?) throws -> CKServerChangeToken {
        guard let data,
              let token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
              )
        else {
            throw CloudKitSocialError.missingRecordField(LiveE2E.baselineZoneTokenField)
        }
        return token
    }

    private static func makeBulkPlans(count: Int, now: Date) -> [FriendSharedPlanSnapshot] {
        (0..<count).map { index in
            let start = now.addingTimeInterval(TimeInterval(index) * 900)
            return FriendSharedPlanSnapshot(
                title: "Bulk Plan \(index)",
                startTime: start,
                endTime: start.addingTimeInterval(1_800),
                isImportant: index.isMultiple(of: 5),
                categoryTitle: "Bulk",
                categoryIconName: "calendar",
                categoryColorHex: "#2F80ED",
                updatedAt: now
            )
        }
    }

    private static func makeBulkChapters(count: Int, now: Date) -> [FriendSharedActivitySnapshot] {
        (0..<count).map { index in
            let start = now.addingTimeInterval(-TimeInterval(index + 1) * 1_200)
            return FriendSharedActivitySnapshot(
                title: "Bulk Chapter \(index)",
                startTime: start,
                endTime: start.addingTimeInterval(900),
                categoryTitle: "Bulk",
                categoryIconName: "circle.fill",
                categoryColorHex: "#34C759",
                note: index.isMultiple(of: 10) ? "bulk note \(index)" : nil,
                mood: index.isMultiple(of: 7) ? "focused" : nil,
                updatedAt: now
            )
        }
    }
}

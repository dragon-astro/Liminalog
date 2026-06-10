import CloudKit
import XCTest
@testable import Liminalog

final class CloudKitLiveDeviceSmokeTests: XCTestCase {
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
}

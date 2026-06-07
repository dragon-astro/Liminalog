import CloudKit
import XCTest
@testable import Liminalog

final class CloudKitLiveDeviceSmokeTests: XCTestCase {
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

        let missingUsername = "codex_missing_\(UUID().uuidString)"
        do {
            _ = try await store.fetchProfile(username: missingUsername)
            XCTFail("A random smoke-test username should not resolve to a CloudKit profile.")
        } catch CloudKitSocialError.profileNotFound {
            // Expected: the public database is reachable and returns a normal not-found result.
        }
#endif
    }
}

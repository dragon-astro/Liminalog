import CloudKit
import Foundation
import Testing
@testable import Liminalog

@Suite("CloudKitCurrentUserRecordResolver")
struct CloudKitCurrentUserRecordResolverTests {
    @Test
    func cachesAvailableCurrentUserRecordID() async throws {
        let probe = CurrentUserRecordProbe(recordNames: ["_current"])
        let resolver = CloudKitCurrentUserRecordResolver(
            accountStatusProvider: { try await probe.accountStatus() },
            userRecordIDProvider: { try await probe.userRecordID() },
            notificationCenter: NotificationCenter()
        )

        let first = try await resolver.currentUserRecordID()
        let second = try await resolver.currentUserRecordID()
        let counts = await probe.counts()

        #expect(first.recordName == "_current")
        #expect(second.recordName == "_current")
        #expect(counts.accountStatus == 1)
        #expect(counts.userRecordID == 1)
    }

    @Test
    func accountChangedNotificationInvalidatesCachedRecordID() async throws {
        let center = NotificationCenter()
        let probe = CurrentUserRecordProbe(recordNames: ["_before", "_after"])
        let resolver = CloudKitCurrentUserRecordResolver(
            accountStatusProvider: { try await probe.accountStatus() },
            userRecordIDProvider: { try await probe.userRecordID() },
            notificationCenter: center
        )

        let first = try await resolver.currentUserRecordID()
        center.post(name: Notification.Name.CKAccountChanged, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        let second = try await resolver.currentUserRecordID()
        let counts = await probe.counts()

        #expect(first.recordName == "_before")
        #expect(second.recordName == "_after")
        #expect(counts.accountStatus == 2)
        #expect(counts.userRecordID == 2)
    }

    @Test
    func unavailableAccountDoesNotCacheFailure() async throws {
        let probe = CurrentUserRecordProbe(
            statuses: [.noAccount, .available],
            recordNames: ["_current"]
        )
        let resolver = CloudKitCurrentUserRecordResolver(
            accountStatusProvider: { try await probe.accountStatus() },
            userRecordIDProvider: { try await probe.userRecordID() },
            notificationCenter: NotificationCenter()
        )

        do {
            _ = try await resolver.currentUserRecordID()
            Issue.record("Expected unavailable account to throw")
        } catch CloudKitCurrentUserRecordError.accountUnavailable {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let recovered = try await resolver.currentUserRecordID()
        let counts = await probe.counts()

        #expect(recovered.recordName == "_current")
        #expect(counts.accountStatus == 2)
        #expect(counts.userRecordID == 1)
    }
}

private actor CurrentUserRecordProbe {
    private var statuses: [CKAccountStatus]
    private var recordNames: [String]
    private var accountStatusCallCount = 0
    private var userRecordIDCallCount = 0

    init(
        statuses: [CKAccountStatus] = [.available],
        recordNames: [String]
    ) {
        self.statuses = statuses
        self.recordNames = recordNames
    }

    func accountStatus() throws -> CKAccountStatus {
        accountStatusCallCount += 1
        if statuses.count > 1 {
            return statuses.removeFirst()
        }
        return statuses.first ?? .available
    }

    func userRecordID() throws -> CKRecord.ID {
        userRecordIDCallCount += 1
        let recordName = recordNames.isEmpty ? "_current" : recordNames.removeFirst()
        return CKRecord.ID(recordName: recordName)
    }

    func counts() -> (accountStatus: Int, userRecordID: Int) {
        (accountStatusCallCount, userRecordIDCallCount)
    }
}

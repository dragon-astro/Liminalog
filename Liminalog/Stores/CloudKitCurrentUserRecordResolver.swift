import CloudKit
import Foundation

enum CloudKitCurrentUserRecordError: Error {
    case accountUnavailable
}

final class CloudKitCurrentUserRecordResolver: @unchecked Sendable {
    typealias AccountStatusProvider = @Sendable () async throws -> CKAccountStatus
    typealias UserRecordIDProvider = @Sendable () async throws -> CKRecord.ID

    private static let defaultContainerID = "iCloud.app.YasudaRyuga.Liminalog"

    static let shared: CloudKitCurrentUserRecordResolver = {
        let container = CKContainer(identifier: defaultContainerID)
        return CloudKitCurrentUserRecordResolver(container: container)
    }()

    private let accountStatusProvider: AccountStatusProvider
    private let userRecordIDProvider: UserRecordIDProvider
    private let notificationCenter: NotificationCenter
    private let cache: CloudKitCurrentUserRecordCache
    private let accountChangedObserver: NSObjectProtocol

    convenience init(
        container: CKContainer,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            accountStatusProvider: { try await container.accountStatus() },
            userRecordIDProvider: {
                try await withCheckedThrowingContinuation { continuation in
                    container.fetchUserRecordID { recordID, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let recordID else {
                            continuation.resume(throwing: CloudKitCurrentUserRecordError.accountUnavailable)
                            return
                        }
                        continuation.resume(returning: recordID)
                    }
                }
            },
            notificationCenter: notificationCenter
        )
    }

    init(
        accountStatusProvider: @escaping AccountStatusProvider,
        userRecordIDProvider: @escaping UserRecordIDProvider,
        notificationCenter: NotificationCenter = .default
    ) {
        let cache = CloudKitCurrentUserRecordCache()
        self.accountStatusProvider = accountStatusProvider
        self.userRecordIDProvider = userRecordIDProvider
        self.notificationCenter = notificationCenter
        self.cache = cache
        self.accountChangedObserver = notificationCenter.addObserver(
            forName: Notification.Name.CKAccountChanged,
            object: nil,
            queue: nil
        ) { _ in
            Task { await cache.invalidate() }
        }
    }

    deinit {
        notificationCenter.removeObserver(accountChangedObserver)
    }

    func currentUserRecordID() async throws -> CKRecord.ID {
        if let cachedRecordID = await cache.recordID() {
            return cachedRecordID
        }
        let status = try await accountStatusProvider()
        guard status == .available else {
            await cache.invalidate()
            throw CloudKitCurrentUserRecordError.accountUnavailable
        }
        do {
            let recordID = try await userRecordIDProvider()
            await cache.store(recordID)
            return recordID
        } catch {
            await cache.invalidate()
            throw error
        }
    }

    func invalidate() async {
        await cache.invalidate()
    }
}

private actor CloudKitCurrentUserRecordCache {
    private var cachedRecordID: CKRecord.ID?

    func recordID() -> CKRecord.ID? {
        cachedRecordID
    }

    func store(_ recordID: CKRecord.ID) {
        cachedRecordID = recordID
    }

    func invalidate() {
        cachedRecordID = nil
    }
}

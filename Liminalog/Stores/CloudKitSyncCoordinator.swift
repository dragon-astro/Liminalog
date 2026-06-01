import CloudKit
import Combine
import Foundation

@MainActor
final class CloudKitSyncCoordinator: ObservableObject {
    enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case couldNotDetermine
        case temporarilyUnavailable
        case failed(String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        var userMessage: String? {
            switch self {
            case .unknown, .available:
                return nil
            case .noAccount:
                return "iCloudにサインインすると友達との同期が使えます。"
            case .restricted:
                return "この端末ではiCloud同期が制限されています。"
            case .couldNotDetermine:
                return "iCloudの状態を確認できませんでした。時間をおいて再試行してください。"
            case .temporarilyUnavailable:
                return "iCloud同期が一時的に利用できません。"
            case let .failed(message):
                return message
            }
        }
    }

    static let containerID = "iCloud.app.YasudaRyuga.Liminalog"

    private let container: CKContainer
    @Published private(set) var accountState: AccountState = .unknown
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastError: String?

    init(container: CKContainer = CKContainer(identifier: "iCloud.app.YasudaRyuga.Liminalog")) {
        self.container = container
    }

    func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            accountState = Self.map(status)
            lastError = accountState.userMessage
            lastCheckedAt = Date()
        } catch {
            let message = "iCloud同期状態の確認に失敗しました: \(error.localizedDescription)"
            accountState = .failed(message)
            lastError = message
            lastCheckedAt = Date()
        }
    }

    private static func map(_ status: CKAccountStatus) -> AccountState {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .couldNotDetermine
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .couldNotDetermine
        }
    }
}

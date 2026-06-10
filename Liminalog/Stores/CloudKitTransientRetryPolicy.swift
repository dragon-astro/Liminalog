import CloudKit
import Foundation

/// CloudKit の一時的エラー（Zone Busy / レート制限 / 一時障害）のリトライ判断。
/// サーバーが `CKErrorRetryAfterKey` で待ち時間を指定してくるため、それに従う。
/// 実機検証で `zoneBusy`（"Failed to provide read-consistent view", Retry after 2.0s）を観測済み。
enum CloudKitTransientRetryPolicy {
    /// 初回を含めた最大試行回数。
    static let maxAttempts = 3
    private static let maxDelaySeconds: TimeInterval = 30

    /// リトライすべきなら待ち時間（秒）を返す。リトライ不要・上限到達なら nil。
    /// - Parameter attempt: いま失敗した試行が何回目か（1始まり）。
    static func retryDelay(after error: Error, attempt: Int) -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .zoneBusy, .serviceUnavailable, .requestRateLimited:
            let suggested = ckError.retryAfterSeconds ?? pow(2, Double(attempt))
            return min(max(suggested, 1), maxDelaySeconds)
        default:
            return nil
        }
    }
}

extension CloudFriendShareStore {
    /// 一時的エラーをサーバー指定の待ち時間でリトライする。恒久的エラーは即座に投げる。
    func withTransientRetry<Value>(
        _ label: String,
        operation: () async throws -> Value
    ) async throws -> Value {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard let delay = CloudKitTransientRetryPolicy.retryDelay(after: error, attempt: attempt) else {
                    throw error
                }
                NSLog("Liminalog: retrying \(label) in \(delay)s after transient CloudKit error (attempt \(attempt)): \(String(describing: error))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }
}

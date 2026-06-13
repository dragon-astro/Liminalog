import CryptoKit
import Foundation

/// 公開済み台帳（指紋）とローカルの可視セットを突き合わせ、CloudKit へ送る差分を決める純ロジック。
/// docs/20 §2.1 の「オーナー側の追加/編集/削除を Shared* レコードへ upsert/delete 同期」の中核。
enum FriendSharePublishDiffPolicy {
    struct Plan: Equatable {
        /// 新規または内容が変わったアイテム。CloudKit へ upsert する。
        var upsertSourceIDs: Set<UUID> = []
        /// ローカルの可視セットから消えたアイテム。CloudKit のレコードを削除する。
        var deleteSourceIDs: Set<UUID> = []

        var isEmpty: Bool {
            upsertSourceIDs.isEmpty && deleteSourceIDs.isEmpty
        }
    }

    /// - Parameters:
    ///   - desired: いま公開したい sourceID → 指紋（可視性フィルタ済み）。
    ///   - published: 公開済み台帳の sourceID → 指紋。
    static func plan(desired: [UUID: String], published: [UUID: String]) -> Plan {
        var result = Plan()
        for (sourceID, fingerprint) in desired where published[sourceID] != fingerprint {
            result.upsertSourceIDs.insert(sourceID)
        }
        for sourceID in published.keys where desired[sourceID] == nil {
            result.deleteSourceIDs.insert(sourceID)
        }
        return result
    }

    // MARK: - 指紋

    /// プロセスを跨いで安定な内容ハッシュ。`Hasher` はシードが起動ごとに変わるため使わない。
    static func fingerprint(_ snapshot: FriendSharedPlanSnapshot) -> String {
        stableFingerprint(of: snapshot)
    }

    static func fingerprint(_ snapshot: FriendSharedActivitySnapshot) -> String {
        stableFingerprint(of: snapshot)
    }

    static func fingerprint(_ snapshot: FriendSharedDailyScoreSnapshot) -> String {
        stableFingerprint(of: snapshot)
    }

    private static func stableFingerprint<Value: Encodable>(of value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return UUID().uuidString }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

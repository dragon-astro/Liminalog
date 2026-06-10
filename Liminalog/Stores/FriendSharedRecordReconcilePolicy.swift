import Foundation

/// 受信した共有スナップショットと、ローカルの個別行キャッシュの突合計画（docs/20 §2.2）。
/// `sourceID` をキーに insert / update / delete を決める純ロジック。
/// 将来 CloudKit の差分同期（ゾーン変更トークン）に置き換わっても、この突合はそのまま使える。
enum FriendSharedRecordReconcilePolicy {
    struct ExistingRecord: Equatable {
        let sourceID: UUID
        let updatedAt: Date

        init(sourceID: UUID, updatedAt: Date) {
            self.sourceID = sourceID
            self.updatedAt = updatedAt
        }
    }

    struct Incoming: Equatable {
        let sourceID: UUID
        let updatedAt: Date

        init(sourceID: UUID, updatedAt: Date) {
            self.sourceID = sourceID
            self.updatedAt = updatedAt
        }
    }

    struct Plan: Equatable {
        /// ローカルに無い sourceID。新規行として挿入する。
        var insertSourceIDs: Set<UUID> = []
        /// ローカルより新しい更新が来ている sourceID。フィールドを上書きする。
        var updateSourceIDs: Set<UUID> = []
        /// 受信側に存在しない sourceID。オーナーが削除（または可視性で除外）したので行を消す。
        var deleteSourceIDs: Set<UUID> = []
    }

    /// 全量スナップショット受信時の突合（塊JSON経由・初回全件取得時）。
    /// 受信スナップショットを正としてローカル行を一致させる。
    static func plan(existing: [ExistingRecord], incoming: [Incoming]) -> Plan {
        var result = Plan()
        let existingBySourceID = Dictionary(
            existing.map { ($0.sourceID, $0.updatedAt) },
            uniquingKeysWith: { lhs, rhs in min(lhs, rhs) }
        )
        var incomingSourceIDs = Set<UUID>()
        incomingSourceIDs.reserveCapacity(incoming.count)

        for record in incoming {
            // 同じ sourceID が重複して届いた場合は最初の1件だけを反映する。
            guard incomingSourceIDs.insert(record.sourceID).inserted else { continue }
            guard let existingUpdatedAt = existingBySourceID[record.sourceID] else {
                result.insertSourceIDs.insert(record.sourceID)
                continue
            }
            if record.updatedAt > existingUpdatedAt {
                result.updateSourceIDs.insert(record.sourceID)
            }
        }

        for record in existing where !incomingSourceIDs.contains(record.sourceID) {
            result.deleteSourceIDs.insert(record.sourceID)
        }
        return result
    }
}

import CloudKit
import Foundation
import SwiftData

/// 友達共有の同期状態（公開台帳・受信トークン）の読み書き。
/// 呼び出し側で `modelContext.save()` すること。
@MainActor
struct FriendSharePublishStateStore {
    static let planKind = "plan"
    static let chapterKind = "chapter"
    static let scoreKind = "score"
    private static let batchedSourceIDFetchThreshold = 24

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 公開台帳（オーナー側）

    func publishedFingerprints(targetUserRecordName: String, kind: String) -> [UUID: String] {
        let items = compactPublishedItems(fetchPublishedItems(targetUserRecordName: targetUserRecordName, kind: kind))
        return Dictionary(items.map { ($0.sourceID, $0.fingerprint) }, uniquingKeysWith: { lhs, _ in lhs })
    }

    func publishedFingerprints(targetUserRecordName: String, kind: String, sourceIDs: Set<UUID>) -> [UUID: String] {
        guard !sourceIDs.isEmpty else { return [:] }
        let items = sourceIDs.count > Self.batchedSourceIDFetchThreshold
            ? fetchPublishedItems(targetUserRecordName: targetUserRecordName, kind: kind)
                .filter { sourceIDs.contains($0.sourceID) }
            : sourceIDs.compactMap { sourceID in
                fetchPublishedItem(targetUserRecordName: targetUserRecordName, kind: kind, sourceID: sourceID)
            }
        return Dictionary(compactPublishedItems(items).map { ($0.sourceID, $0.fingerprint) }, uniquingKeysWith: { lhs, _ in lhs })
    }

    /// CloudKit への送信が成功した分だけ台帳へ反映する。
    func applyPublishResult(
        targetUserRecordName: String,
        kind: String,
        upserted: [UUID: String],
        deleted: Set<UUID>
    ) {
        guard !upserted.isEmpty || !deleted.isEmpty else { return }
        let existing = compactPublishedItems(fetchPublishedItems(targetUserRecordName: targetUserRecordName, kind: kind))
        let existingBySourceID = Dictionary(
            existing.map { ($0.sourceID, $0) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        for (sourceID, fingerprint) in upserted {
            if let item = existingBySourceID[sourceID] {
                item.fingerprint = fingerprint
            } else {
                modelContext.insert(FriendSharePublishedItem(
                    targetUserRecordName: targetUserRecordName,
                    kindRawValue: kind,
                    sourceID: sourceID,
                    fingerprint: fingerprint
                ))
            }
        }
        for sourceID in deleted {
            guard let item = existingBySourceID[sourceID] else { continue }
            modelContext.delete(item)
        }
    }

    /// 共有ルートを作り直した時などに台帳を破棄して全量再公開させる。
    func clearPublishedItems(targetUserRecordName: String) {
        try? modelContext.delete(
            model: FriendSharePublishedItem.self,
            where: #Predicate { $0.targetUserRecordName == targetUserRecordName }
        )
    }

    private func fetchPublishedItems(targetUserRecordName: String, kind: String) -> [FriendSharePublishedItem] {
        (try? modelContext.fetch(
            FetchDescriptor<FriendSharePublishedItem>(
                predicate: #Predicate {
                    $0.targetUserRecordName == targetUserRecordName && $0.kindRawValue == kind
                }
            )
        )) ?? []
    }

    private func fetchPublishedItem(targetUserRecordName: String, kind: String, sourceID: UUID) -> FriendSharePublishedItem? {
        let descriptor = FetchDescriptor<FriendSharePublishedItem>(
            predicate: #Predicate {
                $0.targetUserRecordName == targetUserRecordName
                    && $0.kindRawValue == kind
                    && $0.sourceID == sourceID
            }
        )
        return compactPublishedItems((try? modelContext.fetch(descriptor)) ?? []).first
    }

    // MARK: - ゾーン変更トークン（受信側）

    func changeToken(ownerUserRecordName: String) -> CKServerChangeToken? {
        guard let state = fetchSyncState(ownerUserRecordName: ownerUserRecordName),
              let data = state.changeTokenData
        else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func setChangeToken(_ token: CKServerChangeToken?, ownerUserRecordName: String) {
        let state: FriendShareZoneSyncState
        if let existing = fetchSyncState(ownerUserRecordName: ownerUserRecordName) {
            state = existing
        } else {
            state = FriendShareZoneSyncState(ownerUserRecordName: ownerUserRecordName)
            modelContext.insert(state)
        }
        state.changeTokenData = token.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        state.updatedAt = Date()
    }

    func clearChangeToken(ownerUserRecordName: String) {
        guard let state = fetchSyncState(ownerUserRecordName: ownerUserRecordName) else { return }
        state.changeTokenData = nil
        state.updatedAt = Date()
    }

    private func fetchSyncState(ownerUserRecordName: String) -> FriendShareZoneSyncState? {
        let descriptor = FetchDescriptor<FriendShareZoneSyncState>(
            predicate: #Predicate { $0.ownerUserRecordName == ownerUserRecordName }
        )
        return compactSyncStates((try? modelContext.fetch(descriptor)) ?? []).first
    }

    private func compactPublishedItems(_ items: [FriendSharePublishedItem]) -> [FriendSharePublishedItem] {
        var keptByKey: [FriendSharePublishedItemKey: FriendSharePublishedItem] = [:]
        for item in items {
            let key = FriendSharePublishedItemKey(
                targetUserRecordName: item.targetUserRecordName,
                kindRawValue: item.kindRawValue,
                sourceID: item.sourceID
            )
            if keptByKey[key] != nil {
                modelContext.delete(item)
                continue
            }
            keptByKey[key] = item
        }
        return Array(keptByKey.values)
    }

    private func compactSyncStates(_ states: [FriendShareZoneSyncState]) -> [FriendShareZoneSyncState] {
        var keptByOwner: [String: FriendShareZoneSyncState] = [:]
        for state in states {
            if let kept = keptByOwner[state.ownerUserRecordName] {
                if state.updatedAt > kept.updatedAt {
                    modelContext.delete(kept)
                    keptByOwner[state.ownerUserRecordName] = state
                } else {
                    modelContext.delete(state)
                }
            } else {
                keptByOwner[state.ownerUserRecordName] = state
            }
        }
        return Array(keptByOwner.values)
    }
}

private struct FriendSharePublishedItemKey: Hashable {
    let targetUserRecordName: String
    let kindRawValue: String
    let sourceID: UUID
}

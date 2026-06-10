import Foundation
import SwiftData

/// CloudKit 同期で発生する重複データの統合。
///
/// シードを持つ CloudKit 同期アプリの宿命: 各端末が独立にデフォルト（カテゴリ・セット等）を
/// シードし、後からお互いのレコードがインポートされて合流すると重複が生まれる。
/// 「どの端末で実行しても同じ勝者を選ぶ」決定的ルールで統合し、敗者の削除は
/// CloudKit ミラーリングで全端末へ伝播して収束する。
///
/// 勝者ルール: createdAt が最古 → 同時刻なら id(UUID文字列) が最小。
/// 起動時（bootstrap）とシーンactive時に冪等に実行する。
@MainActor
struct CloudDuplicateMergeStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// すべての重複統合を実行し、統合（削除）した件数を返す。
    @discardableResult
    func mergeAll() -> Int {
        var merged = 0
        merged += mergeUserSettings()
        merged += mergeFriends()
        merged += mergeCategories()
        merged += mergeCategorySets()
        merged += mergeFriendSets()
        if merged > 0 {
            do {
                try modelContext.save()
                NSLog("Liminalog: merged \(merged) duplicated records from CloudKit import")
            } catch {
                NSLog("Liminalog: failed to save duplicate merge: \(String(describing: error))")
                modelContext.rollback()
                return 0
            }
        }
        return merged
    }

    // MARK: - UserSettings（シングルトン）

    private func mergeUserSettings() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<UserSettings>())) ?? []
        guard all.count > 1 else { return 0 }
        // ユーザーID確定済みの行を最優先（消すとID再確定が必要になるため）。次に勝者ルール。
        let winner = all.min { lhs, rhs in
            let lhsHasID = !lhs.cloudUsernameNormalized.isEmpty
            let rhsHasID = !rhs.cloudUsernameNormalized.isEmpty
            if lhsHasID != rhsHasID { return lhsHasID }
            return isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
        }
        var merged = 0
        for settings in all where settings !== winner {
            modelContext.delete(settings)
            merged += 1
        }
        return merged
    }

    // MARK: - Friend（userRecordID で同一人物）

    private func mergeFriends() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<Friend>())) ?? []
        let groups = Dictionary(grouping: all.filter { !$0.userRecordID.isEmpty }, by: \.userRecordID)
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            // accepted を最優先（共有状態を失わないため）。次に勝者ルール。
            let winner = group.min { lhs, rhs in
                let lhsAccepted = lhs.status == .accepted
                let rhsAccepted = rhs.status == .accepted
                if lhsAccepted != rhsAccepted { return lhsAccepted }
                return isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                if winner.visibilityPresetID == nil {
                    winner.visibilityPresetID = loser.visibilityPresetID
                }
                if winner.shareURL == nil {
                    winner.shareURL = loser.shareURL
                }
                repointFriendReferences(from: loser.id, to: winner.id)
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    /// 敗者の friendID を参照している行キャッシュ・観客スナップショット・友達セットを勝者へ付け替える。
    private func repointFriendReferences(from loserID: UUID, to winnerID: UUID) {
        let recordStore = FriendSharedRecordStore(modelContext: modelContext)
        recordStore.repointRows(from: loserID, to: winnerID)

        let friendSets = (try? modelContext.fetch(FetchDescriptor<FriendSet>())) ?? []
        for set in friendSets where set.memberFriendIDs.contains(loserID) {
            var members = set.memberFriendIDs.filter { $0 != loserID }
            if !members.contains(winnerID) {
                members.append(winnerID)
            }
            set.memberFriendIDs = members
        }

        // UUID配列への contains は #Predicate 未対応のため、メモリ内でフィルタする（統合時のみの低頻度処理）。
        let plans = (try? modelContext.fetch(FetchDescriptor<PlanBlock>())) ?? []
        for plan in plans where plan.audienceFriendIDs.contains(loserID) {
            plan.audienceFriendIDs = plan.audienceFriendIDs.map { $0 == loserID ? winnerID : $0 }
        }
        let chapters = (try? modelContext.fetch(FetchDescriptor<Chapter>())) ?? []
        for chapter in chapters where chapter.audienceFriendIDs.contains(loserID) {
            chapter.audienceFriendIDs = chapter.audienceFriendIDs.map { $0 == loserID ? winnerID : $0 }
        }
    }

    // MARK: - Category（isDefault × 名前で同一視）

    private func mergeCategories() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let groups = Dictionary(grouping: all) { category in
            "\(category.isDefault ? "default" : "custom"):\(normalizedName(category.name))"
        }
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.min { lhs, rhs in
                isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                for chapter in loser.chapters ?? [] {
                    chapter.category = winner
                }
                for plan in loser.plans ?? [] {
                    plan.category = winner
                }
                repointCategoryReferences(from: loser.id, to: winner.id)
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    private func repointCategoryReferences(from loserID: UUID, to winnerID: UUID) {
        let sets = (try? modelContext.fetch(FetchDescriptor<CategorySet>())) ?? []
        for set in sets where set.slots.contains(loserID) {
            set.slots = set.slots.map { slot in
                guard slot == loserID else { return slot }
                // 勝者が既に別スロットにいる場合は空ける（同セット内の重複を避ける）。
                return set.slots.contains(winnerID) ? nil : winnerID
            }
        }
        let mappings = (try? modelContext.fetch(
            FetchDescriptor<FriendCategoryMapping>(predicate: #Predicate { $0.myCategoryID == loserID })
        )) ?? []
        for mapping in mappings {
            mapping.myCategoryID = winnerID
        }
    }

    // MARK: - CategorySet（isDefault × 名前）

    private func mergeCategorySets() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<CategorySet>())) ?? []
        let groups = Dictionary(grouping: all) { set in
            "\(set.isDefault ? "default" : "custom"):\(normalizedName(set.name))"
        }
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.min { lhs, rhs in
                isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                if winner.filledCount == 0, loser.filledCount > 0 {
                    winner.slots = loser.slots
                }
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    // MARK: - FriendSet（名前）

    private func mergeFriendSets() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<FriendSet>())) ?? []
        let groups = Dictionary(grouping: all) { normalizedName($0.name) }
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.min { lhs, rhs in
                isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                for member in loser.memberFriendIDs where !winner.memberFriendIDs.contains(member) {
                    winner.memberFriendIDs.append(member)
                }
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    // MARK: - 勝者ルール

    /// 全端末で同じ勝者を選ぶための決定的な順序。createdAt 最古 → id 最小。
    private func isPreferred(_ lhsDate: Date, _ lhsID: String, over rhsDate: Date, _ rhsID: String) -> Bool {
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhsID < rhsID
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }
}

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
        merge(includeTimelineRecords: true)
    }

    /// 復帰時の軽量統合。シード・設定・友達などの小さなマスターデータを整え、
    /// 長期履歴で伸びる Plan/Chapter の全件重複検査は background/idle の `mergeAll` に任せる。
    /// 友達共有の行キャッシュ重複は表示に出やすいため、軽量側で回収する。
    @discardableResult
    func mergeLightweight() -> Int {
        merge(includeTimelineRecords: false)
    }

    @discardableResult
    private func merge(includeTimelineRecords: Bool) -> Int {
        ensureBuiltInVisibilityPresetsIfNeeded()

        var merged = 0
        merged += mergeUserSettings()
        merged += mergeFriends()
        merged += mergeCategories()
        merged += mergeCategorySets()
        if includeTimelineRecords {
            merged += mergeChapters()
            merged += mergePlanBlocks()
        }
        merged += purgeFriendSharedRecordDuplicates()
        merged += mergeFriendSets()
        merged += repairDanglingReferences(includeTimelineRecords: includeTimelineRecords)
        if merged > 0 {
            do {
                try modelContext.save()
                NSLog("Liminalog: merged or repaired \(merged) records from CloudKit import")
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
            if let winner {
                mergeScoreLedger(from: settings, into: winner)
            }
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
            merged += mergeFriendGroup(group)
        }

        let remaining = (try? modelContext.fetch(FetchDescriptor<Friend>())) ?? []
        let usernameGroups = Dictionary(grouping: remaining, by: normalizedFriendUsername)
        for (username, group) in usernameGroups where !username.isEmpty && group.count > 1 {
            merged += mergeFriendGroup(group)
        }
        return merged
    }

    private func mergeFriendGroup(_ group: [Friend]) -> Int {
        // accepted を最優先（共有状態を失わないため）。次にCloudKit record IDがある行、最後に勝者ルール。
        let winner = group.min { lhs, rhs in
            let lhsAccepted = lhs.status == .accepted
            let rhsAccepted = rhs.status == .accepted
            if lhsAccepted != rhsAccepted { return lhsAccepted }
            let lhsHasRecord = !lhs.userRecordID.isEmpty
            let rhsHasRecord = !rhs.userRecordID.isEmpty
            if lhsHasRecord != rhsHasRecord { return lhsHasRecord }
            return isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
        }
        guard let winner else { return 0 }

        var merged = 0
        for loser in group where loser !== winner {
            mergeFriend(loser, into: winner)
            repointFriendReferences(from: loser.id, to: winner.id)
            modelContext.delete(loser)
            merged += 1
        }
        return merged
    }

    private func mergeFriend(_ duplicate: Friend, into primary: Friend) {
        if primary.userRecordID.isEmpty {
            primary.userRecordID = duplicate.userRecordID
        }
        if primary.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            primary.displayName = duplicate.displayName
        }
        if primary.handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            primary.handle = duplicate.handle
        }
        if primary.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            primary.inviteCode = duplicate.inviteCode
        }
        if primary.visibilityPresetID == nil {
            primary.visibilityPresetID = duplicate.visibilityPresetID
        }
        if primary.shareURL == nil {
            primary.shareURL = duplicate.shareURL
        }
        primary.isFavorite = primary.isFavorite || duplicate.isFavorite
        if primary.acceptedAt == nil {
            primary.acceptedAt = duplicate.acceptedAt
        }
        if primary.lastSeenAt == nil {
            primary.lastSeenAt = duplicate.lastSeenAt
        }
        if duplicate.updatedAt > primary.updatedAt {
            primary.updatedAt = duplicate.updatedAt
        }
    }

    private func mergeScoreLedger(from duplicate: UserSettings, into primary: UserSettings) {
        guard duplicate.isFinalizedScoreLedgerInitialized else { return }
        if !primary.isFinalizedScoreLedgerInitialized {
            primary.finalizedCumulativeScore = duplicate.finalizedCumulativeScore
            primary.finalizedScoreReconciledThroughDayStart = duplicate.finalizedScoreReconciledThroughDayStart
            primary.isFinalizedScoreLedgerInitialized = true
            return
        }

        if let duplicateThrough = duplicate.finalizedScoreReconciledThroughDayStart,
           (primary.finalizedScoreReconciledThroughDayStart ?? Date.distantPast) < duplicateThrough {
            primary.finalizedCumulativeScore = max(primary.finalizedCumulativeScore, duplicate.finalizedCumulativeScore)
            primary.finalizedScoreReconciledThroughDayStart = duplicateThrough
        } else {
            primary.finalizedCumulativeScore = max(primary.finalizedCumulativeScore, duplicate.finalizedCumulativeScore)
        }
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

    /// CloudKit の差分インポート直後に一時的に残る友達共有行キャッシュの重複を回収する。
    /// LocalCache の派生データだけを対象にし、元の予定・実績レコードは触らない。
    private func purgeFriendSharedRecordDuplicates() -> Int {
        FriendSharedRecordStore(modelContext: modelContext).purgeDuplicateRecords()
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
                mergeCategory(loser, into: winner)
                for chapter in loser.chapters ?? [] {
                    chapter.category = winner
                }
                for plan in loser.plans ?? [] {
                    plan.category = winner
                }
                repointCategoryReferences(from: loser.id, to: winner.id)
                resolveCategoryValueFaults(loser)
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    private func mergeCategory(_ duplicate: Category, into primary: Category) {
        if primary.icon == nil {
            primary.icon = duplicate.icon
        }
        if primary.dailyCardIntent == .neutral, duplicate.dailyCardIntent != .neutral {
            primary.dailyCardIntent = duplicate.dailyCardIntent
        }
        primary.isDailyCardSleepCategory = primary.isDailyCardSleepCategory || duplicate.isDailyCardSleepCategory
        primary.defaultAudienceFriendSetIDs = uniquePreservingOrder(
            primary.defaultAudienceFriendSetIDs + duplicate.defaultAudienceFriendSetIDs
        )
        primary.defaultAudienceIncludedFriendIDs = uniquePreservingOrder(
            primary.defaultAudienceIncludedFriendIDs + duplicate.defaultAudienceIncludedFriendIDs
        )
        primary.defaultAudienceExcludedFriendIDs = uniquePreservingOrder(
            primary.defaultAudienceExcludedFriendIDs + duplicate.defaultAudienceExcludedFriendIDs
        )
    }

    private func resolveCategoryValueFaults(_ category: Category) {
        _ = category.id
        _ = category.name
        _ = category.colorHex
        _ = category.icon
        _ = category.sortOrder
        _ = category.isDefault
        _ = category.dailyCardIntentRawValue
        _ = category.isDailyCardSleepCategory
        _ = category.defaultAudienceFriendSetIDs
        _ = category.defaultAudienceIncludedFriendIDs
        _ = category.defaultAudienceExcludedFriendIDs
        _ = category.createdAt
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

    // MARK: - PlanBlock（CloudKit合流で増えた同一予定）

    private func mergePlanBlocks() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<PlanBlock>())) ?? []
        let groups = Dictionary(grouping: all, by: planDuplicateKey)
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.min { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                mergePlanBlock(loser, into: winner)
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    private func mergePlanBlock(_ duplicate: PlanBlock, into primary: PlanBlock) {
        if primary.category == nil {
            primary.category = duplicate.category
        }
        if primary.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let duplicateNote = duplicate.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !duplicateNote.isEmpty {
            primary.note = duplicateNote
        }
        if primary.sourceEventID == nil {
            primary.sourceEventID = duplicate.sourceEventID
        }
        primary.isImportant = primary.isImportant || duplicate.isImportant
        mergeAudience(from: duplicate, into: primary)
        if duplicate.updatedAt > primary.updatedAt {
            primary.updatedAt = duplicate.updatedAt
        }
    }

    private func mergeAudience(from duplicate: PlanBlock, into primary: PlanBlock) {
        if !primary.hasAudienceSnapshot, duplicate.hasAudienceSnapshot {
            primary.audienceFriendIDs = duplicate.audienceFriendIDs
            primary.audienceSource = duplicate.audienceSource
            primary.hasAudienceSnapshot = true
        } else {
            primary.audienceFriendIDs = uniquePreservingOrder(primary.audienceFriendIDs)
        }
    }

    private func planDuplicateKey(_ plan: PlanBlock) -> String {
        if let sourceEventID = plan.sourceEventID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceEventID.isEmpty {
            return "source:\(sourceEventID)"
        }
        let categoryKey = plan.category.map {
            "\($0.isDefault ? "default" : "custom"):\(normalizedName($0.name))"
        } ?? "none"
        let note = plan.note.map(normalizedName) ?? ""
        return [
            "manual",
            categoryKey,
            normalizedName(plan.title),
            minuteKey(plan.startTime),
            minuteKey(plan.endTime),
            plan.isAllDay ? "all-day" : "timed",
            note
        ].joined(separator: "|")
    }

    private func minuteKey(_ date: Date) -> String {
        String(Int((date.timeIntervalSinceReferenceDate / 60).rounded()))
    }

    // MARK: - Chapter（CloudKit合流で増えた同一実績）

    private func mergeChapters() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<Chapter>())) ?? []
        let groups = Dictionary(grouping: all, by: chapterDuplicateKey)
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let winner = group.min { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return isPreferred(lhs.createdAt, lhs.id.uuidString, over: rhs.createdAt, rhs.id.uuidString)
            }
            guard let winner else { continue }
            for loser in group where loser !== winner {
                mergeChapter(loser, into: winner)
                modelContext.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    private func mergeChapter(_ duplicate: Chapter, into primary: Chapter) {
        if primary.category == nil {
            primary.category = duplicate.category
        }
        if primary.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let duplicateNote = duplicate.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !duplicateNote.isEmpty {
            primary.note = duplicateNote
        }
        if primary.mood?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let duplicateMood = duplicate.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
           !duplicateMood.isEmpty {
            primary.mood = duplicateMood
        }
        if primary.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let duplicateLocation = duplicate.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !duplicateLocation.isEmpty {
            primary.locationName = duplicateLocation
        }
        mergeAudience(from: duplicate, into: primary)
        if duplicate.updatedAt > primary.updatedAt {
            primary.updatedAt = duplicate.updatedAt
        }
    }

    private func mergeAudience(from duplicate: Chapter, into primary: Chapter) {
        if !primary.hasAudienceSnapshot, duplicate.hasAudienceSnapshot {
            primary.audienceFriendIDs = duplicate.audienceFriendIDs
            primary.audienceSource = duplicate.audienceSource
            primary.hasAudienceSnapshot = true
        } else {
            primary.audienceFriendIDs = uniquePreservingOrder(primary.audienceFriendIDs)
        }
    }

    private func chapterDuplicateKey(_ chapter: Chapter) -> String {
        let categoryKey = chapter.category.map {
            "\($0.isDefault ? "default" : "custom"):\(normalizedName($0.name))"
        } ?? "none"
        return [
            categoryKey,
            minuteKey(chapter.startTime),
            chapter.endTime.map(minuteKey) ?? "active",
            chapter.note.map(normalizedName) ?? "",
            chapter.mood.map(normalizedName) ?? "",
            chapter.locationName.map(normalizedName) ?? ""
        ].joined(separator: "|")
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

    // MARK: - 参照整合性の修復

    private func ensureBuiltInVisibilityPresetsIfNeeded() {
        let friends = (try? modelContext.fetch(FetchDescriptor<Friend>())) ?? []
        let presets = (try? modelContext.fetch(FetchDescriptor<VisibilityPreset>())) ?? []
        guard !friends.isEmpty || !presets.isEmpty else { return }
        SeedCoordinator.consolidateBuiltInVisibilityPresets(in: modelContext)
    }

    private func repairDanglingReferences(includeTimelineRecords: Bool) -> Int {
        var repaired = 0

        let friends = (try? modelContext.fetch(FetchDescriptor<Friend>())) ?? []
        let presets = (try? modelContext.fetch(FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))) ?? []
        let presetIDs = Set(presets.map(\.id))
        let defaultPresetID = presets.first { $0.builtInKey == "acquaintances" }?.id
            ?? presets.first { $0.name == "控えめ" }?.id
            ?? presets.first?.id

        for friend in friends {
            if friend.visibilityPresetID.map({ !presetIDs.contains($0) }) ?? true,
               friend.visibilityPresetID != defaultPresetID {
                friend.visibilityPresetID = defaultPresetID
                friend.updatedAt = Date()
                repaired += 1
            }
        }

        let friendSets = (try? modelContext.fetch(FetchDescriptor<FriendSet>())) ?? []
        for set in friendSets {
            repaired += replaceIfChanged(&set.memberFriendIDs) {
                uniquePreservingOrder($0)
            }
        }

        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        for category in categories {
            repaired += replaceIfChanged(&category.defaultAudienceFriendSetIDs) {
                uniquePreservingOrder($0)
            }
            repaired += replaceIfChanged(&category.defaultAudienceIncludedFriendIDs) {
                uniquePreservingOrder($0)
            }
            repaired += replaceIfChanged(&category.defaultAudienceExcludedFriendIDs) {
                uniquePreservingOrder($0)
            }
        }

        for preset in presets {
            repaired += replaceIfChanged(&preset.excludedCategoryIDs) {
                uniquePreservingOrder($0)
            }
        }

        let categorySets = (try? modelContext.fetch(FetchDescriptor<CategorySet>())) ?? []
        for set in categorySets {
            let normalized = deduplicatedSlots(CategorySet.normalize(set.slots))
            if set.slots != normalized {
                set.slots = normalized
                repaired += 1
            }
        }

        if includeTimelineRecords {
            let plans = (try? modelContext.fetch(FetchDescriptor<PlanBlock>())) ?? []
            for plan in plans {
                repaired += replaceIfChanged(&plan.audienceFriendIDs) {
                    uniquePreservingOrder($0)
                }
            }
            let chapters = (try? modelContext.fetch(FetchDescriptor<Chapter>())) ?? []
            for chapter in chapters {
                repaired += replaceIfChanged(&chapter.audienceFriendIDs) {
                    uniquePreservingOrder($0)
                }
            }
        }

        return repaired
    }

    private func replaceIfChanged(_ values: inout [UUID], transform: ([UUID]) -> [UUID]) -> Int {
        let next = transform(values)
        guard next != values else { return 0 }
        values = next
        return 1
    }

    private func uniquePreservingOrder(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func deduplicatedSlots(_ slots: [UUID?]) -> [UUID?] {
        var seen = Set<UUID>()
        return slots.map { slot in
            guard let id = slot, seen.insert(id).inserted else {
                return nil
            }
            return id
        }
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

    private func normalizedFriendUsername(_ friend: Friend) -> String {
        let handle = friend.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        return UserIDNormalizer.normalizedValue(rawHandle)
            ?? UserIDNormalizer.normalizedValue(friend.inviteCode)
            ?? ""
    }
}

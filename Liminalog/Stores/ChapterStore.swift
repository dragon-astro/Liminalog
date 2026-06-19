import SwiftUI
import SwiftData
import WidgetKit

@Observable
@MainActor
final class ChapterStore {
    private(set) var contentRevision = 0

    private var modelContext: ModelContext
    private let clock: any LiminalogClock
    private let categoryStore: CategoryStore
    private let categorySetStore: CategorySetStore
    private let planStore: PlanStore
    private let liveActivityCoordinator: LiveActivityCoordinator
    private var didDisableUserSettingsPersistence = false
    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let activeCategoryCacheKey = "recording.activeCategoryID"
    private static let pendingCategoryCacheKey = "recording.pendingCategoryID"
    private static let enabledCategorySetCacheKey = "recording.enabledCategorySetID"
    private static let surfaceSnapshotCacheKey = "recording.surfaceSnapshot"

    init(
        modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock(),
        categoryStore: CategoryStore? = nil,
        categorySetStore: CategorySetStore? = nil,
        planStore: PlanStore? = nil,
        liveActivityCoordinator: LiveActivityCoordinator? = nil
    ) {
        self.modelContext = modelContext
        self.clock = clock
        let resolvedCategoryStore = categoryStore ?? CategoryStore(modelContext: modelContext)
        let resolvedCategorySetStore = categorySetStore ?? CategorySetStore(
            modelContext: modelContext,
            categoryStore: resolvedCategoryStore
        )
        self.categoryStore = resolvedCategoryStore
        self.categorySetStore = resolvedCategorySetStore
        self.planStore = planStore ?? PlanStore(modelContext: modelContext, clock: clock)
        self.liveActivityCoordinator = liveActivityCoordinator ?? LiveActivityCoordinator(
            categorySetStore: resolvedCategorySetStore
        )
    }

    private func markChanged(
        reloadWidgets: Bool = true,
        changedPlanSourceIDs: Set<UUID> = [],
        changedChapterSourceIDs: Set<UUID> = [],
        changedScoreDayStarts: Set<Date> = [],
        requiresFullSharePublish: Bool = true,
        requestCloudFriendShareRefresh: Bool = true
    ) {
        contentRevision &+= 1

        if reloadWidgets && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            WidgetCenter.shared.reloadAllTimelines()
        }
        guard requestCloudFriendShareRefresh else { return }
        CloudFriendShareRefreshCoordinator.requestRefresh(
            reason: "chapter store changed",
            changedPlanSourceIDs: changedPlanSourceIDs,
            changedChapterSourceIDs: changedChapterSourceIDs,
            changedScoreDayStarts: changedScoreDayStarts,
            requiresFullPublish: requiresFullSharePublish
        )
    }

    private func reloadRecordingGridWidget() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")
    }

    private func cacheActiveCategoryID(_ id: UUID?) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            NSLog("Liminalog: skipped active category cache because app group UserDefaults was unavailable")
            return
        }
        if let id {
            defaults.set(id.uuidString, forKey: Self.activeCategoryCacheKey)
            defaults.set(id.uuidString, forKey: Self.pendingCategoryCacheKey)
        } else {
            defaults.removeObject(forKey: Self.activeCategoryCacheKey)
            defaults.removeObject(forKey: Self.pendingCategoryCacheKey)
        }
        // synchronize() は同期ディスクフラッシュで重く、現行iOSでは不要（自動永続化される）。
    }

    private func cachedEnabledCategorySetID() -> UUID? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let value = UserDefaults(suiteName: Self.appGroupID)?.string(forKey: Self.enabledCategorySetCacheKey)
        else { return nil }
        return UUID(uuidString: value)
    }

    private func affectedScoreDayStarts(start: Date, end: Date) -> Set<Date> {
        var result: Set<Date> = []
        let calendar = Calendar.japanese
        var cursor = calendar.startOfDay(for: start)
        let endReference = end > start ? end.addingTimeInterval(-0.001) : start
        let last = calendar.startOfDay(for: endReference)
        while cursor <= last {
            result.insert(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func publishRecordingSurfaceSnapshot(categorySet: CategorySet? = nil) -> RecordingSurfaceSnapshot? {
        guard let snapshot = makeRecordingSurfaceSnapshot(categorySet: categorySet) else {
            NSLog("Liminalog: skipped recording surface snapshot because categories or category sets could not be loaded")
            return nil
        }

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return snapshot }
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            NSLog("Liminalog: skipped recording surface snapshot cache because app group UserDefaults was unavailable")
            return snapshot
        }

        if let id = snapshot.selectedCategorySetID {
            defaults.set(id.uuidString, forKey: Self.enabledCategorySetCacheKey)
        } else {
            defaults.removeObject(forKey: Self.enabledCategorySetCacheKey)
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: Self.surfaceSnapshotCacheKey)
        } catch {
            NSLog("Liminalog: failed to encode recording surface snapshot: \(String(describing: error))")
        }
        return snapshot
    }

    private func makeRecordingSurfaceSnapshot(categorySet: CategorySet? = nil) -> RecordingSurfaceSnapshot? {
        let selectedSet = categorySet ?? currentCategorySet()
        guard let categories = categoryStore.allCategoriesIfAvailable() else { return nil }
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let cells: [RecordingSurfaceSnapshot.Cell?] = CategorySet.normalize(selectedSet?.slots ?? [])
            .map { id in
                guard let id, let category = categoryByID[id] else { return nil }
                return RecordingSurfaceSnapshot.Cell(
                    id: category.id,
                    name: category.name,
                    colorHex: category.colorHex,
                    icon: category.icon
                )
            }

        return RecordingSurfaceSnapshot(
            selectedCategorySetID: selectedSet?.id,
            categorySetName: selectedSet?.name ?? "カテゴリ",
            cells: cells
        )
    }

    private func syncActiveCategoryCacheFromStore() {
        cacheActiveCategoryID(activeChapter?.category?.id)
    }

    private struct AudienceResolution {
        let friendIDs: [UUID]
        let didResolveSnapshot: Bool
    }

    private func defaultAudienceResolution(for category: Category?) -> AudienceResolution {
        do {
            let friendSets = try modelContext.fetch(FetchDescriptor<FriendSet>(
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            let friends = try modelContext.fetch(FetchDescriptor<Friend>(
                sortBy: [SortDescriptor(\.displayName)]
            ))
            let friendIDs = AudienceResolver.categoryDefaultAudience(
                for: category,
                friendSets: friendSets,
                friends: friends
            )
            return AudienceResolution(friendIDs: friendIDs, didResolveSnapshot: !friendIDs.isEmpty)
        } catch {
            NSLog("Liminalog: failed to resolve default audience: \(String(describing: error))")
            return AudienceResolution(friendIDs: [], didResolveSnapshot: false)
        }
    }

    private func applyCategoryDefaultAudience(to chapter: Chapter, category: Category?) {
        let resolution = defaultAudienceResolution(for: category)
        chapter.audienceFriendIDs = resolution.friendIDs
        chapter.audienceSource = .categoryDefaultSnapshot
        chapter.hasAudienceSnapshot = resolution.didResolveSnapshot
    }

    @discardableResult
    private func saveModelContext(action: String = "chapter store update") -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }

    // MARK: - Edit locks

    func isPlanScheduleLocked(_ plan: PlanBlock, now: Date = Date()) -> Bool {
        planStore.isScheduleLocked(plan, now: now)
    }

    func canCreatePlan(startTime: Date, isAllDay: Bool = false, now: Date = Date()) -> Bool {
        planStore.canCreate(startTime: startTime, isAllDay: isAllDay, now: now)
    }

    func canCreatePlan(
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        excluding planID: UUID? = nil,
        now: Date = Date()
    ) -> Bool {
        planStore.canCreate(
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            excluding: planID,
            now: now
        )
    }

    func hasTimedPlanOverlap(startTime: Date, endTime: Date, excluding planID: UUID? = nil) -> Bool {
        planStore.hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: planID)
    }

    func isChapterTimeLocked(_ chapter: Chapter, now: Date = Date()) -> Bool {
        let today = DayBoundary(date: now)
        let effectiveEnd = chapter.endTime ?? now
        return !today.overlaps(start: chapter.startTime, end: effectiveEnd)
    }

    func canCreateChapter(startTime: Date, endTime: Date, now: Date = Date()) -> Bool {
        let today = DayBoundary(date: now)
        return startTime >= today.dayStart
            && startTime < today.dayEnd
            && endTime > today.dayStart
            && endTime <= today.dayEnd
            && startTime < endTime
            && endTime <= now
            && !hasChapterOverlap(startTime: startTime, endTime: endTime, now: now)
    }

    func hasChapterOverlap(startTime: Date, endTime: Date, excluding chapterID: UUID? = nil, now: Date = Date()) -> Bool {
        chapterOverlapIfAvailable(startTime: startTime, endTime: endTime, excluding: chapterID, now: now) ?? true
    }

    private func chapterOverlapIfAvailable(startTime: Date, endTime: Date, excluding chapterID: UUID? = nil, now: Date = Date()) -> Bool? {
        guard startTime < endTime else { return false }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < endTime },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let candidates: [Chapter]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch chapters for overlap validation: \(String(describing: error))")
            return nil
        }
        return candidates.contains { chapter in
            guard chapter.id != chapterID else { return false }
            let candidateEnd = chapter.endTime ?? now
            return candidateEnd > startTime
        }
    }

    // MARK: - Active Chapter

    var activeChapter: Chapter? {
        activeChapters().first
    }

    private func activeChapters() -> [Chapter] {
        activeChaptersIfAvailable() ?? []
    }

    private func activeChaptersIfAvailable() -> [Chapter]? {
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch active chapters: \(String(describing: error))")
            return nil
        }
    }

    /// Close every active chapter before creating/stopping an active session.
    /// CloudKit or widget writes can leave multiple `endTime == nil` records; user-facing state must converge to one active chapter.
    @discardableResult
    private func closeActiveChapters(at now: Date) -> Bool {
        guard let actives = activeChaptersIfAvailable() else { return false }
        guard !actives.isEmpty else { return false }

        for active in actives {
            active.endTime = now
            active.updatedAt = now
        }
        return true
    }

    // MARK: - Start a new chapter

    /// カテゴリボタンが押されたときの記録開始ロジック。
    ///
    /// 挙動:
    /// - **同じカテゴリの再タップ:** active に同カテゴリのものがあれば**何もしない**（継続）。
    ///   並行性で他カテゴリの active が存在していれば、それらは閉じる。
    /// - **別カテゴリへ切替:** active を `endTime = now` で終了して新規開始（カテゴリ切替では削除しない）。
    @discardableResult
    func startChapter(category: Category, categorySet: CategorySet? = nil) -> Bool {
        let now = clock.now
        guard let activeChapters = activeChaptersIfAvailable() else { return false }
        let result = RecordingSwitchLogic.switchToCategory(
            category,
            at: now,
            activeChapters: activeChapters
        ) { chapter in
            applyCategoryDefaultAudience(to: chapter, category: category)
            modelContext.insert(chapter)
        }

        guard saveModelContext(action: "chapter start") else { return false }
        cacheActiveCategoryID(result.activeChapter?.category?.id)
        var changedChapterIDs = Set(activeChapters.map(\.id))
        if let activeID = result.activeChapter?.id {
            changedChapterIDs.insert(activeID)
        }
        let changedScoreDayStarts = Set((activeChapters + [result.activeChapter].compactMap { $0 }).flatMap {
            affectedScoreDayStarts(start: $0.startTime, end: $0.endTime ?? now)
        })
        markChanged(
            reloadWidgets: false,
            changedChapterSourceIDs: changedChapterIDs,
            changedScoreDayStarts: changedScoreDayStarts,
            requiresFullSharePublish: false
        )
        reloadRecordingGridWidget()
        updateLiveActivity(categorySet: categorySet)
        return true
    }

    @discardableResult
    func addChapter(
        category: Category,
        startTime: Date,
        endTime: Date,
        note: String? = nil,
        mood: String? = nil,
        locationName: String? = nil,
        isPublic: Bool = true,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource = .categoryDefaultSnapshot,
        hasAudienceSnapshot: Bool = true
    ) -> Bool {
        guard canCreateChapter(startTime: startTime, endTime: endTime, now: clock.now) else { return false }
        let chapter = Chapter(category: category, startTime: startTime)
        chapter.endTime = endTime
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        let audienceResolution = audienceFriendIDs.map {
            AudienceResolution(friendIDs: $0, didResolveSnapshot: hasAudienceSnapshot)
        } ?? defaultAudienceResolution(for: category)
        chapter.audienceFriendIDs = audienceResolution.friendIDs
        chapter.audienceSource = audienceSource
        chapter.hasAudienceSnapshot = hasAudienceSnapshot && audienceResolution.didResolveSnapshot
        chapter.updatedAt = clock.now
        modelContext.insert(chapter)
        guard saveModelContext(action: "chapter add") else { return false }
        markChanged(
            changedChapterSourceIDs: [chapter.id],
            changedScoreDayStarts: affectedScoreDayStarts(start: chapter.startTime, end: chapter.endTime ?? clock.now),
            requiresFullSharePublish: false
        )
        updateLiveActivity()
        return true
    }

    @discardableResult
    func endActiveChapter() -> Bool {
        let now = clock.now
        guard let actives = activeChaptersIfAvailable(), !actives.isEmpty else { return false }
        for active in actives {
            active.endTime = now
            active.updatedAt = now
        }
        guard saveModelContext(action: "active chapter end") else { return false }
        cacheActiveCategoryID(nil)
        markChanged(
            changedChapterSourceIDs: Set(actives.map(\.id)),
            changedScoreDayStarts: Set(actives.flatMap { affectedScoreDayStarts(start: $0.startTime, end: $0.endTime ?? now) }),
            requiresFullSharePublish: false
        )
        updateLiveActivity()
        return true
    }

    // MARK: - Chapter edits

    @discardableResult
    func saveChapter(
        _ chapter: Chapter,
        startTime: Date,
        endTime: Date?,
        category: Category?,
        note: String?,
        mood: String?,
        locationName: String?,
        isPublic: Bool,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource? = nil,
        hasAudienceSnapshot: Bool? = nil
    ) -> Bool {
        var changedScoreDayStarts = affectedScoreDayStarts(start: chapter.startTime, end: chapter.endTime ?? clock.now)
        if isChapterTimeLocked(chapter, now: clock.now) {
            // 前日以前の実績はスコア公平性のため、時間とカテゴリを固定する。
            // 振り返り用のメモ/場所/公開設定だけ後から編集可能。
        } else {
            let validationEnd = endTime ?? clock.now
            guard startTime < validationEnd,
                  validationEnd <= clock.now,
                  let hasOverlap = chapterOverlapIfAvailable(startTime: startTime, endTime: validationEnd, excluding: chapter.id, now: clock.now),
                  !hasOverlap
            else {
                return false
            }
            chapter.startTime = startTime
            chapter.endTime = endTime
            chapter.category = category
            changedScoreDayStarts.formUnion(affectedScoreDayStarts(start: startTime, end: endTime ?? clock.now))
        }
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        if let audienceFriendIDs {
            chapter.audienceFriendIDs = audienceFriendIDs
        }
        if let audienceSource {
            chapter.audienceSource = audienceSource
        }
        if let hasAudienceSnapshot {
            chapter.hasAudienceSnapshot = hasAudienceSnapshot
        }
        chapter.updatedAt = clock.now
        guard saveModelContext(action: "chapter update") else { return false }
        syncActiveCategoryCacheFromStore()
        markChanged(
            changedChapterSourceIDs: [chapter.id],
            changedScoreDayStarts: changedScoreDayStarts,
            requiresFullSharePublish: false
        )
        updateLiveActivity()
        return true
    }

    @discardableResult
    func setChapterVisibility(_ chapter: Chapter, isPublic: Bool) -> Bool {
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        guard saveModelContext(action: "chapter visibility update") else { return false }
        markChanged(changedChapterSourceIDs: [chapter.id], requiresFullSharePublish: false)
        return true
    }

    /// 複数チャプターの公開状態をまとめて変更。`isPublic == nil` のときは現状を反転する（一括トグル）。
    @discardableResult
    func setChaptersVisibility(_ chapters: [Chapter], isPublic: Bool?) -> Bool {
        guard !chapters.isEmpty else { return false }
        let target = isPublic ?? !chapters.allSatisfy(\.isPublic)
        for chapter in chapters {
            chapter.isPublic = target
            chapter.updatedAt = clock.now
        }
        guard saveModelContext(action: "chapter bulk visibility update") else { return false }
        markChanged(
            changedChapterSourceIDs: Set(chapters.map(\.id)),
            requiresFullSharePublish: false
        )
        return true
    }

    @discardableResult
    func deleteChapter(_ chapter: Chapter) -> Bool {
        guard !isChapterTimeLocked(chapter, now: clock.now) else { return false }
        let sourceID = chapter.id
        let changedScoreDayStarts = affectedScoreDayStarts(start: chapter.startTime, end: chapter.endTime ?? clock.now)
        modelContext.delete(chapter)
        guard saveModelContext(action: "chapter delete") else { return false }
        syncActiveCategoryCacheFromStore()
        markChanged(
            changedChapterSourceIDs: [sourceID],
            changedScoreDayStarts: changedScoreDayStarts,
            requiresFullSharePublish: false
        )
        updateLiveActivity()
        return true
    }

    // MARK: - Plans

    @discardableResult
    func addPlanBlock(
        category: Category?,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource = .categoryDefaultSnapshot,
        hasAudienceSnapshot: Bool = true
    ) -> Bool {
        createPlanBlock(
            category: category,
            title: title,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note,
            isPublic: isPublic,
            audienceFriendIDs: audienceFriendIDs,
            audienceSource: audienceSource,
            hasAudienceSnapshot: hasAudienceSnapshot
        ) != nil
    }

    @discardableResult
    func createPlanBlock(
        category: Category?,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false,
        isImportant: Bool = false,
        note: String? = nil,
        isPublic: Bool = true,
        audienceFriendIDs: [UUID]? = nil,
        audienceSource: AudienceSource = .categoryDefaultSnapshot,
        hasAudienceSnapshot: Bool = true
    ) -> PlanBlock? {
        let audienceResolution = audienceFriendIDs.map {
            AudienceResolution(friendIDs: $0, didResolveSnapshot: hasAudienceSnapshot)
        } ?? defaultAudienceResolution(for: category)
        guard let plan = planStore.createPlanBlock(
            category: category,
            title: title,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note,
            isPublic: isPublic,
            audienceFriendIDs: audienceResolution.friendIDs,
            audienceSource: audienceSource,
            hasAudienceSnapshot: hasAudienceSnapshot && audienceResolution.didResolveSnapshot
        ) else { return nil }
        markChanged(requestCloudFriendShareRefresh: false)
        return plan
    }

    @discardableResult
    func savePlanBlock(_ plan: PlanBlock, category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool, isImportant: Bool, note: String?, isPublic: Bool, audienceFriendIDs: [UUID]? = nil, audienceSource: AudienceSource? = nil, hasAudienceSnapshot: Bool? = nil) -> Bool {
        guard planStore.savePlanBlock(plan, category: category, title: title, startTime: startTime, endTime: endTime, isAllDay: isAllDay, isImportant: isImportant, note: note, isPublic: isPublic, audienceFriendIDs: audienceFriendIDs, audienceSource: audienceSource, hasAudienceSnapshot: hasAudienceSnapshot) else { return false }
        markChanged(requestCloudFriendShareRefresh: false)
        return true
    }

    @discardableResult
    func savePlanScheduleChanges(_ changes: [PlanStore.ScheduleChange]) -> Bool {
        guard planStore.savePlanScheduleChanges(changes) else { return false }
        markChanged(requestCloudFriendShareRefresh: false)
        return true
    }

    @discardableResult
    func deletePlanBlock(_ plan: PlanBlock) -> Bool {
        guard planStore.deletePlanBlock(plan) else { return false }
        markChanged(requestCloudFriendShareRefresh: false)
        return true
    }

    // MARK: - Category management

    @discardableResult
    func addCategory(
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        analysisKind: CategoryAnalysisKind = .unspecified,
        isDailyCardSleepCategory: Bool = false,
        defaultAudienceFriendSetIDs: [UUID] = [],
        defaultAudienceIncludedFriendIDs: [UUID] = [],
        defaultAudienceExcludedFriendIDs: [UUID] = []
    ) -> Bool {
        guard categoryStore.addCategory(
            name: name,
            colorHex: colorHex,
            icon: icon,
            dailyCardIntent: dailyCardIntent,
            analysisKind: analysisKind,
            isDailyCardSleepCategory: isDailyCardSleepCategory,
            defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
            defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
            defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
        ) else { return false }
        markChanged()
        return true
    }

    @discardableResult
    func updateCategory(
        _ category: Category,
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        analysisKind: CategoryAnalysisKind = .unspecified,
        isDailyCardSleepCategory: Bool = false,
        defaultAudienceFriendSetIDs: [UUID]? = nil,
        defaultAudienceIncludedFriendIDs: [UUID]? = nil,
        defaultAudienceExcludedFriendIDs: [UUID]? = nil
    ) -> Bool {
        guard categoryStore.updateCategory(
            category,
            name: name,
            colorHex: colorHex,
            icon: icon,
            dailyCardIntent: dailyCardIntent,
            analysisKind: analysisKind,
            isDailyCardSleepCategory: isDailyCardSleepCategory,
            defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
            defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
            defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
        ) else { return false }
        markChanged()
        updateLiveActivity()
        return true
    }

    @discardableResult
    func deleteCategory(_ category: Category) -> Bool {
        guard categoryStore.deleteCategory(category) else { return false }
        syncActiveCategoryCacheFromStore()
        markChanged()
        updateLiveActivity()
        return true
    }

    // MARK: - Category sets

    @discardableResult
    func addCategorySet(name: String, slots: [UUID?]) -> Bool {
        guard categorySetStore.addCategorySet(name: name, slots: slots) else { return false }
        markChanged()
        updateLiveActivity()
        return true
    }

    @discardableResult
    func updateCategorySet(_ set: CategorySet, name: String, slots: [UUID?]) -> Bool {
        guard categorySetStore.updateCategorySet(set, name: name, slots: slots) else { return false }
        markChanged()
        updateLiveActivity()
        return true
    }

    @discardableResult
    func deleteCategorySet(_ set: CategorySet) -> Bool {
        guard categorySetStore.deleteCategorySet(set) else { return false }
        markChanged()
        updateLiveActivity()
        return true
    }

    @discardableResult
    func moveCategorySets(from source: IndexSet, to destination: Int) -> Bool {
        guard categorySetStore.moveCategorySets(from: source, to: destination) else { return false }
        markChanged()
        updateLiveActivity()
        return true
    }

    func setEnabledCategorySetID(_ id: UUID?) {
        guard let sets = categorySetStore.categorySetsIfAvailable(),
              let snapshot = publishRecordingSurfaceSnapshot(categorySet: sets.first { $0.id == id })
        else {
            NSLog("Liminalog: skipped enabled category set update because category sets could not be loaded")
            return
        }
        reloadRecordingGridWidget()
        updateLiveActivity(snapshot: snapshot)
        persistEnabledCategorySetIDBestEffort(id)
    }

    func syncLiveActivityWithActiveChapter() {
        updateLiveActivity()
    }

    func restoreRecordingStateAfterLaunch() {
        syncActiveCategoryCacheFromStore()
        updateLiveActivity()
    }

    // MARK: - Maintenance

    /// 前日以前の1分未満完了チャプターを削除する。
    ///
    /// 起動時に呼ぶことでゴミデータの蓄積を防ぐ。
    /// 当日分は残す（ユーザーが気づいて手動削除できるようにするため）。
    /// 記録中（endTime == nil）は絶対に削除しない。
    func pruneShortChapters() {
        let today = DayBoundary.dayStart(for: clock.now)
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate {
                $0.endTime != nil && $0.startTime < today
            }
        )
        let candidates: [Chapter]
        do {
            candidates = try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: skipped short chapter prune because chapters could not be fetched: \(String(describing: error))")
            return
        }
        let toDelete = candidates.filter { chapter in
            guard let end = chapter.endTime else { return false }
            return end.timeIntervalSince(chapter.startTime) < 60
        }
        guard !toDelete.isEmpty else { return }
        toDelete.forEach { modelContext.delete($0) }
        guard saveModelContext(action: "short chapter prune") else { return }
        markChanged()
    }

    // MARK: - Seed defaults

    func seedDefaultCategoriesIfNeeded() {
        if categoryStore.seedDefaultCategoriesIfNeeded() {
            markChanged()
        }
    }

    func seedDefaultCategorySetsIfNeeded() {
        if categorySetStore.seedDefaultCategorySetsIfNeeded() {
            markChanged()
        }
    }

    #if DEBUG
    func seedPreviewPlansIfNeeded() {
        if PreviewSupport.seedPreviewPlansIfNeeded(in: modelContext, clock: clock) {
            markChanged()
        }
    }
    #endif

    #if DEBUG
    func seedDevSampleChaptersIfNeeded() {
        if PreviewSupport.seedDevSampleChaptersIfNeeded(in: modelContext, clock: clock) {
            syncActiveCategoryCacheFromStore()
            markChanged()
            updateLiveActivity()
        }
    }
    #endif

    private func updateLiveActivity(categorySet: CategorySet? = nil) {
        guard let snapshot = publishRecordingSurfaceSnapshot(categorySet: categorySet) else { return }
        updateLiveActivity(snapshot: snapshot)
    }

    private func updateLiveActivity(snapshot: RecordingSurfaceSnapshot) {
        liveActivityCoordinator.update(activeChapter: activeChapter, snapshot: snapshot)
    }

    private func currentCategorySet() -> CategorySet? {
        guard let sets = categorySetStore.categorySetsIfAvailable() else { return nil }
        let settings: UserSettings?
        do {
            settings = try modelContext.fetch(FetchDescriptor<UserSettings>(
                predicate: #Predicate { $0.settingsKey == "default" },
                sortBy: [SortDescriptor(\.createdAt)]
            )).first
        } catch {
            NSLog("Liminalog: failed to fetch UserSettings for current category set: \(String(describing: error))")
            settings = nil
        }
        return cachedEnabledCategorySetID().flatMap { id in sets.first { $0.id == id } }
            ?? settings?.enabledCategorySetID.flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first
    }

    private func persistEnabledCategorySetIDBestEffort(_ id: UUID?) {
        guard !didDisableUserSettingsPersistence else { return }

        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.settingsKey == "default" },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let settings: UserSettings
        do {
            settings = try modelContext.fetch(descriptor).first ?? UserSettings()
        } catch {
            didDisableUserSettingsPersistence = true
            NSLog("Liminalog: skipped UserSettings.enabledCategorySetID persistence because settings could not be fetched: \(String(describing: error))")
            return
        }
        if settings.modelContext == nil {
            modelContext.insert(settings)
        }
        guard settings.enabledCategorySetID != id else { return }
        settings.enabledCategorySetID = id
        settings.updatedAt = clock.now
        if !saveModelContext() {
            didDisableUserSettingsPersistence = true
            #if DEBUG
            NSLog("Liminalog: skipped UserSettings.enabledCategorySetID persistence; recording surface snapshot was already published")
            #endif
        }
    }
}

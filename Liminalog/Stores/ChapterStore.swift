import SwiftUI
import SwiftData
import WidgetKit

@Observable
@MainActor
final class ChapterStore {
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

    private func markChanged(reloadWidgets: Bool = true) {
        if reloadWidgets && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func reloadRecordingGridWidget() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")
    }

    private func cacheActiveCategoryID(_ id: UUID?) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let defaults = UserDefaults(suiteName: Self.appGroupID)
        else { return }
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

    private func publishRecordingSurfaceSnapshot(categorySet: CategorySet? = nil) -> RecordingSurfaceSnapshot {
        let snapshot = makeRecordingSurfaceSnapshot(categorySet: categorySet)

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let defaults = UserDefaults(suiteName: Self.appGroupID)
        else { return snapshot }

        if let id = snapshot.selectedCategorySetID {
            defaults.set(id.uuidString, forKey: Self.enabledCategorySetCacheKey)
        } else {
            defaults.removeObject(forKey: Self.enabledCategorySetCacheKey)
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.surfaceSnapshotCacheKey)
        }
        return snapshot
    }

    private func makeRecordingSurfaceSnapshot(categorySet: CategorySet? = nil) -> RecordingSurfaceSnapshot {
        let selectedSet = categorySet ?? currentCategorySet()
        let categoryByID = Dictionary(uniqueKeysWithValues: categoryStore.allCategories().map { ($0.id, $0) })
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

    @discardableResult
    private func saveModelContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
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
        guard startTime < endTime else { return false }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < endTime },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
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
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Close every active chapter before creating/stopping an active session.
    /// CloudKit or widget writes can leave multiple `endTime == nil` records; user-facing state must converge to one active chapter.
    @discardableResult
    private func closeActiveChapters(at now: Date) -> Bool {
        let actives = activeChapters()
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
    func startChapter(category: Category, categorySet: CategorySet? = nil) {
        let now = clock.now
        let result = RecordingSwitchLogic.switchToCategory(
            category,
            at: now,
            activeChapters: activeChapters()
        ) { chapter in
            modelContext.insert(chapter)
        }

        if saveModelContext() {
            cacheActiveCategoryID(result.activeChapter?.category?.id)
        }
        reloadRecordingGridWidget()
        updateLiveActivity(categorySet: categorySet)
    }

    @discardableResult
    func addChapter(category: Category, startTime: Date, endTime: Date, note: String? = nil, mood: String? = nil, locationName: String? = nil, isPublic: Bool = true) -> Bool {
        guard canCreateChapter(startTime: startTime, endTime: endTime, now: clock.now) else { return false }
        let chapter = Chapter(category: category, startTime: startTime)
        chapter.endTime = endTime
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        modelContext.insert(chapter)
        try? modelContext.save()
        markChanged()
        updateLiveActivity()
        return true
    }

    func endActiveChapter() {
        let now = clock.now
        guard closeActiveChapters(at: now) else { return }
        if saveModelContext() {
            cacheActiveCategoryID(nil)
        }
        markChanged()
        updateLiveActivity()
    }

    // MARK: - Chapter edits

    @discardableResult
    func saveChapter(_ chapter: Chapter, startTime: Date, endTime: Date?, category: Category?, note: String?, mood: String?, locationName: String?, isPublic: Bool) -> Bool {
        if isChapterTimeLocked(chapter, now: clock.now) {
            // 前日以前の実績はスコア公平性のため、時間とカテゴリを固定する。
            // 振り返り用のメモ/場所/公開設定だけ後から編集可能。
        } else {
            let validationEnd = endTime ?? clock.now
            guard startTime < validationEnd,
                  validationEnd <= clock.now,
                  !hasChapterOverlap(startTime: startTime, endTime: validationEnd, excluding: chapter.id, now: clock.now)
            else {
                return false
            }
            chapter.startTime = startTime
            chapter.endTime = endTime
            chapter.category = category
        }
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        if saveModelContext() {
            syncActiveCategoryCacheFromStore()
        }
        markChanged()
        updateLiveActivity()
        return true
    }

    func setChapterVisibility(_ chapter: Chapter, isPublic: Bool) {
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        try? modelContext.save()
        markChanged()
    }

    /// 複数チャプターの公開状態をまとめて変更。`isPublic == nil` のときは現状を反転する（一括トグル）。
    func setChaptersVisibility(_ chapters: [Chapter], isPublic: Bool?) {
        guard !chapters.isEmpty else { return }
        let target = isPublic ?? !chapters.allSatisfy(\.isPublic)
        for chapter in chapters {
            chapter.isPublic = target
            chapter.updatedAt = clock.now
        }
        try? modelContext.save()
        markChanged()
    }

    @discardableResult
    func deleteChapter(_ chapter: Chapter) -> Bool {
        guard !isChapterTimeLocked(chapter, now: clock.now) else { return false }
        modelContext.delete(chapter)
        if saveModelContext() {
            syncActiveCategoryCacheFromStore()
        }
        markChanged()
        updateLiveActivity()
        return true
    }

    // MARK: - Plans

    @discardableResult
    func addPlanBlock(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, isImportant: Bool = false, note: String? = nil, isPublic: Bool = true) -> Bool {
        guard planStore.addPlanBlock(category: category, title: title, startTime: startTime, endTime: endTime, isAllDay: isAllDay, isImportant: isImportant, note: note, isPublic: isPublic) else { return false }
        markChanged()
        return true
    }

    @discardableResult
    func savePlanBlock(_ plan: PlanBlock, category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool, isImportant: Bool, note: String?, isPublic: Bool) -> Bool {
        guard planStore.savePlanBlock(plan, category: category, title: title, startTime: startTime, endTime: endTime, isAllDay: isAllDay, isImportant: isImportant, note: note, isPublic: isPublic) else { return false }
        markChanged()
        return true
    }

    @discardableResult
    func deletePlanBlock(_ plan: PlanBlock) -> Bool {
        guard planStore.deletePlanBlock(plan) else { return false }
        markChanged()
        return true
    }

    // MARK: - Category management

    func addCategory(
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        isDailyCardSleepCategory: Bool = false
    ) {
        if categoryStore.addCategory(
            name: name,
            colorHex: colorHex,
            icon: icon,
            dailyCardIntent: dailyCardIntent,
            isDailyCardSleepCategory: isDailyCardSleepCategory
        ) {
            markChanged()
        }
    }

    func updateCategory(
        _ category: Category,
        name: String,
        colorHex: String,
        icon: String? = nil,
        dailyCardIntent: DailyCardCategoryIntent = .neutral,
        isDailyCardSleepCategory: Bool = false
    ) {
        if categoryStore.updateCategory(
            category,
            name: name,
            colorHex: colorHex,
            icon: icon,
            dailyCardIntent: dailyCardIntent,
            isDailyCardSleepCategory: isDailyCardSleepCategory
        ) {
            markChanged()
            updateLiveActivity()
        }
    }

    func deleteCategory(_ category: Category) {
        if categoryStore.deleteCategory(category) {
            syncActiveCategoryCacheFromStore()
            markChanged()
            updateLiveActivity()
        }
    }

    // MARK: - Category sets

    func addCategorySet(name: String, slots: [UUID?]) {
        if categorySetStore.addCategorySet(name: name, slots: slots) {
            markChanged()
            updateLiveActivity()
        }
    }

    func updateCategorySet(_ set: CategorySet, name: String, slots: [UUID?]) {
        if categorySetStore.updateCategorySet(set, name: name, slots: slots) {
            markChanged()
            updateLiveActivity()
        }
    }

    func deleteCategorySet(_ set: CategorySet) {
        if categorySetStore.deleteCategorySet(set) {
            markChanged()
            updateLiveActivity()
        }
    }

    func moveCategorySets(from source: IndexSet, to destination: Int) {
        if categorySetStore.moveCategorySets(from: source, to: destination) {
            markChanged()
            updateLiveActivity()
        }
    }

    func setEnabledCategorySetID(_ id: UUID?) {
        let snapshot = publishRecordingSurfaceSnapshot(categorySet: categorySetStore.categorySets().first { $0.id == id })
        reloadRecordingGridWidget()
        updateLiveActivity(snapshot: snapshot)
        persistEnabledCategorySetIDBestEffort(id)
    }

    func syncLiveActivityWithActiveChapter() {
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
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        let toDelete = candidates.filter { chapter in
            guard let end = chapter.endTime else { return false }
            return end.timeIntervalSince(chapter.startTime) < 60
        }
        guard !toDelete.isEmpty else { return }
        toDelete.forEach { modelContext.delete($0) }
        try? modelContext.save()
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
        let snapshot = publishRecordingSurfaceSnapshot(categorySet: categorySet)
        updateLiveActivity(snapshot: snapshot)
    }

    private func updateLiveActivity(snapshot: RecordingSurfaceSnapshot) {
        liveActivityCoordinator.update(activeChapter: activeChapter, snapshot: snapshot)
    }

    private func currentCategorySet() -> CategorySet? {
        let sets = categorySetStore.categorySets()
        let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.settingsKey == "default" },
            sortBy: [SortDescriptor(\.createdAt)]
        )).first
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
        let settings = (try? modelContext.fetch(descriptor).first) ?? UserSettings()
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

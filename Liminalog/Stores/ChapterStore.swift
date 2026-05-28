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
    private let scoreStore: ScoreStore
    private let liveActivityCoordinator: LiveActivityCoordinator
    var revision = 0
    private static let appGroupID = "group.app.YasudaRyuga.Liminalog"
    private static let activeCategoryCacheKey = "recording.activeCategoryID"
    private static let pendingCategoryCacheKey = "recording.pendingCategoryID"

    init(
        modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock(),
        categoryStore: CategoryStore? = nil,
        categorySetStore: CategorySetStore? = nil,
        planStore: PlanStore? = nil,
        scoreStore: ScoreStore? = nil,
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
        self.scoreStore = scoreStore ?? ScoreStore(modelContext: modelContext, clock: clock)
        self.liveActivityCoordinator = liveActivityCoordinator ?? LiveActivityCoordinator(
            categorySetStore: resolvedCategorySetStore
        )
    }

    private func markChanged(reloadWidgets: Bool = true) {
        revision += 1
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
        defaults.synchronize()
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
        markChanged()
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

    // MARK: - Today's chapters

    func todaysChapters() -> [Chapter] {
        chapters(on: clock.now)
    }

    func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let now = clock.now
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { ($0.endTime ?? now) > dayStart }
    }

    func chapters(from start: Date, to end: Date) -> [Chapter] {
        let now = clock.now
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { ($0.endTime ?? now) > start }
    }

    func recentChapters(limit: Int = 50) -> [Chapter] {
        var descriptor = FetchDescriptor<Chapter>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Category grid (positional 8 slots)

    /// 8件のスロット配列を返す。空きスロットは `nil`。配列 index がそのままグリッド位置。
    func slottedCategories(for set: CategorySet) -> [Category?] {
        categorySetStore.slottedCategories(for: set)
    }

    /// 割り当て済みカテゴリだけを順序保ったまま返す（Live Activity 等の表示用）
    func assignedCategories(for set: CategorySet) -> [Category] {
        categorySetStore.assignedCategories(for: set)
    }

    func allCategories() -> [Category] {
        categoryStore.allCategories()
    }

    func categorySets() -> [CategorySet] {
        categorySetStore.categorySets()
    }

    // MARK: - Chapter edits

    @discardableResult
    func saveChapter(_ chapter: Chapter, startTime: Date, endTime: Date?, category: Category?, note: String?, mood: String?, locationName: String?, isPublic: Bool) -> Bool {
        if isChapterTimeLocked(chapter, now: clock.now) {
            // 前日以前の実績はスコア公平性のため、時間とカテゴリを固定する。
            // 振り返り用のメモ/気分/場所/公開設定だけ後から編集可能。
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

    func plannedBlocks(on date: Date) -> [PlanBlock] {
        planStore.plannedBlocks(on: date)
    }

    func plannedBlocks(from start: Date, to end: Date) -> [PlanBlock] {
        planStore.plannedBlocks(from: start, to: end)
    }

    func allPlannedBlocks() -> [PlanBlock] {
        planStore.allPlannedBlocks()
    }

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

    // MARK: - Score

    func scoreSummary(on date: Date) -> ScoreSummary {
        scoreStore.scoreSummary(on: date)
    }

    func streakCount(endingAt date: Date = Date()) -> Int {
        scoreStore.streakCount(endingAt: date)
    }

    func totalScore(days: Int = 365) -> Int {
        scoreStore.totalScore(days: days)
    }

    // MARK: - Category management

    func addCategory(name: String, colorHex: String, icon: String? = nil) {
        if categoryStore.addCategory(name: name, colorHex: colorHex, icon: icon) {
            markChanged()
        }
    }

    func updateCategory(_ category: Category, name: String, colorHex: String, icon: String? = nil) {
        if categoryStore.updateCategory(category, name: name, colorHex: colorHex, icon: icon) {
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
        let descriptor = FetchDescriptor<UserSettings>()
        let settings = (try? modelContext.fetch(descriptor).first) ?? UserSettings()
        if settings.modelContext == nil {
            modelContext.insert(settings)
        }
        guard settings.enabledCategorySetID != id else { return }
        settings.enabledCategorySetID = id
        settings.updatedAt = clock.now
        guard saveModelContext() else { return }
        reloadRecordingGridWidget()
        updateLiveActivity()
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

    func seedPreviewPlansIfNeeded() {
        seedDefaultCategorySetsIfNeeded()

        let seedVersionKey = "LiminalogPreviewPlanSeedVersion"
        let currentSeedVersion = 4
        let calendar = Calendar.current
        let today = DayBoundary.dayStart(for: clock.now, calendar: calendar)
        let todayPlans = plannedBlocks(on: today).filter { !$0.isAllDay }
        let hasCurrentSeedVersion = UserDefaults.standard.integer(forKey: seedVersionKey) >= currentSeedVersion

        if hasCurrentSeedVersion && plansCoverFullDay(todayPlans, on: today) {
            return
        }

        let categories = Dictionary(uniqueKeysWithValues: allCategories().map { ($0.name, $0) })
        let samples: [(String, Int, Int, Int, String)] = [
            ("睡眠", 0, 0, 420, "睡眠"),
            ("休憩", 7, 0, 60, "朝の準備"),
            ("移動", 8, 0, 60, "移動"),
            ("勉強", 9, 0, 120, "英語と課題"),
            ("移動", 11, 0, 45, "移動"),
            ("休憩", 11, 45, 75, "昼休み"),
            ("仕事", 13, 0, 180, "制作作業"),
            ("休憩", 16, 0, 30, "休憩"),
            ("勉強", 16, 30, 90, "復習"),
            ("移動", 18, 0, 60, "帰宅"),
            ("趣味", 19, 0, 150, "自由時間"),
            ("休憩", 21, 30, 60, "夜の休憩"),
            ("睡眠", 22, 30, 90, "睡眠"),
        ]

        let sampleTitles = Set(samples.map { $0.4 } + ["予定調整"])
        let canReplaceTodayPlans = todayPlans.isEmpty || todayPlans.allSatisfy { sampleTitles.contains($0.title) }

        if canReplaceTodayPlans {
            for plan in todayPlans {
                modelContext.delete(plan)
            }
        } else {
            seedPlanGaps(for: todayPlans, on: today, categories: categories, samples: samples)
            try? modelContext.save()
            UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
            markChanged()
            return
        }

        for (categoryName, hour, startMinute, durationMinutes, title) in samples {
            guard
                let category = categories[categoryName],
                let start = calendar.date(byAdding: .hour, value: hour, to: today),
                let adjustedStart = calendar.date(byAdding: .minute, value: startMinute, to: start),
                let end = calendar.date(byAdding: .minute, value: durationMinutes, to: adjustedStart)
            else { continue }

            modelContext.insert(PlanBlock(category: category, title: title, startTime: adjustedStart, endTime: end))
        }

        try? modelContext.save()
        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
        markChanged()
    }

    private func seedPlanGaps(
        for plans: [PlanBlock],
        on date: Date,
        categories: [String: Category],
        samples: [(String, Int, Int, Int, String)]
    ) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let sorted = plans
            .filter { $0.startTime < dayEnd && $0.endTime > dayStart }
            .sorted { $0.startTime < $1.startTime }

        var cursor = dayStart
        for plan in sorted {
            let start = max(plan.startTime, dayStart)
            if start > cursor {
                seedPreviewPlanSegments(from: cursor, to: start, on: dayStart, categories: categories, samples: samples)
            }
            cursor = max(cursor, min(plan.endTime, dayEnd))
        }

        if cursor < dayEnd {
            seedPreviewPlanSegments(from: cursor, to: dayEnd, on: dayStart, categories: categories, samples: samples)
        }
    }

    private func seedPreviewPlanSegments(
        from gapStart: Date,
        to gapEnd: Date,
        on dayStart: Date,
        categories: [String: Category],
        samples: [(String, Int, Int, Int, String)]
    ) {
        let calendar = Calendar.current
        for (categoryName, hour, startMinute, durationMinutes, title) in samples {
            guard
                let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                let sampleStart = calendar.date(byAdding: .minute, value: startMinute, to: hourStart),
                let sampleEnd = calendar.date(byAdding: .minute, value: durationMinutes, to: sampleStart)
            else { continue }

            let start = max(sampleStart, gapStart)
            let end = min(sampleEnd, gapEnd)
            guard end > start else { continue }

            modelContext.insert(PlanBlock(
                category: categories[categoryName],
                title: title,
                startTime: start,
                endTime: end
            ))
        }
    }

    private func plansCoverFullDay(_ plans: [PlanBlock], on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let sorted = plans
            .filter { $0.startTime < dayEnd && $0.endTime > dayStart }
            .sorted { $0.startTime < $1.startTime }

        guard !sorted.isEmpty else { return false }
        var cursor = dayStart
        let tolerance: TimeInterval = 1

        for plan in sorted {
            let start = max(plan.startTime, dayStart)
            let end = min(plan.endTime, dayEnd)
            if start.timeIntervalSince(cursor) > tolerance {
                return false
            }
            cursor = max(cursor, end)
            if cursor >= dayEnd {
                return true
            }
        }

        return dayEnd.timeIntervalSince(cursor) <= tolerance
    }

    /// DEBUG ビルド用: Chapter のサンプルデータを seed する。
    /// 既に Chapter が 1 件でもあれば何もしない（冪等）。
    /// 過去 4 日分の記録 + 今日のタイムライン + 現在記録中のチャプター を生成する。
    func seedDevSampleChaptersIfNeeded() {
        seedDefaultCategoriesIfNeeded()

        let chapterDescriptor = FetchDescriptor<Chapter>()
        guard (try? modelContext.fetchCount(chapterDescriptor)) == 0 else { return }

        let categoriesByName = Dictionary(uniqueKeysWithValues: allCategories().map { ($0.name, $0) })
        let calendar = Calendar.current
        let today = DayBoundary.dayStart(for: clock.now, calendar: calendar)

        // 今日のタイムライン: 朝〜夕方までのチャプター + 現在記録中のもの
        // (categoryName, hour, minutes, note?, mood?, location?, isPublic)
        let todaySamples: [(String, Int, Int, String?, String?, String?, Bool)] = [
            ("睡眠", 0, 420, nil, "😴", nil, false),
            ("勉強", 9, 90, "英語の復習", "💪", "図書館", true),
            ("移動", 11, 30, nil, nil, "電車", true),
            ("仕事", 13, 120, "UI整理", "🔥", nil, true),
            ("休憩", 16, 30, "コーヒー", "☕️", "カフェ", false),
        ]
        for (name, hour, minutes, note, mood, location, isPublic) in todaySamples {
            guard
                let category = categoriesByName[name],
                let start = calendar.date(byAdding: .hour, value: hour, to: today),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }
            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            chapter.note = note
            chapter.mood = mood
            chapter.locationName = location
            chapter.isPublic = isPublic
            modelContext.insert(chapter)
        }

        // 現在記録中のチャプター（30分前から）
        if let trendyCategory = categoriesByName["趣味"] ?? categoriesByName.values.first,
           let recentStart = calendar.date(byAdding: .minute, value: -30, to: clock.now) {
            let active = Chapter(category: trendyCategory, startTime: recentStart)
            active.note = "アプリの試作"
            active.mood = "🤩"
            modelContext.insert(active)
        }

        // 過去 4 日分: ダッシュボード・カレンダーの動作確認用
        // (dayOffset, categoryName, hour, minutes, note?, mood?, location?)
        let pastSamples: [(Int, String, Int, Int, String?, String?, String?)] = [
            (-1, "睡眠", 0, 420, nil, "😴", nil),
            (-1, "勉強", 10, 90, "授業", nil, "学校"),
            (-1, "仕事", 14, 120, "資料作成", "📝", nil),
            (-1, "趣味", 19, 75, "ゲーム", "🎮", nil),

            (-2, "睡眠", 1, 390, nil, nil, nil),
            (-2, "移動", 9, 45, nil, nil, "電車"),
            (-2, "仕事", 10, 180, "MTG", "💼", "オフィス"),
            (-2, "休憩", 14, 60, "ランチ", "🍱", nil),
            (-2, "勉強", 16, 90, "復習", nil, nil),

            (-3, "睡眠", 0, 450, nil, "😪", nil),
            (-3, "趣味", 11, 120, "映画", "🎬", nil),
            (-3, "勉強", 15, 60, "読書", "📚", "カフェ"),

            (-4, "睡眠", 1, 420, nil, nil, nil),
            (-4, "仕事", 10, 240, "集中作業", "🔥", nil),
            (-4, "休憩", 15, 30, nil, "☕️", nil),
            (-4, "勉強", 17, 90, "課題", "💪", "図書館"),
        ]
        for (dayOffset, name, hour, minutes, note, mood, location) in pastSamples {
            guard
                let category = categoriesByName[name],
                let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                let start = calendar.date(byAdding: .hour, value: hour, to: day),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }
            let chapter = Chapter(category: category, startTime: start)
            chapter.endTime = end
            chapter.note = note
            chapter.mood = mood
            chapter.locationName = location
            chapter.isPublic = true
            modelContext.insert(chapter)
        }

        try? modelContext.save()
        markChanged()
    }

    private func updateLiveActivity(categorySet: CategorySet? = nil) {
        liveActivityCoordinator.update(activeChapter: activeChapter, categorySet: categorySet ?? currentCategorySet())
    }

    private func currentCategorySet() -> CategorySet? {
        let sets = categorySets()
        let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first
        return settings?.enabledCategorySetID.flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first
    }
}

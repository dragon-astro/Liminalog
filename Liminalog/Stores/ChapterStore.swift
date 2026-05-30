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
    private static let devSampleChapterSeedVersionKey = "LiminalogDevSampleChapterSeedVersion"
    private static let currentDevSampleChapterSeedVersion = 3

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
        defaults.synchronize()
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
        defaults.synchronize()
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

    func seedPreviewPlansIfNeeded() {
        seedDefaultCategorySetsIfNeeded()

        let seedVersionKey = "LiminalogPreviewPlanSeedVersion"
        let currentSeedVersion = 6
        let calendar = Calendar.current
        let today = DayBoundary.dayStart(for: clock.now, calendar: calendar)
        guard let month = monthInterval(containing: today, calendar: calendar) else { return }
        let monthPlans = planStore.plannedBlocks(from: month.start, to: month.end)
        let hasCurrentSeedVersion = UserDefaults.standard.integer(forKey: seedVersionKey) >= currentSeedVersion

        if hasCurrentSeedVersion && monthHasCompleteShowcasePlans(monthPlans, in: month, calendar: calendar) {
            return
        }

        let categories = Dictionary(uniqueKeysWithValues: categoryStore.allCategories().map { ($0.name, $0) })

        for plan in monthPlans {
            modelContext.delete(plan)
        }

        for day in days(in: month, calendar: calendar) {
            for (index, segment) in previewPlanSegments(for: day, calendar: calendar) {
                guard
                    let category = categories[segment.categoryName],
                    let start = calendar.date(byAdding: .minute, value: segment.startMinute, to: day),
                    let end = calendar.date(byAdding: .minute, value: segment.durationMinutes, to: start)
                else { continue }

                let plan = PlanBlock(
                    category: category,
                    title: segment.title,
                    startTime: start,
                    endTime: end,
                    isImportant: segment.isImportant,
                    note: segment.note,
                    isPublic: true
                )
                plan.sourceEventID = "debug.preview.plan.\(dateKey(for: day, calendar: calendar)).\(index)"
                modelContext.insert(plan)
            }
        }

        insertShowcaseImportantPlans(monthStart: month.start, calendar: calendar, categories: categories)

        _ = saveModelContext()
        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
        markChanged()
    }

    private func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .month, value: 1, to: start),
            end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func days(in month: DateInterval, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = month.start
        while cursor < month.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func monthHasCompleteShowcasePlans(_ plans: [PlanBlock], in month: DateInterval, calendar: Calendar) -> Bool {
        let timedPlans = plans.filter { !$0.isAllDay }
        let allDaysCovered = days(in: month, calendar: calendar).allSatisfy {
            plansCoverFullDay(timedPlans, on: $0)
        }
        guard allDaysCovered else { return false }

        let hasTimedImportant = plans.contains { $0.isImportant && !$0.isAllDay }
        let hasMultiDayImportant = plans.contains {
            $0.isImportant && $0.isAllDay && $0.endTime.timeIntervalSince($0.startTime) >= 2 * 24 * 60 * 60
        }
        return hasTimedImportant && hasMultiDayImportant
    }

    private struct DemoPlanSegment {
        var categoryName: String
        var startMinute: Int
        var durationMinutes: Int
        var title: String
        var isImportant: Bool = false
        var note: String? = nil
    }

    private func previewPlanSegments(for day: Date, calendar: Calendar) -> [(Int, DemoPlanSegment)] {
        let dayNumber = calendar.component(.day, from: day)
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7
        var segments = isWeekend
            ? weekendPreviewPlanSegments(dayNumber: dayNumber)
            : weekdayPreviewPlanSegments(dayNumber: dayNumber)
        applyTimedImportantOverrides(to: &segments, dayNumber: dayNumber)
        return Array(segments.enumerated())
    }

    private func weekdayPreviewPlanSegments(dayNumber: Int) -> [DemoPlanSegment] {
        let morningFocus = dayNumber.isMultiple(of: 3) ? "仕事" : "勉強"
        let afternoonFocus = dayNumber.isMultiple(of: 2) ? "勉強" : "仕事"
        let morningTitle = morningFocus == "勉強" ? "英語と課題" : "制作作業"
        let afternoonTitle = afternoonFocus == "勉強" ? "演習と復習" : "プロダクト作業"

        return [
            DemoPlanSegment(categoryName: "睡眠", startMinute: 0, durationMinutes: 420, title: "睡眠"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 60, title: "朝の準備"),
            DemoPlanSegment(categoryName: "移動", startMinute: 480, durationMinutes: 60, title: "移動"),
            DemoPlanSegment(categoryName: morningFocus, startMinute: 540, durationMinutes: 180, title: morningTitle),
            DemoPlanSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, title: "昼休み"),
            DemoPlanSegment(categoryName: afternoonFocus, startMinute: 780, durationMinutes: 180, title: afternoonTitle),
            DemoPlanSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, title: "休憩"),
            DemoPlanSegment(categoryName: "勉強", startMinute: 990, durationMinutes: 90, title: "復習"),
            DemoPlanSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, title: "帰宅"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1140, durationMinutes: 150, title: "自由時間"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 1290, durationMinutes: 60, title: "夜の休憩"),
            DemoPlanSegment(categoryName: "睡眠", startMinute: 1350, durationMinutes: 90, title: "睡眠"),
        ]
    }

    private func weekendPreviewPlanSegments(dayNumber: Int) -> [DemoPlanSegment] {
        let afternoonCategory = dayNumber.isMultiple(of: 2) ? "趣味" : "仕事"
        let afternoonTitle = afternoonCategory == "趣味" ? "創作と散歩" : "集中制作"

        return [
            DemoPlanSegment(categoryName: "睡眠", startMinute: 0, durationMinutes: 480, title: "睡眠"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 480, durationMinutes: 90, title: "朝の余白"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 570, durationMinutes: 150, title: "好きなこと"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, title: "昼休み"),
            DemoPlanSegment(categoryName: afternoonCategory, startMinute: 780, durationMinutes: 180, title: afternoonTitle),
            DemoPlanSegment(categoryName: "移動", startMinute: 960, durationMinutes: 60, title: "外出"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1020, durationMinutes: 120, title: "友達と予定"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 1140, durationMinutes: 120, title: "夜ごはん"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1260, durationMinutes: 90, title: "リラックス"),
            DemoPlanSegment(categoryName: "睡眠", startMinute: 1350, durationMinutes: 90, title: "睡眠"),
        ]
    }

    private func applyTimedImportantOverrides(to segments: inout [DemoPlanSegment], dayNumber: Int) {
        let highlights: [Int: (startMinute: Int, title: String, categoryName: String, note: String)] = [
            1: (1140, "THMC", "趣味", "月カレンダーで時間つき重要予定として見せるサンプル"),
            2: (780, "講師レビュー", "仕事", "週末の重要予定サンプル"),
            8: (780, "中間発表", "仕事", "重要予定が通常の24時間予定に混ざる例"),
            13: (990, "歯医者", "移動", "時間つきでも重要なら月カレンダーに表示"),
            20: (780, "遠出MTG", "仕事", "平日の大きな予定"),
            26: (1140, "デイリー共有", "趣味", "夜の短め重要予定"),
            29: (1140, "信頼関係の話", "仕事", "夕方以降の重要予定"),
            31: (780, "カメラ研修", "仕事", "月末の重要予定")
        ]
        guard let highlight = highlights[dayNumber],
              let index = segments.firstIndex(where: { $0.startMinute == highlight.startMinute })
        else { return }

        segments[index].categoryName = highlight.categoryName
        segments[index].title = highlight.title
        segments[index].isImportant = true
        segments[index].note = highlight.note
    }

    private struct DemoImportantPlan {
        var categoryName: String
        var title: String
        var startDayOffset: Int
        var endDayOffsetExclusive: Int
        var note: String
    }

    private func insertShowcaseImportantPlans(
        monthStart: Date,
        calendar: Calendar,
        categories: [String: Category]
    ) {
        let importantPlans = [
            DemoImportantPlan(categoryName: "趣味", title: "連休プロジェクト", startDayOffset: -2, endDayOffsetExclusive: 2, note: "月をまたぐ重要予定の表示確認"),
            DemoImportantPlan(categoryName: "休憩", title: "憲法記念日", startDayOffset: 2, endDayOffsetExclusive: 3, note: "時間未指定の重要予定"),
            DemoImportantPlan(categoryName: "趣味", title: "こどもの日", startDayOffset: 4, endDayOffsetExclusive: 5, note: "祝日/イベントのサンプル"),
            DemoImportantPlan(categoryName: "勉強", title: "集中制作週間", startDayOffset: 7, endDayOffsetExclusive: 12, note: "週をまたぐ横長バーのサンプル"),
            DemoImportantPlan(categoryName: "移動", title: "合宿", startDayOffset: 14, endDayOffsetExclusive: 17, note: "複数日にまたがる重要予定"),
            DemoImportantPlan(categoryName: "仕事", title: "展示準備", startDayOffset: 20, endDayOffsetExclusive: 24, note: "友達共有で見せたい大きめの予定"),
            DemoImportantPlan(categoryName: "仕事", title: "リリース準備", startDayOffset: 29, endDayOffsetExclusive: 33, note: "翌月まで続く重要予定")
        ]

        for (index, important) in importantPlans.enumerated() {
            guard
                let start = calendar.date(byAdding: .day, value: important.startDayOffset, to: monthStart),
                let end = calendar.date(byAdding: .day, value: important.endDayOffsetExclusive, to: monthStart)
            else { continue }
            let plan = PlanBlock(
                category: categories[important.categoryName],
                title: important.title,
                startTime: start,
                endTime: end,
                isAllDay: true,
                isImportant: true,
                note: important.note,
                isPublic: true
            )
            plan.sourceEventID = "debug.preview.important.\(index)"
            modelContext.insert(plan)
        }
    }

    private func plansCoverFullDay(_ plans: [PlanBlock], on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = DayBoundary.dayStart(for: date, calendar: calendar)
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
    /// 明示フラグで使うスクリーンショット/デモ用データのため、世代更新時は既存の開発用
    /// Chapter を作り直す。リリースビルドでは RootTabView 側から呼ばれない。
    func seedDevSampleChaptersIfNeeded() {
        seedDefaultCategoriesIfNeeded()

        let chapterDescriptor = FetchDescriptor<Chapter>()
        let existingChapters = (try? modelContext.fetch(chapterDescriptor)) ?? []
        let hasCurrentSeedVersion = UserDefaults.standard.integer(
            forKey: Self.devSampleChapterSeedVersionKey
        ) >= Self.currentDevSampleChapterSeedVersion

        if hasCurrentSeedVersion && !existingChapters.isEmpty {
            return
        }

        if !existingChapters.isEmpty {
            existingChapters.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }

        let categoriesByName = Dictionary(uniqueKeysWithValues: categoryStore.allCategories().map { ($0.name, $0) })
        let calendar = Calendar.current
        let now = clock.now
        let today = DayBoundary.dayStart(for: now, calendar: calendar)
        guard let month = monthInterval(containing: today, calendar: calendar) else { return }

        insertDevSleepChapters(in: month, now: now, calendar: calendar, categories: categoriesByName)
        insertDevDaytimeChapters(in: month, now: now, calendar: calendar, categories: categoriesByName)

        if saveModelContext() {
            syncActiveCategoryCacheFromStore()
        }
        UserDefaults.standard.set(
            Self.currentDevSampleChapterSeedVersion,
            forKey: Self.devSampleChapterSeedVersionKey
        )
        markChanged()
        updateLiveActivity()
    }

    private struct DemoChapterSegment {
        var categoryName: String
        var startMinute: Int
        var durationMinutes: Int
        var note: String?
        var mood: String?
        var location: String?
        var isPublic: Bool
    }

    private func insertDevSleepChapters(
        in month: DateInterval,
        now: Date,
        calendar: Calendar,
        categories: [String: Category]
    ) {
        guard
            let sleep = categories["睡眠"],
            let previousDay = calendar.date(byAdding: .day, value: -1, to: month.start),
            let firstNightStart = calendar.date(byAdding: .minute, value: 22 * 60 + 30, to: previousDay)
        else { return }

        var nightStart = firstNightStart
        while nightStart < now && nightStart < month.end {
            guard let plannedEnd = calendar.date(byAdding: .minute, value: 8 * 60 + 30, to: nightStart) else { break }
            if plannedEnd > month.start {
                let chapter = Chapter(category: sleep, startTime: nightStart)
                chapter.endTime = plannedEnd <= now ? plannedEnd : nil
                chapter.mood = "😴"
                chapter.isPublic = false
                modelContext.insert(chapter)
            }
            guard let nextNightStart = calendar.date(byAdding: .day, value: 1, to: nightStart) else { break }
            nightStart = nextNightStart
        }
    }

    private func insertDevDaytimeChapters(
        in month: DateInterval,
        now: Date,
        calendar: Calendar,
        categories: [String: Category]
    ) {
        var didInsertActive = false
        for day in days(in: month, calendar: calendar) {
            guard day <= now, !didInsertActive else { break }
            for segment in devDaytimeChapterSegments(for: day, calendar: calendar) {
                guard
                    let category = categories[segment.categoryName],
                    let start = calendar.date(byAdding: .minute, value: segment.startMinute, to: day),
                    start <= now,
                    let plannedEnd = calendar.date(byAdding: .minute, value: segment.durationMinutes, to: start)
                else { continue }

                let chapter = Chapter(category: category, startTime: start)
                chapter.endTime = plannedEnd <= now ? plannedEnd : nil
                chapter.note = segment.note
                chapter.mood = segment.mood
                chapter.locationName = segment.location
                chapter.isPublic = segment.isPublic
                modelContext.insert(chapter)

                if plannedEnd > now {
                    didInsertActive = true
                    break
                }
            }
        }
    }

    private func devDaytimeChapterSegments(for day: Date, calendar: Calendar) -> [DemoChapterSegment] {
        let dayNumber = calendar.component(.day, from: day)
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 || weekday == 7 {
            return weekendDevDaytimeSegments(dayNumber: dayNumber)
        }
        if dayNumber.isMultiple(of: 5) {
            return driftDevDaytimeSegments(dayNumber: dayNumber)
        }
        return weekdayDevDaytimeSegments(dayNumber: dayNumber)
    }

    private func weekdayDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        let morningFocus = dayNumber.isMultiple(of: 3) ? "仕事" : "勉強"
        let afternoonFocus = dayNumber.isMultiple(of: 2) ? "勉強" : "仕事"
        return [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 60, note: "朝の準備", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "移動", startMinute: 480, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: morningFocus, startMinute: 540, durationMinutes: 165, note: morningFocus == "勉強" ? "英語の復習" : "UI整理", mood: "💪", location: morningFocus == "勉強" ? "図書館" : nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 705, durationMinutes: 15, note: nil, mood: nil, location: "移動中", isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, note: "昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: afternoonFocus, startMinute: 780, durationMinutes: 180, note: afternoonFocus == "勉強" ? "演習" : "資料作成", mood: "🔥", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, note: "コーヒー", mood: "☕️", location: "カフェ", isPublic: false),
            DemoChapterSegment(categoryName: "勉強", startMinute: 990, durationMinutes: 90, note: "復習", mood: nil, location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1140, durationMinutes: 150, note: "アプリの試作", mood: "🤩", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1290, durationMinutes: 60, note: "夜の休憩", mood: nil, location: nil, isPublic: false)
        ]
    }

    private func driftDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 75, note: "ゆっくり朝", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "移動", startMinute: 495, durationMinutes: 45, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 540, durationMinutes: 120, note: "予定より短め", mood: "📚", location: "学校", isPublic: true),
            DemoChapterSegment(categoryName: "仕事", startMinute: 660, durationMinutes: 60, note: "急ぎ対応", mood: nil, location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 90, note: "長めの昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "仕事", startMinute: 810, durationMinutes: 150, note: "作業調整", mood: "📝", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, note: "休憩", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 990, durationMinutes: 90, note: "予定外の制作", mood: "✨", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 1140, durationMinutes: 90, note: "夜の巻き返し", mood: "💪", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1230, durationMinutes: 120, note: "リカバリー", mood: nil, location: nil, isPublic: false)
        ]
    }

    private func weekendDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        let afternoonCategory = dayNumber.isMultiple(of: 2) ? "趣味" : "仕事"
        return [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 90, note: "ゆっくり朝", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 510, durationMinutes: 150, note: "散歩と創作", mood: "✨", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 660, durationMinutes: 60, note: "軽い復習", mood: "📚", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, note: "昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: afternoonCategory, startMinute: 780, durationMinutes: 180, note: afternoonCategory == "趣味" ? "友達と予定" : "集中制作", mood: afternoonCategory == "趣味" ? "🎮" : "🔥", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 960, durationMinutes: 60, note: nil, mood: nil, location: "街", isPublic: true),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1020, durationMinutes: 120, note: "自由時間", mood: "🤩", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1140, durationMinutes: 120, note: "夜ごはん", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1260, durationMinutes: 90, note: "リラックス", mood: nil, location: nil, isPublic: true)
        ]
    }

    private func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

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

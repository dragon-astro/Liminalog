import SwiftUI
import SwiftData

@Observable
@MainActor
final class ChapterStore {
    private var modelContext: ModelContext
    private let clock: any LiminalogClock
    var revision = 0

    private let defaultCategorySpecs: [(name: String, hex: String, icon: String)] = [
        ("勉強", "#2F80ED", "book.closed.fill"),
        ("仕事", "#6C5CE7", "briefcase.fill"),
        ("趣味", "#EB5757", "sparkles"),
        ("休憩", "#27AE60", "cup.and.saucer.fill"),
        ("移動", "#F2994A", "tram.fill"),
        ("睡眠", "#9B51E0", "moon.fill"),
    ]

    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock()) {
        self.modelContext = modelContext
        self.clock = clock
    }

    // MARK: - Edit locks

    func isPlanScheduleLocked(_ plan: PlanBlock, now: Date = Date()) -> Bool {
        !plan.isAllDay && DayBoundary.dayStart(for: plan.startTime) <= DayBoundary.dayStart(for: now)
    }

    func canCreatePlan(startTime: Date, isAllDay: Bool = false, now: Date = Date()) -> Bool {
        if isAllDay {
            return true
        }
        return DayBoundary.dayStart(for: startTime) > DayBoundary.dayStart(for: now)
    }

    func isChapterTimeLocked(_ chapter: Chapter, now: Date = Date()) -> Bool {
        DayBoundary.dayStart(for: chapter.startTime) < DayBoundary.dayStart(for: now)
    }

    func canCreateChapter(startTime: Date, endTime: Date, now: Date = Date()) -> Bool {
        let today = DayBoundary(date: now)
        return startTime >= today.dayStart
            && startTime < today.dayEnd
            && endTime > today.dayStart
            && endTime <= today.dayEnd
            && startTime < endTime
            && endTime <= now
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
        let actives = activeChapters()

        // 1. 同カテゴリの active があれば維持しつつ、並行して残った他 active だけ閉じる。
        if let keptActive = actives.first(where: { $0.category?.id == category.id }) {
            for active in actives where active.id != keptActive.id {
                active.endTime = now
                active.updatedAt = now
            }
            // 既に同カテゴリを記録中 → 何も新しく作らずに継続
            try? modelContext.save()
            revision += 1
            updateLiveActivity(categorySet: categorySet)
            return
        }

        // 2. 通常のカテゴリ切替。ここでは 1分未満でも削除せず、必ず終了記録を残す。
        for active in actives {
            active.endTime = now
            active.updatedAt = now
        }

        let chapter = Chapter(category: category, startTime: now)
        modelContext.insert(chapter)
        try? modelContext.save()
        revision += 1
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
        revision += 1
        updateLiveActivity()
        return true
    }

    func endActiveChapter() {
        let now = clock.now
        guard closeActiveChapters(at: now) else { return }
        try? modelContext.save()
        revision += 1
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
        let indexed = Dictionary(uniqueKeysWithValues: allCategories().map { ($0.id, $0) })
        return set.slots.map { id in id.flatMap { indexed[$0] } }
    }

    /// 割り当て済みカテゴリだけを順序保ったまま返す（Live Activity 等の表示用）
    func assignedCategories(for set: CategorySet) -> [Category] {
        slottedCategories(for: set).compactMap { $0 }
    }

    func allCategories() -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func categorySets() -> [CategorySet] {
        let descriptor = FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Chapter edits

    @discardableResult
    func saveChapter(_ chapter: Chapter, startTime: Date, endTime: Date?, category: Category?, note: String?, mood: String?, locationName: String?, isPublic: Bool) -> Bool {
        if isChapterTimeLocked(chapter, now: clock.now) {
            // 前日以前の実績はスコア公平性のため、時間とカテゴリを固定する。
            // 振り返り用のメモ/気分/場所/公開設定だけ後から編集可能。
        } else {
            chapter.startTime = startTime
            chapter.endTime = endTime
            chapter.category = category
        }
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
        return true
    }

    func setChapterVisibility(_ chapter: Chapter, isPublic: Bool) {
        chapter.isPublic = isPublic
        chapter.updatedAt = clock.now
        try? modelContext.save()
        revision += 1
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
        revision += 1
    }

    @discardableResult
    func deleteChapter(_ chapter: Chapter) -> Bool {
        guard !isChapterTimeLocked(chapter, now: clock.now) else { return false }
        modelContext.delete(chapter)
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
        return true
    }

    // MARK: - Plans

    func plannedBlocks(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        return plannedBlocks(from: boundary.dayStart, to: boundary.dayEnd)
    }

    func plannedBlocks(from start: Date, to end: Date) -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func allPlannedBlocks() -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addPlanBlock(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, isImportant: Bool = false, note: String? = nil, isPublic: Bool = true) -> Bool {
        guard canCreatePlan(startTime: startTime, isAllDay: isAllDay, now: clock.now) else { return false }
        let plan = PlanBlock(
            category: category,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (category?.name ?? "予定") : title,
            startTime: startTime,
            endTime: max(endTime, startTime.addingTimeInterval(60)),
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            isPublic: isPublic
        )
        plan.updatedAt = clock.now
        modelContext.insert(plan)
        try? modelContext.save()
        revision += 1
        return true
    }

    @discardableResult
    func savePlanBlock(_ plan: PlanBlock, category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool, isImportant: Bool, note: String?, isPublic: Bool) -> Bool {
        if isPlanScheduleLocked(plan, now: clock.now) {
            // 今日以前の時間つき予定はスコア公平性のため、内容・カテゴリ・時間を固定する。
            // 重要フラグはカレンダー俯瞰の表示だけに関わるため、後から切り替え可能。
            plan.isImportant = isImportant
        } else {
            guard canCreatePlan(startTime: startTime, isAllDay: isAllDay, now: clock.now) else { return false }
            plan.category = category
            plan.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (category?.name ?? "予定") : title
            plan.startTime = startTime
            plan.endTime = max(endTime, startTime.addingTimeInterval(60))
            plan.isAllDay = isAllDay
            plan.isImportant = isImportant
        }
        plan.note = note.flatMap { $0.isEmpty ? nil : $0 }
        plan.isPublic = isPublic
        plan.updatedAt = clock.now
        try? modelContext.save()
        revision += 1
        return true
    }

    @discardableResult
    func deletePlanBlock(_ plan: PlanBlock) -> Bool {
        guard !isPlanScheduleLocked(plan, now: clock.now) else { return false }
        modelContext.delete(plan)
        try? modelContext.save()
        revision += 1
        return true
    }

    // MARK: - Score

    func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(date: date, plans: plannedBlocks(on: date), chapters: chapters(on: date), now: clock.now)
    }

    func streakCount(endingAt date: Date = Date()) -> Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: date) else { break }
            let summary = scoreSummary(on: target)
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            count += 1
        }
        return count
    }

    func totalScore(days: Int = 365) -> Int {
        let calendar = Calendar.current
        return (0..<days).reduce(0) { partial, offset in
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { return partial }
            let summary = scoreSummary(on: target)
            return partial + Int(summary.totalScore.rounded())
        }
    }

    // MARK: - Category management

    func addCategory(name: String, colorHex: String, icon: String? = nil) {
        let all = allCategories()
        let nextOrder = (all.map(\.sortOrder).max() ?? -1) + 1
        let cat = Category(name: name, colorHex: colorHex, icon: icon, sortOrder: nextOrder)
        modelContext.insert(cat)
        try? modelContext.save()
        revision += 1
    }

    func updateCategory(_ category: Category, name: String, colorHex: String, icon: String? = nil) {
        category.name = name
        category.colorHex = colorHex
        category.icon = icon
        try? modelContext.save()
        revision += 1
    }

    func deleteCategory(_ category: Category) {
        // カテゴリが含まれるすべてのセットから、該当スロットを空きに戻す（位置は維持）
        for set in categorySets() where set.slots.contains(category.id) {
            set.slots = set.slots.map { $0 == category.id ? nil : $0 }
        }
        modelContext.delete(category)
        try? modelContext.save()
        revision += 1
    }

    // MARK: - Category sets

    func addCategorySet(name: String, slots: [UUID?]) {
        let nextOrder = (categorySets().map(\.sortOrder).max() ?? -1) + 1
        let set = CategorySet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "セット \(nextOrder + 1)" : name,
            sortOrder: nextOrder,
            slots: slots
        )
        modelContext.insert(set)
        try? modelContext.save()
        revision += 1
    }

    func updateCategorySet(_ set: CategorySet, name: String, slots: [UUID?]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        set.name = trimmed.isEmpty ? set.name : trimmed
        set.slots = CategorySet.normalize(slots)
        try? modelContext.save()
        revision += 1
    }

    func deleteCategorySet(_ set: CategorySet) {
        modelContext.delete(set)
        try? modelContext.save()
        revision += 1
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
        revision += 1
    }

    // MARK: - Seed defaults

    func seedDefaultCategoriesIfNeeded() {
        let existing = allCategories()
        let existingNames = Set(existing.map(\.name))
        var didInsert = false

        for (index, spec) in defaultCategorySpecs.enumerated() where !existingNames.contains(spec.name) {
            let cat = Category(name: spec.name, colorHex: spec.hex, icon: spec.icon, sortOrder: index, isDefault: true)
            modelContext.insert(cat)
            didInsert = true
        }

        guard didInsert else { return }
        try? modelContext.save()
        revision += 1
    }

    func seedDefaultCategorySetsIfNeeded() {
        seedDefaultCategoriesIfNeeded()
        guard categorySets().isEmpty else { return }

        let categories = allCategories()
        let byName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })

        // 平日: スロット位置を意図的に固定（左上から「主に使う順」）。空きを2つ残す。
        // 0: 勉強, 1: 仕事, 2: 移動, 3: 休憩 / 4: 睡眠, 5: 趣味, 6: 空, 7: 空
        let weekdayNames: [String?] = ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味", nil, nil]
        let weekdaySlots = weekdayNames.map { name in name.flatMap { byName[$0]?.id } }

        // 休日: 睡眠と趣味中心。空きを3つ残す。
        // 0: 睡眠, 1: 趣味, 2: 休憩, 3: 勉強 / 4: 移動, 5: 空, 6: 空, 7: 空
        let holidayNames: [String?] = ["睡眠", "趣味", "休憩", "勉強", "移動", nil, nil, nil]
        let holidaySlots = holidayNames.map { name in name.flatMap { byName[$0]?.id } }

        modelContext.insert(CategorySet(name: "平日", sortOrder: 0, slots: weekdaySlots))
        modelContext.insert(CategorySet(name: "休日", sortOrder: 1, slots: holidaySlots))
        try? modelContext.save()
        revision += 1
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
            revision += 1
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
        revision += 1
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
        revision += 1
    }

    private func updateLiveActivity(categorySet: CategorySet? = nil) {
        if #available(iOS 16.2, *) {
            let set = categorySet ?? categorySets().first
            let gridCategories = set.map { assignedCategories(for: $0) } ?? []
            Task {
                await LiveActivityManager.shared.update(
                    activeChapter: activeChapter,
                    categorySetName: set?.name ?? "カテゴリ",
                    categories: gridCategories
                )
            }
        }
    }
}

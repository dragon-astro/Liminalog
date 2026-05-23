import SwiftUI
import SwiftData

@Observable
@MainActor
final class ChapterStore {
    private var modelContext: ModelContext
    var revision = 0

    private let defaultCategorySpecs: [(name: String, hex: String, icon: String)] = [
        ("勉強", "#2F80ED", "book.closed.fill"),
        ("仕事", "#6C5CE7", "briefcase.fill"),
        ("趣味", "#EB5757", "sparkles"),
        ("休憩", "#27AE60", "cup.and.saucer.fill"),
        ("移動", "#F2994A", "tram.fill"),
        ("睡眠", "#9B51E0", "moon.fill"),
    ]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Active Chapter

    var activeChapter: Chapter? {
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Start a new chapter

    func startChapter(category: Category, categorySet: CategorySet? = nil) {
        let now = Date()
        if let active = activeChapter {
            if now.timeIntervalSince(active.startTime) < 60 {
                modelContext.delete(active)
            } else {
                active.endTime = now
            }
        }
        category.usageCount += 1
        let chapter = Chapter(category: category, startTime: now)
        modelContext.insert(chapter)
        try? modelContext.save()
        revision += 1
        updateLiveActivity(categorySet: categorySet)
    }

    func addChapter(category: Category, startTime: Date, endTime: Date, note: String? = nil, mood: String? = nil, locationName: String? = nil, isPublic: Bool = true) {
        let chapter = Chapter(category: category, startTime: startTime)
        chapter.endTime = endTime
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        category.usageCount += 1
        modelContext.insert(chapter)
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
    }

    func endActiveChapter() {
        guard let active = activeChapter else { return }
        let now = Date()
        if now.timeIntervalSince(active.startTime) < 60 {
            modelContext.delete(active)
        } else {
            active.endTime = now
        }
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
    }

    // MARK: - Today's chapters

    func todaysChapters() -> [Chapter] {
        chapters(on: Date())
    }

    func chapters(on date: Date) -> [Chapter] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < endOfDay && ($0.endTime == nil || $0.endTime! > startOfDay) },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func chapters(from start: Date, to end: Date) -> [Chapter] {
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime < end && ($0.endTime == nil || $0.endTime! > start) },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func recentChapters(limit: Int = 50) -> [Chapter] {
        var descriptor = FetchDescriptor<Chapter>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Category grid (top 8 by usage)

    func categoriesForGrid() -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Array(all.sorted {
            if $0.totalUsageCount == $1.totalUsageCount {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.totalUsageCount > $1.totalUsageCount
        }.prefix(8))
    }

    func categories(for set: CategorySet) -> [Category] {
        let all = allCategories()
        let indexed = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return set.categoryIDs.compactMap { indexed[$0] }
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

    func saveChapter(_ chapter: Chapter, startTime: Date, endTime: Date?, category: Category?, note: String?, mood: String?, locationName: String?, isPublic: Bool) {
        chapter.startTime = startTime
        chapter.endTime = endTime
        chapter.category = category
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        chapter.locationName = locationName.flatMap { $0.isEmpty ? nil : $0 }
        chapter.isPublic = isPublic
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
    }

    func setChapterVisibility(_ chapter: Chapter, isPublic: Bool) {
        chapter.isPublic = isPublic
        try? modelContext.save()
        revision += 1
    }

    func deleteChapter(_ chapter: Chapter) {
        modelContext.delete(chapter)
        try? modelContext.save()
        revision += 1
        updateLiveActivity()
    }

    // MARK: - Plans

    func plannedBlocks(on date: Date) -> [PlanBlock] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        return plannedBlocks(from: startOfDay, to: endOfDay)
    }

    func plannedBlocks(from start: Date, to end: Date) -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func addPlanBlock(category: Category?, title: String, startTime: Date, endTime: Date, isAllDay: Bool = false, note: String? = nil, isPublic: Bool = true) {
        let plan = PlanBlock(
            category: category,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (category?.name ?? "予定") : title,
            startTime: startTime,
            endTime: max(endTime, startTime.addingTimeInterval(60)),
            isAllDay: isAllDay,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            isPublic: isPublic
        )
        modelContext.insert(plan)
        try? modelContext.save()
        revision += 1
    }

    func deletePlanBlock(_ plan: PlanBlock) {
        modelContext.delete(plan)
        try? modelContext.save()
        revision += 1
    }

    // MARK: - Score

    func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(date: date, plans: plannedBlocks(on: date), chapters: chapters(on: date))
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
            guard let target = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return partial }
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
        for set in categorySets() where set.categoryIDs.contains(category.id) {
            set.categoryIDs.removeAll { $0 == category.id }
        }
        modelContext.delete(category)
        try? modelContext.save()
        revision += 1
    }

    // MARK: - Category sets

    func addCategorySet(name: String, categoryIDs: [UUID]) {
        let nextOrder = (categorySets().map(\.sortOrder).max() ?? -1) + 1
        let set = CategorySet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "セット \(nextOrder + 1)" : name,
            sortOrder: nextOrder,
            categoryIDs: Array(categoryIDs.prefix(8))
        )
        modelContext.insert(set)
        try? modelContext.save()
        revision += 1
    }

    func updateCategorySet(_ set: CategorySet, name: String, categoryIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        set.name = trimmed.isEmpty ? set.name : trimmed
        set.categoryIDs = Array(categoryIDs.prefix(8))
        try? modelContext.save()
        revision += 1
    }

    func deleteCategorySet(_ set: CategorySet) {
        modelContext.delete(set)
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
        let weekdayNames = ["勉強", "仕事", "移動", "休憩", "睡眠", "趣味"]
        let holidayNames = ["睡眠", "趣味", "休憩", "勉強", "移動"]

        let weekdayIDs = weekdayNames.compactMap { byName[$0]?.id }
        let holidayIDs = holidayNames.compactMap { byName[$0]?.id }

        modelContext.insert(CategorySet(name: "平日", sortOrder: 0, categoryIDs: weekdayIDs.isEmpty ? categories.prefix(8).map(\.id) : weekdayIDs))
        modelContext.insert(CategorySet(name: "休日", sortOrder: 1, categoryIDs: holidayIDs.isEmpty ? categories.prefix(8).map(\.id) : holidayIDs))
        try? modelContext.save()
        revision += 1
    }

    func seedPreviewPlansIfNeeded() {
        seedDefaultCategorySetsIfNeeded()

        let planDescriptor = FetchDescriptor<PlanBlock>()
        guard (try? modelContext.fetchCount(planDescriptor)) == 0 else { return }

        let categories = Dictionary(uniqueKeysWithValues: allCategories().map { ($0.name, $0) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let samples: [(String, Int, Int, String)] = [
            ("睡眠", 0, 420, "睡眠"),
            ("勉強", 9, 120, "英語と課題"),
            ("移動", 11, 45, "移動"),
            ("仕事", 13, 150, "制作作業"),
            ("休憩", 16, 45, "休憩"),
            ("趣味", 19, 120, "自由時間"),
        ]

        for (categoryName, hour, minutes, title) in samples {
            guard
                let category = categories[categoryName],
                let start = calendar.date(byAdding: .hour, value: hour, to: today),
                let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            else { continue }

            modelContext.insert(PlanBlock(category: category, title: title, startTime: start, endTime: end))
        }

        try? modelContext.save()
        revision += 1
    }

    private func updateLiveActivity(categorySet: CategorySet? = nil) {
        if #available(iOS 16.2, *) {
            let set = categorySet ?? categorySets().first
            let gridCategories = set.map { categories(for: $0) } ?? categoriesForGrid()
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

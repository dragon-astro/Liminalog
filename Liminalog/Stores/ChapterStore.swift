import SwiftUI
import SwiftData

@Observable
@MainActor
final class ChapterStore {
    private var modelContext: ModelContext

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

    func startChapter(category: Category) {
        let now = Date()
        if let active = activeChapter {
            active.endTime = now
        }
        let chapter = Chapter(category: category, startTime: now)
        modelContext.insert(chapter)
        try? modelContext.save()
    }

    func endActiveChapter() {
        guard let active = activeChapter else { return }
        active.endTime = Date()
        try? modelContext.save()
    }

    // MARK: - Today's chapters

    func todaysChapters() -> [Chapter] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= startOfDay && $0.startTime < endOfDay },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Category grid (top 8 by usage)

    func categoriesForGrid() -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Array(all.sorted { $0.usageCount > $1.usageCount }.prefix(8))
    }

    func allCategories() -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Chapter edits

    func saveChapter(_ chapter: Chapter, startTime: Date, endTime: Date?, category: Category?, note: String?, mood: String?) {
        chapter.startTime = startTime
        chapter.endTime = endTime
        chapter.category = category
        chapter.note = note.flatMap { $0.isEmpty ? nil : $0 }
        chapter.mood = mood
        try? modelContext.save()
    }

    func deleteChapter(_ chapter: Chapter) {
        modelContext.delete(chapter)
        try? modelContext.save()
    }

    // MARK: - Category management

    func addCategory(name: String, colorHex: String) {
        let all = allCategories()
        let nextOrder = (all.map(\.sortOrder).max() ?? -1) + 1
        let cat = Category(name: name, colorHex: colorHex, sortOrder: nextOrder)
        modelContext.insert(cat)
        try? modelContext.save()
    }

    func updateCategory(_ category: Category, name: String, colorHex: String) {
        category.name = name
        category.colorHex = colorHex
        try? modelContext.save()
    }

    func deleteCategory(_ category: Category) {
        modelContext.delete(category)
        try? modelContext.save()
    }

    // MARK: - Seed defaults

    func seedDefaultCategoriesIfNeeded() {
        let descriptor = FetchDescriptor<Category>()
        guard (try? modelContext.fetchCount(descriptor)) == 0 else { return }

        let defaults: [(String, String)] = [
            ("勉強", "#4A90D9"),
            ("仕事", "#5B6CF0"),
            ("趣味", "#E8654A"),
            ("休憩", "#5CB85C"),
            ("移動", "#F0AD4E"),
            ("睡眠", "#9B59B6"),
            ("食事", "#E91E8C"),
            ("運動", "#1ABC9C"),
        ]
        for (index, (name, hex)) in defaults.enumerated() {
            let cat = Category(name: name, colorHex: hex, sortOrder: index, isDefault: true)
            modelContext.insert(cat)
        }
        try? modelContext.save()
    }
}

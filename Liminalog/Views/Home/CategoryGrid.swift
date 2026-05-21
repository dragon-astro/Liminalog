import SwiftUI

struct CategoryGrid: View {
    @Environment(ChapterStore.self) private var store
    @State private var categories: [Category] = []
    @State private var activeID: UUID? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(categories) { category in
                CategoryGridButton(
                    category: category,
                    isActive: activeID == category.id
                ) {
                    store.startChapter(category: category)
                    activeID = category.id
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: store.activeChapter?.category?.id) { _, newID in
            activeID = newID
            refresh()
        }
    }

    private func refresh() {
        categories = store.categoriesForGrid()
        activeID = store.activeChapter?.category?.id
    }
}

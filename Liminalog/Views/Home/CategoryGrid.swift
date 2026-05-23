import SwiftUI

struct CategoryGrid: View {
    @Environment(ChapterStore.self) private var store
    @State private var categorySets: [CategorySet] = []
    @State private var fallbackCategories: [Category] = []
    @State private var selectedSetID: UUID?
    @State private var activeID: UUID? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 14) {
            if categorySets.isEmpty {
                categoryPage(title: nil, categories: fallbackCategories, categorySet: nil)
            } else {
                TabView(selection: $selectedSetID) {
                    ForEach(categorySets) { set in
                        categoryPage(title: set.name, categories: store.categories(for: set), categorySet: set)
                            .tag(Optional(set.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 210)

                if categorySets.count > 1 {
                    pageIndicator
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: store.activeChapter?.category?.id) { _, newID in
            activeID = newID
            refresh()
        }
        .onChange(of: store.revision) { _, _ in
            refresh()
        }
    }

    private func categoryPage(title: String?, categories: [Category], categorySet: CategorySet?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(categories.count)/8")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(categories.prefix(8)) { category in
                    CategoryGridButton(
                        category: category,
                        isActive: activeID == category.id
                    ) {
                        store.startChapter(category: category, categorySet: categorySet)
                        activeID = category.id
                    }
                }
            }
        }
    }

    private func refresh() {
        categorySets = store.categorySets()
        fallbackCategories = store.categoriesForGrid()
        if selectedSetID == nil || !categorySets.contains(where: { $0.id == selectedSetID }) {
            selectedSetID = categorySets.first?.id
        }
        activeID = store.activeChapter?.category?.id
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(categorySets) { set in
                Circle()
                    .fill(selectedSetID == set.id ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: selectedSetID == set.id ? 7 : 6, height: selectedSetID == set.id ? 7 : 6)
                    .animation(.easeInOut(duration: 0.18), value: selectedSetID)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

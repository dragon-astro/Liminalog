import SwiftUI
import SwiftData

struct CategorySettingsView: View {
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showAddSheet = false
    @State private var editingCategory: Category? = nil

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editingCategory = category
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 20, height: 20)
                        Text(category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(category.usageCount)回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.deleteCategory(categories[index])
                }
            }
        }
        .navigationTitle("カテゴリ管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryEditSheet(category: nil)
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditSheet(category: cat)
        }
    }
}

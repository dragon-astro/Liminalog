import SwiftUI
import SwiftData

struct CategorySettingsView: View {
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]

    @State private var showAddSheet = false
    @State private var showAddSetSheet = false
    @State private var editingCategory: Category? = nil
    @State private var editingSet: CategorySet? = nil

    var body: some View {
        List {
            Section {
                ForEach(categorySets) { set in
                    Button {
                        editingSet = set
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(set.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(set.categoryIDs.count)/8")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            HStack(spacing: 6) {
                                ForEach(store.categories(for: set)) { category in
                                    Image(systemName: category.icon ?? "circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(category.color)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(category.color.opacity(0.12)))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deleteCategorySet(categorySets[index])
                    }
                }
            } header: {
                sectionHeader(title: "カテゴリセット") {
                    showAddSetSheet = true
                }
            }

            Section {
                ForEach(categories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 20, height: 20)
                            Image(systemName: category.icon ?? "circle.fill")
                                .foregroundStyle(category.color)
                                .frame(width: 22)
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
            } header: {
                sectionHeader(title: "カテゴリ") {
                    showAddSheet = true
                }
            }
        }
        .navigationTitle("カテゴリ管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryEditSheet(category: nil)
        }
        .sheet(isPresented: $showAddSetSheet) {
            CategorySetEditSheet(categorySet: nil)
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditSheet(category: cat)
        }
        .sheet(item: $editingSet) { set in
            CategorySetEditSheet(categorySet: set)
        }
    }

    private func sectionHeader(title: String, addAction: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: addAction) {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("\(title)を追加")
        }
    }
}

#Preview("Category Settings") {
    NavigationStack {
        CategorySettingsView()
    }
    .liminalogPreviewEnvironment()
}

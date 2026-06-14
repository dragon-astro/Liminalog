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
    @State private var operationError: String?

    private var categoryByID: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        List {
            Section {
                if categorySets.isEmpty {
                    CategorySettingsEmptyRow(
                        text: "カテゴリセットを作ると、今日タブのカテゴリ表を切り替えられます。",
                        systemImage: "square.grid.2x2"
                    )
                }

                ForEach(categorySets) { set in
                    Button {
                        editingSet = set
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(set.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(LiminalTheme.text)
                                Spacer()
                                Text("\(set.filledCount)/8")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(LiminalTheme.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(LiminalTheme.tertiaryText)
                            }

                            HStack(spacing: 6) {
                                if assignedCategories(for: set).isEmpty {
                                    Label("カテゴリ未配置", systemImage: "plus.circle")
                                        .font(.caption)
                                        .foregroundStyle(LiminalTheme.secondaryText)
                                } else {
                                    ForEach(assignedCategories(for: set)) { category in
                                        Image(systemName: category.icon ?? "circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(category.displayColor)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(category.displayColor.opacity(0.12)))
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let deletingSets = indexSet.compactMap { index in
                        categorySets.indices.contains(index) ? categorySets[index] : nil
                    }
                    for set in deletingSets {
                        guard store.deleteCategorySet(set) else {
                            operationError = "カテゴリセットを削除できませんでした。時間をおいてもう一度試してください。"
                            return
                        }
                    }
                }
                .onMove { source, destination in
                    guard store.moveCategorySets(from: source, to: destination) else {
                        operationError = "カテゴリセットの並び順を保存できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                }
            } header: {
                sectionHeader(title: "カテゴリセット") {
                    showAddSetSheet = true
                }
            }

            Section {
                if categories.isEmpty {
                    CategorySettingsEmptyRow(
                        text: "まずは勉強・仕事・休憩などのカテゴリを追加してください。",
                        systemImage: "tag"
                    )
                }

                ForEach(categories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(category.displayColor)
                                .frame(width: 20, height: 20)
                            Image(systemName: category.icon ?? "circle.fill")
                                .foregroundStyle(category.displayColor)
                                .frame(width: 22)
                            Text(category.name)
                                .foregroundStyle(LiminalTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let deletingCategories = indexSet.compactMap { index in
                        categories.indices.contains(index) ? categories[index] : nil
                    }
                    for category in deletingCategories {
                        guard store.deleteCategory(category) else {
                            operationError = "カテゴリを削除できませんでした。時間をおいてもう一度試してください。"
                            return
                        }
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
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK") {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
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

    private func assignedCategories(for set: CategorySet) -> [Category] {
        CategorySet.normalize(set.slots).compactMap { id in
            id.flatMap { categoryByID[$0] }
        }
    }
}

private struct CategorySettingsEmptyRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(LiminalTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

#Preview("Category Settings") {
    NavigationStack {
        CategorySettingsView()
    }
    .liminalogPreviewEnvironment()
}

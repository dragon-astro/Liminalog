import SwiftUI

struct CategorySetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let categorySet: CategorySet?

    @State private var name = ""
    @State private var selectedIDs: [UUID] = []

    private var isNew: Bool { categorySet == nil }

    var body: some View {
        NavigationStack {
            List {
                Section("セット名") {
                    TextField("例: 平日", text: $name)
                }

                Section {
                    ForEach(store.allCategories()) { category in
                        Button {
                            toggle(category)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.icon ?? "circle.fill")
                                    .foregroundStyle(category.color)
                                    .frame(width: 24)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIDs.contains(category.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(category.color)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!selectedIDs.contains(category.id) && selectedIDs.count >= 8)
                    }
                } header: {
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Text("\(selectedIDs.count)/8")
                    }
                }
            }
            .navigationTitle(isNew ? "セットを追加" : "セットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedIDs.isEmpty)
                }
            }
            .onAppear {
                if let categorySet {
                    name = categorySet.name
                    selectedIDs = categorySet.categoryIDs
                }
            }
        }
    }

    private func toggle(_ category: Category) {
        if selectedIDs.contains(category.id) {
            selectedIDs.removeAll { $0 == category.id }
        } else if selectedIDs.count < 8 {
            selectedIDs.append(category.id)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let categorySet {
            store.updateCategorySet(categorySet, name: trimmed, categoryIDs: selectedIDs)
        } else {
            store.addCategorySet(name: trimmed, categoryIDs: selectedIDs)
        }
        dismiss()
    }
}

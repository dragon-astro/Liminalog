import SwiftUI
import SwiftData

struct CategorySetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @FocusState private var nameFieldFocused: Bool

    let categorySet: CategorySet?

    @State private var name = ""
    /// 編集中のスロット状態（長さ 8 で常に保持）
    @State private var slots: [UUID?] = Array(repeating: nil, count: CategorySet.slotCount)
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    private var isNew: Bool { categorySet == nil }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var assignedCount: Int { slots.compactMap { $0 }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: 平日（空でも自動命名）", text: $name)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }
                } header: {
                    Text("セット名")
                } footer: {
                    Text("空のままだと「セット ◯」が自動で付きます")
                        .font(.caption2)
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<CategorySet.slotCount, id: \.self) { index in
                            slotCell(at: index)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    HStack {
                        Text("グリッド位置")
                        Spacer()
                        Text("\(assignedCount)/\(CategorySet.slotCount)")
                            .monospacedDigit()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "セットを追加" : "セットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { nameFieldFocused = false }
                }
            }
            .onAppear { loadInitialState() }
        }
    }

    // MARK: - Slot cell

    @ViewBuilder
    private func slotCell(at index: Int) -> some View {
        let category = category(for: slots[index])

        Menu {
            slotMenu(at: index, currentCategory: category)
        } label: {
            SlotCellLabel(index: index, category: category)
        }
        .draggable(String(index))
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(Int.init), source != index else { return false }
            moveSlot(from: source, to: index)
            return true
        }
        .accessibilityLabel(category.map { "スロット\(index + 1): \($0.name)" } ?? "スロット\(index + 1): 空き")
    }

    @ViewBuilder
    private func slotMenu(at index: Int, currentCategory: Category?) -> some View {
        // 別のスロットに割り当て済みのカテゴリは候補から除外（自分のスロットの category は再選択不要なので除外）
        let assignedIDs = Set(slots.compactMap { $0 })
        let candidates = allCategories.filter { !assignedIDs.contains($0.id) }

        if let current = currentCategory {
            // 既に割り当て済みスロット
            Section {
                Text(current.name)
            }
            if !candidates.isEmpty {
                Section("別のカテゴリに変更") {
                    ForEach(candidates) { category in
                        Button {
                            assign(category.id, to: index)
                        } label: {
                            Label(category.name, systemImage: category.icon ?? "circle.fill")
                        }
                    }
                }
            }
            Button(role: .destructive) {
                assign(nil, to: index)
            } label: {
                Label("このスロットを外す", systemImage: "xmark.circle")
            }
        } else {
            // 空きスロット
            if candidates.isEmpty {
                Text("追加できるカテゴリがありません")
            } else {
                ForEach(candidates) { category in
                    Button {
                        assign(category.id, to: index)
                    } label: {
                        Label(category.name, systemImage: category.icon ?? "circle.fill")
                    }
                }
            }
        }
    }

    // MARK: - State helpers

    /// 保存可否: スロットが1つ以上埋まっていればOK。空名は Store 側で自動命名されるため許容する。
    private var canSave: Bool {
        assignedCount > 0
    }

    private func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return allCategories.first { $0.id == id }
    }

    private func assign(_ id: UUID?, to index: Int) {
        var next = slots
        next[index] = id
        slots = next
    }

    private func moveSlot(from source: Int, to destination: Int) {
        guard slots.indices.contains(source), slots.indices.contains(destination) else { return }
        var next = slots
        next.swapAt(source, destination)
        slots = next
    }

    private func loadInitialState() {
        if let categorySet {
            name = categorySet.name
            slots = CategorySet.normalize(categorySet.slots)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let categorySet {
            store.updateCategorySet(categorySet, name: trimmed, slots: slots)
        } else {
            store.addCategorySet(name: trimmed, slots: slots)
        }
        dismiss()
    }
}

// MARK: - Slot cell label

private struct SlotCellLabel: View {
    let index: Int
    let category: Category?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 40, height: 40)

                if let category {
                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(category.color)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(category?.name ?? "空き")
                .font(.caption2)
                .foregroundStyle(category == nil ? .tertiary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    category == nil ? Color(.separator).opacity(0.45) : Color.clear,
                    style: StrokeStyle(lineWidth: 1, dash: category == nil ? [4, 4] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(category?.color.opacity(0.08) ?? Color(.tertiarySystemGroupedBackground).opacity(0.5))
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fillColor: Color {
        category?.color.opacity(0.18) ?? Color(.tertiarySystemGroupedBackground)
    }
}

#Preview("Category Set Edit — Existing") {
    CategorySetEditSheet(categorySet: nil)
        .liminalogPreviewEnvironment()
}

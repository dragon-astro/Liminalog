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
    @State private var selectedSlotIndex: Int?
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    private var isNew: Bool { categorySet == nil }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var assignedCount: Int { slots.compactMap { $0 }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    settingsSection
                    slotSection
                    paletteSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
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

    // MARK: - Sections

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("セット名")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                TextField("例: 平日（空でも自動命名）", text: $name)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFieldFocused = false }

                Text("空のままだと「セット ◯」が自動で付きます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("グリッド位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(assignedCount)/\(CategorySet.slotCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<CategorySet.slotCount, id: \.self) { index in
                    slotCell(at: index)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("カテゴリ")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: paletteColumns, spacing: 10) {
                ForEach(allCategories) { category in
                    CategoryPaletteItem(
                        category: category,
                        isAssigned: slots.contains(category.id),
                        isReadyToAssign: selectedSlotIndex != nil
                    ) {
                        assignPaletteCategory(category.id)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Slot cell

    private var paletteColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 74), spacing: 10)]
    }

    @ViewBuilder
    private func slotCell(at index: Int) -> some View {
        let category = category(for: slots[index])

        SlotCellLabel(index: index, category: category)
        .overlay {
            if selectedSlotIndex == index {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
            }
        }
        .onTapGesture {
            selectedSlotIndex = selectedSlotIndex == index ? nil : index
        }
        .contextMenu {
            slotMenu(at: index, currentCategory: category)
        }
        .accessibilityLabel(category.map { "スロット\(index + 1): \($0.name)" } ?? "スロット\(index + 1): 空き")
        .accessibilityHint(selectedSlotIndex == index ? "選択中。カテゴリをタップするとこのスロットに入ります。" : "タップするとこのスロットを選択します。")
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

    private func assignCategory(_ id: UUID, to destination: Int) {
        guard let next = CategorySetSlotDraft.assignCategory(
            id,
            to: destination,
            slots: slots,
            validCategoryIDs: validCategoryIDs
        ) else { return }
        slots = next
    }

    private func assignPaletteCategory(_ id: UUID) {
        if let selectedSlotIndex {
            assignCategory(id, to: selectedSlotIndex)
            self.selectedSlotIndex = nil
        } else {
            assignToFirstAvailableSlot(id)
        }
    }

    private func assignToFirstAvailableSlot(_ id: UUID) {
        if let existingIndex = slots.firstIndex(of: id) {
            assign(nil, to: existingIndex)
            return
        }
        guard let emptyIndex = slots.firstIndex(where: { $0 == nil }) else { return }
        assignCategory(id, to: emptyIndex)
    }

    private func moveSlot(from source: Int, to destination: Int) {
        guard let next = CategorySetSlotDraft.moveSlot(from: source, to: destination, slots: slots) else { return }
        slots = next
    }

    private func handleDrop(_ items: [String], to destination: Int) -> Bool {
        guard let next = CategorySetSlotDraft.applyDrop(
            items,
            to: destination,
            slots: slots,
            validCategoryIDs: validCategoryIDs
        ) else { return false }
        slots = next
        return true
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

    private var validCategoryIDs: Set<UUID> {
        Set(allCategories.map(\.id))
    }
}

struct CategorySetSlotDraft {
    static func assignCategory(
        _ id: UUID,
        to destination: Int,
        slots: [UUID?],
        validCategoryIDs: Set<UUID>
    ) -> [UUID?]? {
        guard slots.indices.contains(destination), validCategoryIDs.contains(id) else { return nil }
        var next = slots
        for index in next.indices where index != destination && next[index] == id {
            next[index] = nil
        }
        next[destination] = id
        return next
    }

    static func moveSlot(from source: Int, to destination: Int, slots: [UUID?]) -> [UUID?]? {
        guard slots.indices.contains(source), slots.indices.contains(destination), source != destination else { return nil }
        var next = slots
        next.swapAt(source, destination)
        return next
    }

    static func applyDrop(
        _ items: [String],
        to destination: Int,
        slots: [UUID?],
        validCategoryIDs: Set<UUID>
    ) -> [UUID?]? {
        guard let payload = items.first else { return nil }

        if let source = slotIndex(from: payload) {
            return moveSlot(from: source, to: destination, slots: slots)
        }

        if let categoryID = categoryID(from: payload) {
            return assignCategory(categoryID, to: destination, slots: slots, validCategoryIDs: validCategoryIDs)
        }

        return nil
    }

    static func slotPayload(for index: Int) -> String {
        "slot:\(index)"
    }

    static func categoryPayload(for categoryID: UUID) -> String {
        "category:\(categoryID.uuidString)"
    }

    private static func slotIndex(from payload: String) -> Int? {
        guard payload.hasPrefix("slot:") else { return nil }
        return Int(payload.dropFirst("slot:".count))
    }

    private static func categoryID(from payload: String) -> UUID? {
        guard payload.hasPrefix("category:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst("category:".count)))
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

private struct CategoryPaletteItem: View {
    let category: Category
    let isAssigned: Bool
    let isReadyToAssign: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(category.color.opacity(isAssigned ? 0.24 : 0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(category.color)
                        .frame(width: 42, height: 42)

                    if isAssigned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white, category.color)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(category.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isReadyToAssign || !isAssigned ? 1 : 0.62)
        .accessibilityLabel("\(category.name)\(isAssigned ? "、割り当て済み" : "")")
        .accessibilityHint(isReadyToAssign ? "選択中のスロットに配置します。" : "最初の空きスロットに配置します。")
    }
}

#Preview("Category Set Edit — Existing") {
    CategorySetEditSheet(categorySet: nil)
        .liminalogPreviewEnvironment()
}

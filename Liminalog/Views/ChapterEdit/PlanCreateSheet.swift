import SwiftUI

struct PlanCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    private let editingPlan: PlanBlock?

    @State private var title = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var allDayEndDate = Date()
    @State private var isAllDay = false
    @State private var isImportant = false
    @State private var selectedCategory: Category?
    @State private var note = ""
    @State private var isPublic = true
    @State private var categories: [Category] = []
    @State private var categorySets: [CategorySet] = []
    @State private var showingCategoryPicker = false

    init(initialDate: Date = Date(), startsAsAllDay: Bool = false) {
        editingPlan = nil
        let calendar = Calendar.current
        let start = startsAsAllDay ? calendar.startOfDay(for: initialDate) : initialDate
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: calendar.date(byAdding: .hour, value: 1, to: start) ?? start)
        _allDayEndDate = State(initialValue: start)
        _isAllDay = State(initialValue: startsAsAllDay)
        _isImportant = State(initialValue: startsAsAllDay)
    }

    init(plan: PlanBlock) {
        editingPlan = plan
        let inclusiveEndDate = plan.isAllDay
            ? plan.endTime.addingTimeInterval(-1)
            : plan.endTime
        _title = State(initialValue: plan.title)
        _startTime = State(initialValue: plan.startTime)
        _endTime = State(initialValue: plan.endTime)
        _allDayEndDate = State(initialValue: inclusiveEndDate)
        _isAllDay = State(initialValue: plan.isAllDay)
        _isImportant = State(initialValue: plan.isAllDay || plan.isImportant)
        _selectedCategory = State(initialValue: plan.category)
        _note = State(initialValue: plan.note ?? "")
        _isPublic = State(initialValue: plan.isPublic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("予定名") {
                    TextField("例: ゼミ発表", text: $title)
                        .disabled(isScheduleLocked)
                }

                Section("カテゴリ") {
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            CategoryPreviewIcon(category: selectedCategory)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCategory?.name ?? "カテゴリを選択")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(selectedCategorySetName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isScheduleLocked)
                }

                Section("時間") {
                    Toggle("重要な予定としてカレンダーに表示", isOn: $isImportant)
                    Toggle("時間未指定", isOn: $isAllDay)
                        .disabled(isScheduleLocked)
                    if !isAllDay {
                        DatePicker("開始", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                            .disabled(isScheduleLocked)
                        DatePicker("終了", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                            .disabled(isScheduleLocked)
                    } else {
                        DatePicker("開始日", selection: $startTime, displayedComponents: [.date])
                            .disabled(isScheduleLocked)
                        DatePicker("終了日", selection: $allDayEndDate, displayedComponents: [.date])
                            .disabled(isScheduleLocked)
                    }

                    if isScheduleLocked {
                        Label("今日以前の時間つき予定はスコア公平性のため、内容・カテゴリ・時間を変更できません。重要表示・メモ・公開設定は編集できます。", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !canPlaceSchedule {
                        Label("予定は明日以降の日付にだけ追加できます。当日のスコアは前日までに組んだ予定を基準にします。", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let timeValidationMessage {
                        Label(timeValidationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("メモ") {
                    TextField("メモを追加...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("公開設定") {
                    Toggle(isOn: $isPublic) {
                        Label(isPublic ? "友達に見せる" : "自分だけ", systemImage: isPublic ? "eye" : "eye.slash")
                    }
                }
            }
            .navigationTitle(editingPlan == nil ? "予定を追加" : "予定を編集")
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
            }
            .onAppear {
                categories = store.allCategories()
                categorySets = store.categorySets()
                if selectedCategory == nil {
                    selectedCategory = categories.first
                }
            }
            .onChange(of: startTime) { _, newValue in
                guard isAllDay else { return }
                let startOfNewDay = Calendar.current.startOfDay(for: newValue)
                if allDayEndDate < startOfNewDay {
                    allDayEndDate = startOfNewDay
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                PlanCategoryPickerSheet(
                    categorySets: categorySets,
                    categories: categories,
                    selectedCategory: $selectedCategory
                )
            }
        }
    }

    private var selectedCategorySetName: String {
        guard let selectedCategory else { return "未選択" }
        if let set = categorySets.first(where: { $0.assignedIDs.contains(selectedCategory.id) }) {
            return "\(set.name) セット"
        }
        return "すべてのカテゴリ"
    }

    private var canSave: Bool {
        if isScheduleLocked {
            return true
        }
        let titleOK = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let timeOK: Bool
        if isAllDay {
            let calendar = Calendar.current
            timeOK = calendar.startOfDay(for: allDayEndDate) >= calendar.startOfDay(for: startTime)
        } else {
            timeOK = endTime > startTime
        }
        return titleOK && timeOK && canPlaceSchedule
    }

    private var timeValidationMessage: String? {
        if isAllDay {
            let calendar = Calendar.current
            if calendar.startOfDay(for: allDayEndDate) < calendar.startOfDay(for: startTime) {
                return "終了日は開始日以降にしてください。"
            }
        } else if endTime <= startTime {
            return "終了時刻は開始時刻より後にしてください。"
        }
        return nil
    }

    private var isScheduleLocked: Bool {
        editingPlan.map { store.isPlanScheduleLocked($0) } ?? false
    }

    private var canPlaceSchedule: Bool {
        store.canCreatePlan(startTime: startTime, isAllDay: isAllDay)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let resolvedStart: Date
        let resolvedEnd: Date
        if isAllDay {
            let dayStart = calendar.startOfDay(for: startTime)
            let inclusiveEndDay = max(calendar.startOfDay(for: allDayEndDate), dayStart)
            resolvedStart = dayStart
            resolvedEnd = calendar.date(byAdding: .day, value: 1, to: inclusiveEndDay) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        } else {
            resolvedStart = startTime
            resolvedEnd = endTime
        }
        let didSave: Bool
        if let editingPlan {
            didSave = store.savePlanBlock(
                editingPlan,
                category: selectedCategory,
                title: trimmedTitle,
                startTime: resolvedStart,
                endTime: resolvedEnd,
                isAllDay: isAllDay,
                isImportant: isImportant,
                note: note,
                isPublic: isPublic
            )
        } else {
            didSave = store.addPlanBlock(
                category: selectedCategory,
                title: trimmedTitle,
                startTime: resolvedStart,
                endTime: resolvedEnd,
                isAllDay: isAllDay,
                isImportant: isImportant,
                note: note,
                isPublic: isPublic
            )
        }
        if didSave {
            dismiss()
        }
    }
}

private struct PlanCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categorySets: [CategorySet]
    let categories: [Category]
    @Binding var selectedCategory: Category?

    @State private var selectedSetID: UUID?

    init(categorySets: [CategorySet], categories: [Category], selectedCategory: Binding<Category?>) {
        self.categorySets = categorySets
        self.categories = categories
        self._selectedCategory = selectedCategory

        let selected = selectedCategory.wrappedValue
        let initialSet = selected.flatMap { category in
            categorySets.first { $0.assignedIDs.contains(category.id) }
        } ?? categorySets.first
        _selectedSetID = State(initialValue: initialSet?.id)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !categorySets.isEmpty {
                        setSelector
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(displayedSlots.indices, id: \.self) { index in
                            let category = displayedSlots[index]
                            Button {
                                if let category {
                                    selectedCategory = category
                                    dismiss()
                                }
                            } label: {
                                CategoryGridPickCell(
                                    index: index,
                                    category: category,
                                    isSelected: category?.id == selectedCategory?.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(category == nil)
                        }
                    }

                    let uncategorized = categoriesNotInDisplayedSet
                    if !uncategorized.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("その他")
                                .font(.headline)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(uncategorized) { category in
                                    Button {
                                        selectedCategory = category
                                        dismiss()
                                    } label: {
                                        CategoryGridPickCell(
                                            index: nil,
                                            category: category,
                                            isSelected: category.id == selectedCategory?.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("カテゴリを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var setSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categorySets) { set in
                    Button {
                        selectedSetID = set.id
                    } label: {
                        Text(set.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSetID == set.id ? .white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                Capsule()
                                    .fill(selectedSetID == set.id ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayedSlots: [Category?] {
        guard let set = selectedSet else {
            return categories.map { Optional($0) }
        }
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return CategorySet.normalize(set.slots).map { id in id.flatMap { categoryByID[$0] } }
    }

    private var selectedSet: CategorySet? {
        guard let selectedSetID else { return nil }
        return categorySets.first { $0.id == selectedSetID }
    }

    private var categoriesNotInDisplayedSet: [Category] {
        guard let selectedSet else { return [] }
        let displayedIDs = Set(selectedSet.assignedIDs)
        return categories.filter { !displayedIDs.contains($0.id) }
    }
}

private struct CategoryPreviewIcon: View {
    let category: Category?

    var body: some View {
        ZStack {
            Circle()
                .fill((category?.color ?? Color(.systemGray3)).opacity(0.16))
                .frame(width: 38, height: 38)

            Image(systemName: category?.icon ?? "circle.dashed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(category?.color ?? .secondary)
        }
    }
}

private struct CategoryGridPickCell: View {
    let index: Int?
    let category: Category?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(fillColor)
                    .frame(width: 42, height: 42)

                Image(systemName: category?.icon ?? "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(category?.color ?? Color(.tertiaryLabel))
                    .frame(width: 42, height: 42)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, category?.color ?? Color.accentColor)
                        .offset(x: 4, y: -4)
                }
            }

            Text(category?.name ?? "空き")
                .font(.caption2.weight(category == nil ? .regular : .semibold))
                .foregroundStyle(category == nil ? .tertiary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 86)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(accessibilityText)
    }

    private var fillColor: Color {
        category?.color.opacity(isSelected ? 0.24 : 0.16) ?? Color(.tertiarySystemGroupedBackground)
    }

    private var backgroundColor: Color {
        if let category {
            return category.color.opacity(isSelected ? 0.13 : 0.07)
        }
        return Color(.tertiarySystemGroupedBackground).opacity(0.55)
    }

    private var borderColor: Color {
        if let category {
            return category.color.opacity(isSelected ? 0.72 : 0.18)
        }
        return Color(.separator).opacity(0.32)
    }

    private var accessibilityText: String {
        if let category {
            return isSelected ? "\(category.name) 選択中" : category.name
        }
        if let index {
            return "スロット\(index + 1) 空き"
        }
        return "空き"
    }
}

#Preview("Create Plan") {
    PlanCreateSheet()
        .liminalogPreviewEnvironment()
}

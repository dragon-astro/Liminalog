import SwiftUI
import SwiftData

struct PlanCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]

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
            ScrollView {
                VStack(spacing: 14) {
                    planPreviewCard
                    planTitleCard
                    categoryCard
                    timeCard
                    noteCard
                    visibilityCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
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

    private var planPreviewCard: some View {
        let tint = selectedTint
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CategoryPreviewIcon(category: selectedCategory, size: 52)

                VStack(alignment: .leading, spacing: 7) {
                    Text(previewTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(previewTimeText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isImportant ? "star.fill" : "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
            }

            HStack(spacing: 8) {
                PlanPreviewBadge(text: isAllDay ? "時間未指定" : "時間指定", systemImage: isAllDay ? "sun.max.fill" : "clock.fill", tint: tint)
                PlanPreviewBadge(text: isPublic ? "共有" : "非公開", systemImage: isPublic ? "eye.fill" : "eye.slash.fill", tint: isPublic ? Color.green : Color.secondary)
                if isImportant {
                    PlanPreviewBadge(text: "重要", systemImage: "star.fill", tint: Color.yellow)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: tint)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    private var planTitleCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "予定名", systemImage: "text.cursor", tint: selectedTint)
                TextField("例: ゼミ発表", text: $title)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(isScheduleLocked)
            }
        }
    }

    private var categoryCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "カテゴリ", systemImage: "square.grid.2x2.fill", tint: selectedTint)

                Button {
                    showingCategoryPicker = true
                } label: {
                    HStack(spacing: 12) {
                        CategoryPreviewIcon(category: selectedCategory, size: 42)

                        VStack(alignment: .leading, spacing: 3) {
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
                    .padding(12)
                    .background(selectedTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isScheduleLocked)
            }
        }
    }

    private var timeCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                PlanEditorSectionHeader(title: "時間", systemImage: "clock.fill", tint: selectedTint)

                Toggle(isOn: $isImportant) {
                    Label("重要な予定", systemImage: "star.fill")
                }
                .tint(selectedTint)

                Toggle(isOn: $isAllDay) {
                    Label("時間未指定", systemImage: "sun.max.fill")
                }
                .tint(selectedTint)
                .disabled(isScheduleLocked)

                VStack(spacing: 10) {
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
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                validationStatus
            }
        }
    }

    private var noteCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "メモ", systemImage: "note.text", tint: selectedTint)
                TextField("メモを追加...", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            Toggle(isOn: $isPublic) {
                PlanEditorSectionHeader(title: isPublic ? "友達に見せる" : "自分だけ", systemImage: isPublic ? "eye.fill" : "eye.slash.fill", tint: isPublic ? Color.green : Color.secondary)
            }
            .tint(selectedTint)
        }
    }

    @ViewBuilder
    private var validationStatus: some View {
        if isScheduleLocked {
            PlanEditorStatusLabel(
                text: "今日以前の時間つき予定は、重要表示・メモ・公開設定のみ編集できます。",
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if !canPlaceSchedule {
            PlanEditorStatusLabel(
                text: "予定は明日以降の日付にだけ追加できます。",
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if let timeValidationMessage {
            PlanEditorStatusLabel(
                text: timeValidationMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    private var selectedCategorySetName: String {
        guard let selectedCategory else { return "未選択" }
        if let set = categorySets.first(where: { $0.assignedIDs.contains(selectedCategory.id) }) {
            return "\(set.name) セット"
        }
        return "すべてのカテゴリ"
    }

    private var selectedTint: Color {
        selectedCategory?.color ?? Color.accentColor
    }

    private var previewTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (editingPlan == nil ? "新しい予定" : "予定") : trimmed
    }

    private var previewTimeText: String {
        let calendar = Calendar.current
        if isAllDay {
            let start = calendar.startOfDay(for: startTime)
            let end = calendar.startOfDay(for: allDayEndDate)
            if calendar.isDate(start, inSameDayAs: end) {
                return "\(start.japaneseMonthDayShortWeekday) 終日"
            }
            return "\(start.japaneseMonthDayShortWeekday) - \(end.japaneseMonthDayShortWeekday)"
        }

        if calendar.isDate(startTime, inSameDayAs: endTime) {
            return "\(startTime.japaneseMonthDayShortWeekday) \(startTime.shortTime) - \(endTime.shortTime)"
        }
        return "\(startTime.japaneseMonthDayShortWeekday) \(startTime.shortTime) - \(endTime.japaneseMonthDayShortWeekday) \(endTime.shortTime)"
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

private struct PlanEditorCard<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct PlanEditorSectionHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.headline)
        }
    }
}

private struct PlanPreviewBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct PlanEditorStatusLabel: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
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
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill((category?.color ?? Color(.systemGray3)).opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: category?.icon ?? "circle.dashed")
                .font(.system(size: max(15, size * 0.42), weight: .semibold))
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

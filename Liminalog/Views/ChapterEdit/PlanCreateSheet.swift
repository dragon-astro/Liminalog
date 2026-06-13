import SwiftUI
import SwiftData

struct PlanCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

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
    @State private var showingAudiencePicker = false
    @State private var audienceFriendIDs: [UUID] = []
    @State private var audienceSource: AudienceSource = .categoryDefaultSnapshot
    @State private var didInitializeAudience = false
    @State private var saveError: String?
    @State private var errorTitle = "保存できませんでした"
    @State private var showDeleteConfirm = false

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
        _audienceFriendIDs = State(initialValue: plan.audienceFriendIDs)
        _audienceSource = State(initialValue: plan.audienceSource)
        _didInitializeAudience = State(initialValue: plan.hasAudienceSnapshot)
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
                    if editingPlan != nil {
                        deleteCard
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(LiminalTheme.canvasGradient)
            .navigationTitle(editingPlan == nil ? "予定を追加" : "予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        LiminalHaptics.lightImpact(intensity: 0.45)
                        dismiss()
                    }
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
                if editingPlan == nil, selectedCategory == nil {
                    isPublic = false
                }
                if !didInitializeAudience {
                    resetAudienceToCategoryDefault()
                    didInitializeAudience = true
                }
            }
            .onChange(of: selectedCategory?.id) { _, _ in
                guard didInitializeAudience, audienceSource == .categoryDefaultSnapshot else { return }
                resetAudienceToCategoryDefault()
            }
            .onChange(of: isImportant) { _, _ in
                LiminalHaptics.selection()
            }
            .onChange(of: isAllDay) { _, _ in
                LiminalHaptics.selection()
            }
            .onChange(of: isPublic) { _, _ in
                LiminalHaptics.selection()
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
            .sheet(isPresented: $showingAudiencePicker) {
                AudienceSnapshotPickerSheet(audienceFriendIDs: $audienceFriendIDs)
            }
            .alert(errorTitle, isPresented: saveErrorPresented) {
                Button("OK") {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog("予定を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    deletePlan()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この予定は元に戻せません。")
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
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)

                    Text(previewTimeText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isImportant ? "star.fill" : "calendar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .liminalGlassFill(in: Circle())
            }

            HStack(spacing: 8) {
                PlanPreviewBadge(text: isAllDay ? "終日" : "時間指定", systemImage: isAllDay ? "sun.max.fill" : "clock.fill", tint: tint)
                PlanPreviewBadge(text: isPublic ? "共有" : "非公開", systemImage: isPublic ? "eye.fill" : "eye.slash.fill", tint: isPublic ? LiminalTheme.accent : LiminalTheme.secondaryText)
                if isImportant {
                    PlanPreviewBadge(text: "重要", systemImage: "star.fill", tint: LiminalTheme.reward)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
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
                TextField(text: $title) {
                    Text(planTitlePlaceholder)
                        .foregroundStyle(LiminalTheme.tertiaryText)
                }
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(isScheduleLocked)

                if !isScheduleLocked && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    PlanEditorStatusLabel(
                        text: "未入力の場合は「\(fallbackPlanTitle)」として登録します。",
                        systemImage: "sparkles",
                        tint: .secondary
                    )
                }
            }
        }
    }

    private var categoryCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "カテゴリ", systemImage: "square.grid.2x2.fill", tint: selectedTint)

                Button {
                    LiminalHaptics.openSheet()
                    showingCategoryPicker = true
                } label: {
                    HStack(spacing: 12) {
                        CategoryPreviewIcon(category: selectedCategory, size: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCategory?.name ?? "カテゴリを選択")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                            Text(selectedCategorySetName)
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiminalTheme.tertiaryText)
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
                    Label("終日", systemImage: "sun.max.fill")
                }
                .tint(selectedTint)
                .disabled(isScheduleLocked)

                VStack(spacing: 10) {
                    if !isAllDay {
                        DatePicker("開始", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                            .foregroundStyle(LiminalTheme.text)
                            .tint(LiminalTheme.text)
                            .allowsHitTesting(!isScheduleLocked)
                        DatePicker("終了", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                            .foregroundStyle(LiminalTheme.text)
                            .tint(LiminalTheme.text)
                            .allowsHitTesting(!isScheduleLocked)
                    } else {
                        DatePicker("開始日", selection: $startTime, displayedComponents: [.date])
                            .foregroundStyle(LiminalTheme.text)
                            .tint(LiminalTheme.text)
                            .allowsHitTesting(!isScheduleLocked)
                        DatePicker("終了日", selection: $allDayEndDate, displayedComponents: [.date])
                            .foregroundStyle(LiminalTheme.text)
                            .tint(LiminalTheme.text)
                            .allowsHitTesting(!isScheduleLocked)
                    }
                }
                .padding(12)
                .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                    .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isPublic) {
                    PlanEditorSectionHeader(title: isPublic ? "友達に見せる" : "自分だけ", systemImage: isPublic ? "eye.fill" : "eye.slash.fill", tint: isPublic ? LiminalTheme.accent : LiminalTheme.secondaryText)
                }
                .tint(selectedTint)

                if isPublic {
                    Button {
                        LiminalHaptics.openSheet()
                        showingAudiencePicker = true
                        audienceSource = .custom
                    } label: {
                        AudienceSummaryRow(
                            title: "公開相手",
                            count: audienceFriendIDs.count,
                            systemImage: "person.2.fill",
                            tint: selectedTint
                        )
                        .padding(12)
                        .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        LiminalHaptics.selection()
                        resetAudienceToCategoryDefault()
                    } label: {
                        Label("カテゴリ既定値に戻す", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
    }

    private var deleteCard: some View {
        PlanEditorCard(tint: isScheduleLocked ? LiminalTheme.secondaryText : Color.red) {
            if isScheduleLocked {
                PlanEditorStatusLabel(
                    text: "今日以前の時間指定の予定は削除できません。",
                    systemImage: "lock.fill",
                    tint: LiminalTheme.secondaryText
                )
            } else {
                Button(role: .destructive) {
                    LiminalHaptics.warning()
                    showDeleteConfirm = true
                } label: {
                    Label("予定を削除", systemImage: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var validationStatus: some View {
        if isScheduleLocked {
            PlanEditorStatusLabel(
                text: "今日以前の時間指定の予定は、重要表示・メモ・公開設定のみ編集できます。",
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if let timeValidationMessage {
            PlanEditorStatusLabel(
                text: timeValidationMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if !canPlaceSchedule {
            PlanEditorStatusLabel(
                text: "予定は明日以降の日付にだけ追加できます。",
                systemImage: "lock.fill",
                tint: .secondary
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
        selectedCategory?.displayColor ?? LiminalTheme.accent
    }

    private var previewTitle: String {
        resolvedPlanTitle
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
        let timeOK: Bool
        if isAllDay {
            let calendar = Calendar.current
            timeOK = calendar.startOfDay(for: allDayEndDate) >= calendar.startOfDay(for: startTime)
        } else {
            timeOK = endTime > startTime
        }
        return timeOK && canPlaceSchedule
    }

    private var planTitlePlaceholder: String {
        fallbackPlanTitle
    }

    private var fallbackPlanTitle: String {
        let categoryName = selectedCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return categoryName.isEmpty ? "予定" : categoryName
    }

    private var resolvedPlanTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackPlanTitle : trimmed
    }

    private var timeValidationMessage: String? {
        if isAllDay {
            let calendar = Calendar.current
            if calendar.startOfDay(for: allDayEndDate) < calendar.startOfDay(for: startTime) {
                return "終了日は開始日以降にしてください。"
            }
        } else if endTime <= startTime {
            return "終了時刻は開始時刻より後にしてください。"
        } else if store.hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: editingPlan?.id) {
            return "既存の予定と時間が重なっています。"
        }
        return nil
    }

    private var isScheduleLocked: Bool {
        editingPlan.map { store.isPlanScheduleLocked($0) } ?? false
    }

    private var canPlaceSchedule: Bool {
        store.canCreatePlan(
            startTime: startTime,
            endTime: resolvedEndTime,
            isAllDay: isAllDay,
            excluding: editingPlan?.id
        )
    }

    private var resolvedEndTime: Date {
        guard isAllDay else { return endTime }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: startTime)
        let inclusiveEndDay = max(calendar.startOfDay(for: allDayEndDate), dayStart)
        return calendar.date(byAdding: .day, value: 1, to: inclusiveEndDay) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    }

    private func resetAudienceToCategoryDefault() {
        audienceFriendIDs = AudienceResolver.categoryDefaultAudience(
            for: selectedCategory,
            friendSets: friendSets,
            friends: friends
        )
        audienceSource = .categoryDefaultSnapshot
    }

    private func save() {
        errorTitle = "保存できませんでした"
        let planTitle = resolvedPlanTitle
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
                title: planTitle,
                startTime: resolvedStart,
                endTime: resolvedEnd,
                isAllDay: isAllDay,
                isImportant: isImportant,
                note: note,
                isPublic: isPublic,
                audienceFriendIDs: audienceFriendIDs,
                audienceSource: audienceSource,
                hasAudienceSnapshot: shouldSaveAudienceSnapshot
            )
        } else {
            didSave = store.addPlanBlock(
                category: selectedCategory,
                title: planTitle,
                startTime: resolvedStart,
                endTime: resolvedEnd,
                isAllDay: isAllDay,
                isImportant: isImportant,
                note: note,
                isPublic: isPublic,
                audienceFriendIDs: audienceFriendIDs,
                audienceSource: audienceSource,
                hasAudienceSnapshot: shouldSaveAudienceSnapshot
            )
        }
        if didSave {
            LiminalHaptics.commit()
            dismiss()
        } else {
            LiminalHaptics.failure()
            saveError = "予定を保存できませんでした。時間をおいてもう一度試してください。"
        }
    }

    private func deletePlan() {
        guard let editingPlan else { return }
        errorTitle = "削除できませんでした"
        guard store.deletePlanBlock(editingPlan) else {
            LiminalHaptics.failure()
            saveError = "予定を削除できませんでした。時間をおいてもう一度試してください。"
            return
        }
        LiminalHaptics.commit()
        dismiss()
    }

    private var shouldSaveAudienceSnapshot: Bool {
        AudienceSnapshotPolicy.shouldSaveSnapshot(
            isPublic: isPublic,
            audienceSource: audienceSource,
            audienceFriendIDs: audienceFriendIDs
        )
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented {
                saveError = nil
            }
        }
    }
}

struct PlanEditorCard<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LiminalTheme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.1), lineWidth: 1)
            )
    }
}

struct PlanEditorSectionHeader: View {
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

struct PlanPreviewBadge: View {
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

struct PlanEditorStatusLabel: View {
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

struct PlanCategoryPickerSheet: View {
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
                                    LiminalHaptics.selection()
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
            .background(LiminalTheme.canvasGradient)
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
                                    .fill(selectedSetID == set.id ? LiminalTheme.accent : LiminalTheme.surface)
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

struct CategoryPreviewIcon: View {
    let category: Category?
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill((category?.displayColor ?? LiminalTheme.secondaryText).opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: category?.icon ?? "circle.dashed")
                .font(.system(size: max(15, size * 0.42), weight: .semibold))
                .foregroundStyle(category?.displayColor ?? LiminalTheme.secondaryText)
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
                    .foregroundStyle(category?.displayColor ?? LiminalTheme.tertiaryText)
                    .frame(width: 42, height: 42)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, category?.displayColor ?? LiminalTheme.accent)
                        .offset(x: 4, y: -4)
                }
            }

            Text(category?.name ?? "空き")
                .font(.caption2.weight(category == nil ? .regular : .semibold))
                .foregroundStyle(category == nil ? LiminalTheme.tertiaryText : LiminalTheme.text)
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
        category?.displayColor.opacity(isSelected ? 0.24 : 0.16) ?? LiminalTheme.elevated
    }

    private var backgroundColor: Color {
        if let category {
            return category.displayColor.opacity(isSelected ? 0.13 : 0.07)
        }
        return LiminalTheme.elevated.opacity(0.55)
    }

    private var borderColor: Color {
        if let category {
            return category.displayColor.opacity(isSelected ? 0.72 : 0.18)
        }
        return LiminalTheme.divider.opacity(0.64)
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

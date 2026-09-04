import SwiftUI
import SwiftData

struct PlanCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var planPresetStore
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @Query(sort: \PlanPreset.sortOrder) private var planPresets: [PlanPreset]

    private let editingPlan: PlanBlock?
    private let snapshotEditor: SnapshotEditor?

    private struct SnapshotEditor {
        let initial: PlanTemplateSnapshot
        let onSave: (PlanTemplateSnapshot) -> String?
        let onDelete: (() -> Void)?
    }

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
    @State private var showingPresetChoices = false
    @State private var showingDeleteConfirmation = false
    @State private var audienceFriendIDs: [UUID] = []
    @State private var audienceSource: AudienceSource = .categoryDefaultSnapshot
    @State private var didInitializeAudience = false
    @State private var saveError: String?
    @State private var errorTitle = "保存できませんでした"
    @State private var editingPreset: PlanPreset?
    @State private var templateStartMinute = 0
    @State private var templateEndMinute = 60

    init(initialDate: Date = Date(), startsAsAllDay: Bool = false) {
        editingPlan = nil
        snapshotEditor = nil
        let calendar = Calendar.current
        let start = startsAsAllDay ? calendar.startOfDay(for: initialDate) : initialDate
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: calendar.date(byAdding: .hour, value: 1, to: start) ?? start)
        _allDayEndDate = State(initialValue: start)
        _isAllDay = State(initialValue: startsAsAllDay)
        _isImportant = State(initialValue: false)
    }

    init(plan: PlanBlock) {
        editingPlan = plan
        snapshotEditor = nil
        let inclusiveEndDate = plan.isAllDay
            ? plan.endTime.addingTimeInterval(-1)
            : plan.endTime
        _title = State(initialValue: plan.title)
        _startTime = State(initialValue: plan.startTime)
        _endTime = State(initialValue: plan.endTime)
        _allDayEndDate = State(initialValue: inclusiveEndDate)
        _isAllDay = State(initialValue: plan.isAllDay)
        _isImportant = State(initialValue: plan.isImportant)
        _selectedCategory = State(initialValue: plan.category)
        _note = State(initialValue: plan.note ?? "")
        _isPublic = State(initialValue: plan.isPublic)
        _audienceFriendIDs = State(initialValue: plan.audienceFriendIDs)
        _audienceSource = State(initialValue: plan.audienceSource)
        _didInitializeAudience = State(initialValue: plan.hasAudienceSnapshot)
    }

    /// Edits a value inside a day preset, never a dated PlanBlock.
    init(
        snapshot: PlanTemplateSnapshot,
        onSaveSnapshot: @escaping (PlanTemplateSnapshot) -> String?,
        onDeleteSnapshot: (() -> Void)? = nil
    ) {
        editingPlan = nil
        snapshotEditor = SnapshotEditor(initial: snapshot, onSave: onSaveSnapshot, onDelete: onDeleteSnapshot)
        _title = State(initialValue: snapshot.title)
        _templateStartMinute = State(initialValue: snapshot.startMinute)
        _templateEndMinute = State(initialValue: snapshot.endMinute)
        _isAllDay = State(initialValue: snapshot.isAllDay)
        _isImportant = State(initialValue: snapshot.isImportant)
        _note = State(initialValue: snapshot.note ?? "")
        _isPublic = State(initialValue: snapshot.isPublic)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    planTitleCard
                    compactColumns {
                        categoryCard
                        visibilityCard
                    }
                    timeCard
                    noteCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(LiminalTheme.canvasGradient)
            .navigationTitle(editingPlan != nil || snapshotEditor?.onDelete != nil ? "予定を編集" : "予定を追加")
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
                ToolbarItem(placement: .secondaryAction) {
                    // secondaryAction 自体が標準の三点メニューに入るので、Menuを重ねない。
                    Button {
                        saveAsPreset()
                    } label: {
                        Label("プリセットとして保存", systemImage: "bookmark")
                    }
                    .disabled(!canSave)
                }
                if editingPlan != nil || snapshotEditor?.onDelete != nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("予定を削除", systemImage: "trash", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .disabled(isScheduleLocked)
                    }
                }
            }
            .onAppear {
                if selectedCategory == nil {
                    if let snapshotEditor {
                        selectedCategory = categories.first { $0.id == snapshotEditor.initial.categoryID }
                    } else if editingPlan == nil {
                        selectedCategory = categories.first
                    }
                }
                if snapshotEditor == nil, editingPlan == nil, selectedCategory == nil {
                    isPublic = false
                }
                if snapshotEditor == nil, !didInitializeAudience {
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
            .sheet(isPresented: $showingPresetChoices) {
                NavigationStack {
                    ScrollView { presetChips.padding(16) }
                        .background(LiminalTheme.plainSheetBackground)
                        .navigationTitle("予定プリセット")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { showingPresetChoices = false }
                            }
                        }
                        .sheet(item: $editingPreset) { preset in
                            PlanPresetEditSheet(preset: preset)
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("予定を削除しますか？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deletePlan() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は元に戻せません。")
            }
            .alert(errorTitle, isPresented: saveErrorPresented) {
                Button("OK") {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
        .presentationDragIndicator(.visible)
    }

    private var presetChips: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(
                    title: "プリセット",
                    systemImage: "bookmark.fill",
                    tint: selectedTint
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(planPresets) { preset in
                            Button {
                                applyPreset(
                                    preset,
                                    usesPresetStartTime: preset.placementMode == .fixedTime
                                )
                            } label: {
                                Text(preset.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(LiminalTheme.text)
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(
                                        category(for: preset)?.displayColor.opacity(0.12)
                                            ?? LiminalTheme.elevated,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                category(for: preset)?.displayColor.opacity(0.28)
                                                    ?? LiminalTheme.divider.opacity(0.5),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    applyPreset(
                                        preset,
                                        usesPresetStartTime: preset.placementMode != .fixedTime
                                    )
                                } label: {
                                    Label(
                                        preset.placementMode == .fixedTime
                                            ? "長さだけを使う"
                                            : "開始時刻もプリセットに合わせる",
                                        systemImage: preset.placementMode == .fixedTime
                                            ? "timer"
                                            : "clock.arrow.circlepath"
                                    )
                                }
                                Button {
                                    editingPreset = preset
                                } label: {
                                    Label("プリセットを編集", systemImage: "pencil")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func compactColumns<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout { content() }
    }

    private var planTitleCard: some View {
        PlanEditorCard(tint: selectedTint) {
            HStack(spacing: 10) {
                CategoryPreviewIcon(category: selectedCategory, size: 36)
                TextField(planTitlePlaceholder, text: $title, axis: .vertical)
                    .font(.headline)
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1...3)
                    .frame(minHeight: 44)
                    .disabled(isScheduleLocked)
                    .accessibilityLabel("予定名")
                if !planPresets.isEmpty, !isScheduleLocked {
                    Button { showingPresetChoices = true } label: {
                        Image(systemName: "bookmark")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("予定プリセットを選ぶ")
                }
            }
            .foregroundStyle(selectedTint)
        }
    }

    private var categoryCard: some View {
        Button {
            LiminalHaptics.openSheet()
            showingCategoryPicker = true
        } label: {
            PlanEditorCard(tint: selectedTint) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("カテゴリ", systemImage: "square.grid.2x2")
                        .font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                    HStack(spacing: 6) {
                        Text(selectedCategory?.name ?? "未設定")
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(selectedTint)
                    .frame(minHeight: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(isScheduleLocked)
    }

    private var visibilityCard: some View {
        Menu {
            Toggle("友達に見せる", isOn: $isPublic)
            if isPublic, snapshotEditor == nil {
                Button("公開相手を選ぶ", systemImage: "person.2") {
                    showingAudiencePicker = true
                    audienceSource = .custom
                }
                Button("カテゴリ既定値に戻す", systemImage: "arrow.counterclockwise") {
                    resetAudienceToCategoryDefault()
                }
            }
        } label: {
            PlanEditorCard(tint: selectedTint) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("公開範囲", systemImage: isPublic ? "person.2" : "lock")
                        .font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                    HStack(spacing: 6) {
                        Text(!isPublic ? "自分だけ" : snapshotEditor != nil ? "カテゴリに従う" : "友達 \(audienceFriendIDs.count)人")
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(LiminalTheme.text)
                    .frame(minHeight: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel("公開範囲")
    }

    private var timeCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                compactColumns {
                    Toggle("終日", isOn: $isAllDay).disabled(isScheduleLocked)
                    Toggle("重要", isOn: $isImportant)
                }
                .font(.subheadline)
                .tint(selectedTint)
                if snapshotEditor != nil {
                    if !isAllDay {
                        PlanTemplateTimeFields(startMinute: $templateStartMinute, endMinute: $templateEndMinute)
                    }
                } else {
                    compactColumns {
                        dateColumn(title: "開始", date: $startTime)
                        dateColumn(title: "終了", date: isAllDay ? $allDayEndDate : $endTime)
                    }
                    .disabled(isScheduleLocked)
                }
                validationStatus
            }
        }
    }

    private func dateColumn(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(LiminalTheme.secondaryText)
            DatePicker(title + "日", selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityLabel(title + "日")
            if !isAllDay {
                DatePicker(title + "時刻", selection: date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityLabel(title + "時刻")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(LiminalTheme.text)
    }

    private var noteCard: some View {
        PlanEditorCard(tint: selectedTint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(selectedTint).padding(.top, 10)
                TextField("メモを追加", text: $note, axis: .vertical)
                    .lineLimit(1...6)
                    .frame(minHeight: 44)
                    .accessibilityLabel("メモ")
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

    private var selectedTint: Color {
        selectedCategory?.displayColor ?? LiminalTheme.accent
    }

    private var canSave: Bool {
        if snapshotEditor != nil { return draftSnapshot.hasValidTime }
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
        if snapshotEditor != nil {
            guard !isAllDay else { return nil }
            if templateEndMinute <= templateStartMinute {
                return "終了時刻は開始時刻より後にしてください。"
            }
            if !draftSnapshot.hasValidTime {
                return "開始は0〜23時、予定の長さは24時間以内にしてください。"
            }
            return nil
        }
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
        if snapshotEditor != nil { return draftSnapshot.hasValidTime }
        return store.canCreatePlan(
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

    private func category(for preset: PlanPreset) -> Category? {
        guard let categoryID = preset.categoryID else { return nil }
        return categories.first { $0.id == categoryID }
    }

    private func applyPreset(
        _ preset: PlanPreset,
        usesPresetStartTime: Bool
    ) {
        showingPresetChoices = false
        let snapshot = preset.snapshot
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: startTime)

        title = snapshot.title
        selectedCategory = category(for: preset)
        note = snapshot.note ?? ""
        isAllDay = snapshot.isAllDay
        isImportant = snapshot.isImportant
        isPublic = snapshot.isPublic

        if snapshotEditor != nil {
            if snapshot.isAllDay {
                templateStartMinute = 0
                templateEndMinute = 1440
            } else {
                if usesPresetStartTime { templateStartMinute = snapshot.startMinute }
                templateEndMinute = templateStartMinute + snapshot.durationMinutes
            }
            _ = planPresetStore.markUsed(preset)
            LiminalHaptics.selection()
            return
        }

        if snapshot.isAllDay {
            startTime = targetDay
            allDayEndDate = targetDay
        } else {
            if usesPresetStartTime,
               let presetStart = wallClockDate(
                    minuteOffset: snapshot.startMinute,
                    from: targetDay,
                    calendar: calendar
               ) {
                startTime = presetStart
            }
            endTime = calendar.date(
                byAdding: .minute,
                value: snapshot.durationMinutes,
                to: startTime
            ) ?? startTime.addingTimeInterval(TimeInterval(snapshot.durationMinutes * 60))
        }

        resetAudienceToCategoryDefault()
        _ = planPresetStore.markUsed(preset)
        LiminalHaptics.selection()
    }

    private func saveAsPreset() {
        guard let snapshot = currentPresetSnapshot else {
            errorTitle = "保存できませんでした"
            saveError = "現在の時刻設定ではプリセットを作成できません。"
            return
        }
        guard planPresetStore.createPlanPreset(name: resolvedPlanTitle, snapshot: snapshot) != nil else {
            errorTitle = "保存できませんでした"
            saveError = "プリセットを保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        LiminalHaptics.commit()
    }

    private var currentPresetSnapshot: PlanTemplateSnapshot? {
        if snapshotEditor != nil { return draftSnapshot.hasValidTime ? draftSnapshot : nil }
        let calendar = Calendar.current
        let startMinute: Int
        let endMinute: Int

        if isAllDay {
            let startDay = calendar.startOfDay(for: startTime)
            let inclusiveEnd = max(calendar.startOfDay(for: allDayEndDate), startDay)
            let dayCount = (calendar.dateComponents([.day], from: startDay, to: inclusiveEnd).day ?? 0) + 1
            guard dayCount == 1 else { return nil }
            startMinute = 0
            endMinute = dayCount * 24 * 60
        } else {
            let startDay = calendar.startOfDay(for: startTime)
            let endDay = calendar.startOfDay(for: endTime)
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            let endDayOffset = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            startMinute = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            endMinute = endDayOffset * 24 * 60 + (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        }

        let snapshot = PlanTemplateSnapshot(
            title: resolvedPlanTitle,
            categoryID: selectedCategory?.id,
            startMinute: startMinute,
            endMinute: endMinute,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            isPublic: isPublic
        )
        return snapshot.hasValidTime ? snapshot : nil
    }

    private func wallClockDate(
        minuteOffset: Int,
        from dayStart: Date,
        calendar: Calendar
    ) -> Date? {
        let dayOffset = minuteOffset / (24 * 60)
        let minuteOfDay = minuteOffset % (24 * 60)
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) else {
            return nil
        }
        var components = calendar.dateComponents([.era, .year, .month, .day], from: targetDay)
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.second = 0
        return calendar.date(from: components)
    }

    private func save() {
        errorTitle = "保存できませんでした"
        if let snapshotEditor {
            guard draftSnapshot.hasValidTime else {
                saveError = timeValidationMessage ?? "時刻を確認してください。"
                return
            }
            if let error = snapshotEditor.onSave(draftSnapshot) {
                saveError = error
                LiminalHaptics.failure()
                return
            }
            LiminalHaptics.commit()
            dismiss()
            return
        }
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
        if let onDelete = snapshotEditor?.onDelete {
            onDelete()
            LiminalHaptics.commit()
            dismiss()
            return
        }
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

    private var draftSnapshot: PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: resolvedPlanTitle,
            categoryID: selectedCategory?.id,
            startMinute: isAllDay ? 0 : templateStartMinute,
            endMinute: isAllDay ? 1440 : templateEndMinute,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            isPublic: isPublic
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

        _selectedSetID = State(initialValue: nil)
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
                        ForEach(displayedCategories) { category in
                            Button {
                                LiminalHaptics.selection()
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
                .padding(16)
            }
            .background(LiminalTheme.plainSheetBackground.ignoresSafeArea())
            .navigationTitle("カテゴリを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationBackground(LiminalTheme.plainSheetBackground)
    }

    private var setSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedSetID = nil
                } label: {
                    Text("すべて")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSetID == nil ? .white : .primary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(selectedSetID == nil ? LiminalTheme.accent : Color(uiColor: .secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)

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
                                    .fill(selectedSetID == set.id ? LiminalTheme.accent : Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayedCategories: [Category] {
        guard let set = selectedSet else {
            return categories
        }
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return set.assignedIDs.compactMap { categoryByID[$0] }
    }

    private var selectedSet: CategorySet? {
        guard let selectedSetID else { return nil }
        return categorySets.first { $0.id == selectedSetID }
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

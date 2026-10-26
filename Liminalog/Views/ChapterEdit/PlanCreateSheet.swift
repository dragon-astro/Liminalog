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
    @Query(sort: \DayPreset.sortOrder) private var dayPresets: [DayPreset]
    @Query(sort: \PlanPreset.sortOrder) private var planPresets: [PlanPreset]

    private let editingPlan: PlanBlock?
    private let snapshotEditor: SnapshotEditor?

    private struct SnapshotEditor {
        let initial: PlanTemplateSnapshot
        let onSave: (PlanTemplateSnapshot) -> String?
        let onDelete: (() -> Void)?
    }

    @State private var recurrenceRule: PlanRecurrenceRule?
    @State private var reminderMinutesBefore: Int?
    @State private var reminderDate: Date?
    @State private var title = ""
    @FocusState private var isTitleFocused: Bool
    @State private var savedPresetSnapshots: [PlanTemplateSnapshot] = []
    @State private var presetFeedback: String?
    @State private var presetFeedbackID = UUID()
    @State private var showsSavedBookmark = false
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var allDayEndDate = Date()
    @State private var isMemo = false
    @State private var memoPromotion: PlanMemoPromotionRequest?
    @State private var isAllDay = false
    @State private var isImportant = false
    @State private var selectedCategory: Category?
    @State private var locationName = ""
    @State private var urlString = ""
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
    @State private var editingRecurringPreset: PlanPreset?
    @State private var editingRecurringDayPreset: DayPreset?
    @State private var editingPreset: PlanPreset?
    @State private var templateStartMinute = 0
    @State private var templateEndMinute = 60

    init(initialDate: Date = Date(), startsAsAllDay: Bool = false, startsAsMemo: Bool = false) {
        editingPlan = nil
        snapshotEditor = nil
        let calendar = Calendar.current
        let start = startsAsAllDay ? calendar.startOfDay(for: initialDate) : initialDate
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: calendar.date(byAdding: .hour, value: 1, to: start) ?? start)
        _allDayEndDate = State(initialValue: start)
        _isMemo = State(initialValue: startsAsMemo || Calendar.current.startOfDay(for: initialDate) < Calendar.current.startOfDay(for: Date()))
        _isAllDay = State(initialValue: startsAsAllDay)
        _isImportant = State(initialValue: false)
    }

    init(plan: PlanBlock) {
        editingPlan = plan
        snapshotEditor = nil
        let inclusiveEndDate = plan.isAllDay
            ? plan.endTime.addingTimeInterval(-1)
            : plan.endTime
        _reminderMinutesBefore = State(initialValue: plan.reminderMinutesBefore)
        _reminderDate = State(initialValue: plan.reminderDate)
        _title = State(initialValue: plan.title)
        _startTime = State(initialValue: plan.startTime)
        _endTime = State(initialValue: plan.endTime)
        _allDayEndDate = State(initialValue: inclusiveEndDate)
        _isMemo = State(initialValue: plan.isMemo)
        _isAllDay = State(initialValue: plan.isAllDay)
        _isImportant = State(initialValue: plan.isImportant)
        _selectedCategory = State(initialValue: plan.category)
        _locationName = State(initialValue: plan.locationName ?? "")
        _urlString = State(initialValue: plan.urlString ?? "")
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
        _reminderMinutesBefore = State(initialValue: snapshot.reminderMinutesBefore)
        _title = State(initialValue: snapshot.title)
        _templateStartMinute = State(initialValue: snapshot.startMinute)
        _templateEndMinute = State(initialValue: snapshot.endMinute)
        _isMemo = State(initialValue: snapshot.isMemo)
        _isAllDay = State(initialValue: snapshot.isAllDay)
        _isImportant = State(initialValue: snapshot.isImportant)
        _locationName = State(initialValue: snapshot.locationName ?? "")
        _urlString = State(initialValue: snapshot.urlString ?? "")
        _note = State(initialValue: snapshot.note ?? "")
        _isPublic = State(initialValue: snapshot.isPublic)
    }

    private struct Draft: Equatable {
        var title: String
        var location: String
        var url: String
        var note: String
        var categoryID: UUID?
        var start: Date
        var end: Date
        var allDayEnd: Date
        var isAllDay: Bool
        var isMemo: Bool
        var isImportant: Bool
        var isPublic: Bool
        var recurrence: PlanRecurrenceRule?
        var reminder: Int?
        var reminderDate: Date?
        var audience: Set<UUID>
        var audienceSource: AudienceSource
        var templateStart: Int
        var templateEnd: Int
    }
    private var draft: Draft {
        Draft(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
              location: PlanExtraDetails.normalized(locationName) ?? "",
              url: PlanExtraDetails.normalized(urlString) ?? "",
              note: note.trimmingCharacters(in: .whitespacesAndNewlines),
              categoryID: selectedCategory?.id,
              start: startTime,
              end: endTime,
              allDayEnd: allDayEndDate,
              isAllDay: isAllDay,
              isMemo: isMemo,
              isImportant: isImportant,
              isPublic: isPublic,
              recurrence: recurrenceRule,
              reminder: reminderMinutesBefore,
              reminderDate: reminderDate,
              audience: Set(audienceFriendIDs),
              audienceSource: audienceSource,
              templateStart: templateStartMinute,
              templateEnd: templateEndMinute)
    }

    @State private var initialDraft: Draft?
    @State private var showingDiscardConfirmation = false
    private var hasChanges: Bool { initialDraft.map { $0 != draft } ?? false }

    var body: some View {
        // Share one overlap lookup across both toolbar buttons and the warning.
        // Store writes still validate the schedule again at save time.
        let validationMessage = isScheduleLocked ? nil : timeValidationMessage
        let canPlace = snapshotEditor != nil
            ? draftSnapshot.hasValidTime
            : store.canCreatePlan(startTime: startTime, isAllDay: isAllDay, isMemo: isMemo)
        let canSave = PlanExtraDetails.isValid(location: locationName, url: urlString) && (isScheduleLocked || (validationMessage == nil && canPlace))
            && (recurrenceRule == nil || currentPresetSnapshot != nil)
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    planTitleCard(canSave: canSave)
                    timeCard(validationMessage: validationMessage, canPlace: canPlace)
                    categoryCard
                    PlanEditorCard(tint: selectedTint) {
                        PlanReminderControls(minutesBefore: $reminderMinutesBefore, absoluteDate: $reminderDate,
                            isAllDay: isAllDay, startDate: snapshotEditor == nil ? startTime : nil)
                    }
                    if snapshotEditor == nil {
                        PlanEditorCard(tint: selectedTint) {
                            if let seriesID = editingPlan?.recurrenceSeriesID {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("繰り返しから追加した予定", systemImage: "repeat")
                                    Text("ここでの変更は、この日の予定だけに適用されます。")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let master = planPresets.first(where: { $0.id == seriesID }) {
                                        Button("繰り返しの元を編集") { editingRecurringPreset = master }
                                    } else if let master = dayPresets.first(where: { $0.id == seriesID }) {
                                        Button("一日プリセットの繰り返しを編集") { editingRecurringDayPreset = master }
                                    }
                                }
                            } else {
                                PlanRecurrenceControls(rule: $recurrenceRule, initialDate: startTime)
                                if recurrenceRule != nil && currentPresetSnapshot == nil {
                                    Text("繰り返しは24時間以内の予定、または1日分の終日予定に設定できます。")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    visibilityCard
                    EditorTextRow(title: "場所", symbol: "mappin.and.ellipse", text: $locationName, tint: selectedTint)
                    EditorTextRow(title: "URL", symbol: "link", text: $urlString, tint: selectedTint, isURL: true)
                    if !PlanExtraDetails.isValid(location: locationName, url: urlString) {
                        Text("場所は100文字、URLは2,000文字以内にしてください。")
                            .font(.caption).foregroundStyle(.red)
                    }
                    noteCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .accessibilityIdentifier("plan-editor-scroll")
            .background(LiminalTheme.canvasGradient)
            .editorDateSelectionScope()
            .navigationTitle(editingPlan != nil || snapshotEditor?.onDelete != nil ? "予定を編集" : "予定を追加")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissGuard(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation)
            .toolbar {
                if isTitleFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完了") { isTitleFocused = false }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation) { dismiss() }
                }.sharedBackgroundVisibility(.hidden)
                if canChoosePreset || editingPlan != nil || snapshotEditor?.onDelete != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditorActionsMenu {
                            if canChoosePreset {
                                Button("プリセットから入れる…", systemImage: "rectangle.stack") {
                                    showingPresetChoices = true
                                }
                            }
                            if editingPlan != nil || snapshotEditor?.onDelete != nil {
                                if canChoosePreset { Divider() }
                                Button("予定を削除", systemImage: "trash", role: .destructive) {
                                    showingDeleteConfirmation = true
                                }
                                .disabled(isScheduleLocked)
                            }
                        }
                    }.sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditorSaveButton(isEmphasized: hasChanges || (editingPlan == nil && snapshotEditor?.onDelete == nil), canSave: canSave) { save() }
                }.sharedBackgroundVisibility(.hidden)
            }

            .sheet(item: $memoPromotion) { request in
                PlanMemoPromotionSheet(request: request, title: resolvedPlanTitle, start: startTime, end: endTime,
                    colorHex: selectedCategory?.colorHex, icon: selectedCategory?.icon) { mode in
                        memoPromotion = nil
                        save(approvedPromotion: request.changes, promotionMode: mode)
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
                if initialDraft == nil { initialDraft = draft }
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
                AudienceSnapshotPickerSheet(audienceFriendIDs: customAudienceFriendIDs) {
                    audienceSourceSection
                }
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
            .sheet(item: $editingRecurringPreset) { PlanPresetEditSheet(preset: $0) }
            .sheet(item: $editingRecurringDayPreset) { DayPresetEditSheet(preset: $0) }
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

    private var canChoosePreset: Bool { !planPresets.isEmpty && !isScheduleLocked }

    private func planTitleCard(canSave: Bool) -> some View {
        PlanEditorCard(tint: selectedTint, planIsMemo: isMemo) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    CategoryPreviewIcon(category: selectedCategory, size: 36)
                        .frame(height: 44)
                    TextField(planTitlePlaceholder, text: $title, axis: .vertical)
                        .font(.headline)
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1...)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .focused($isTitleFocused)
                        .disabled(isScheduleLocked)
                        .accessibilityLabel("予定名")
                    if !isTitleFocused {
                        HStack(spacing: 0) {
                            Button { saveAsPreset() } label: {
                                Image(systemName: showsSavedBookmark ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(showsSavedBookmark ? LiminalTheme.accent : LiminalTheme.secondaryText)
                                    .frame(width: 40, height: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave || currentPresetSnapshot == nil)
                            .accessibilityLabel("プリセットに保存")
                            PlanImportanceButton(isImportant: $isImportant)
                            PlanMemoButton(isMemo: $isMemo).disabled(isScheduleLocked)
                        }
                    }
                }
                if let presetFeedback {
                    Text(presetFeedback)
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .accessibilityIdentifier("plan-preset-save-feedback")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isTitleFocused)
            .foregroundStyle(selectedTint)
        }
    }

    /// カテゴリ欄。閉じている時は選択中のカテゴリを1行で示し、開くとテーブルと「その他」を出す。
    @ViewBuilder
    private var categoryCard: some View {
        if categories.isEmpty {
            categoryListCard
        } else {
            PlanEditorCard(tint: selectedTint) {
                PlanCategoryInlinePicker(
                    categories: categories,
                    categorySets: categorySets,
                    selectedCategory: $selectedCategory
                )
            }
            .disabled(isScheduleLocked)
        }
    }

    private var categoryListCard: some View {
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

    /// 見せる/見せないは1タップのスイッチ。相手は「公開相手」の行からシートで選ぶ。
    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isPublic) {
                    Label("友達に見せる", systemImage: isPublic ? "person.2" : "lock")
                }
                .font(.subheadline)

                if isPublic {
                    Divider()
                    if snapshotEditor == nil {
                        Button {
                            LiminalHaptics.openSheet()
                            showingAudiencePicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("公開相手")
                                    .foregroundStyle(LiminalTheme.text)
                                Spacer(minLength: 8)
                                Text(audienceSummaryText)
                                    .foregroundStyle(LiminalTheme.secondaryText)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(LiminalTheme.secondaryText)
                            }
                            .font(.subheadline)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("公開相手")
                        .accessibilityValue(audienceSummaryText)
                    } else {
                        HStack(spacing: 6) {
                            Text("公開相手")
                                .foregroundStyle(LiminalTheme.text)
                            Spacer(minLength: 8)
                            Text("カテゴリに従う")
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private var audienceSummaryText: String {
        let count = audienceFriendIDs.count
        return audienceSource == .categoryDefaultSnapshot
            ? "カテゴリの既定（\(count)人）"
            : "選んだ友達（\(count)人）"
    }

    /// 公開相手シートの上部。メニューにあった「公開相手を選ぶ／カテゴリ既定値に戻す」をここへ移した。
    private var audienceSourceSection: some View {
        Section {
            Picker("公開相手の決め方", selection: audienceSourceSelection) {
                Text("カテゴリの既定").tag(AudienceSource.categoryDefaultSnapshot)
                Text("自分で選ぶ").tag(AudienceSource.custom)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(
                audienceSource == .categoryDefaultSnapshot
                    ? "カテゴリ「\(selectedCategory?.name ?? "未設定")」で決めた相手に見せます。下で選び直すと「自分で選ぶ」になります。"
                    : "この予定だけ、選んだ友達に見せます。"
            )
        }
    }

    private var audienceSourceSelection: Binding<AudienceSource> {
        Binding {
            audienceSource
        } set: { source in
            LiminalHaptics.selection()
            if source == .categoryDefaultSnapshot {
                resetAudienceToCategoryDefault()
            } else {
                audienceSource = .custom
            }
        }
    }

    /// 一覧で友達を選び直したら、この予定だけの公開相手として扱う。
    private var customAudienceFriendIDs: Binding<[UUID]> {
        Binding {
            audienceFriendIDs
        } set: { ids in
            audienceFriendIDs = ids
            audienceSource = .custom
        }
    }

    private func timeCard(validationMessage: String?, canPlace: Bool) -> some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isAllDay) { Label("終日", systemImage: "calendar") }
                    .font(.subheadline).disabled(isScheduleLocked)
                if snapshotEditor != nil {
                    if !isAllDay {
                        PlanTemplateTimeFields(startMinute: $templateStartMinute, endMinute: $templateEndMinute)
                    }
                } else {
                    VStack(spacing: 12) {
                        EditorDateRow(title: "開始", date: $startTime, showsTime: !isAllDay)
                        EditorDateRow(title: "終了", date: isAllDay ? $allDayEndDate : $endTime, showsTime: !isAllDay)
                    }
                    .disabled(isScheduleLocked)
                }
                validationStatus(message: validationMessage, canPlace: canPlace)
            }
        }
    }

    private var noteCard: some View {
        EditorTextRow(title: "メモ", symbol: "note.text", text: $note, tint: selectedTint)
    }

    @ViewBuilder
    private func validationStatus(message: String?, canPlace: Bool) -> some View {
        if isScheduleLocked {
            PlanEditorStatusLabel(
                text: "今日以前の時間指定の予定は、重要表示・メモ・公開設定のみ編集できます。",
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if let message {
            PlanEditorStatusLabel(
                text: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if !canPlace {
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
        } else if !isMemo && editingPlan?.isMemo != true && store.hasTimedPlanOverlap(startTime: startTime, endTime: endTime, excluding: editingPlan?.id) {
            return "既存の予定と時間が重なっています。"
        }
        return nil
    }

    private var isScheduleLocked: Bool {
        editingPlan.map { store.isPlanScheduleLocked($0) } ?? false
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
        locationName = snapshot.locationName ?? ""
        urlString = snapshot.urlString ?? ""
        note = snapshot.note ?? ""
        isAllDay = snapshot.isAllDay
        isImportant = snapshot.isImportant
        isPublic = snapshot.isPublic
        reminderMinutesBefore = snapshot.reminderMinutesBefore
        reminderDate = nil

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
        var comparison = snapshot.editorComparison
        comparison.isMemo = false
        comparison.templateItemID = nil
        if savedPresetSnapshots.contains(comparison) {
            showPresetFeedback("保存済みです")
            return
        }
        guard planPresetStore.createPlanPreset(name: resolvedPlanTitle, snapshot: snapshot) != nil else {
            errorTitle = "保存できませんでした"
            saveError = "プリセットを保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        savedPresetSnapshots.append(comparison)
        showPresetFeedback("プリセットに保存しました")
        LiminalHaptics.commit()
    }

    private func showPresetFeedback(_ message: String) {
        let id = UUID()
        presetFeedbackID = id
        presetFeedback = message
        showsSavedBookmark = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard presetFeedbackID == id else { return }
            showsSavedBookmark = false
            try? await Task.sleep(for: .milliseconds(300))
            guard presetFeedbackID == id else { return }
            presetFeedback = nil
        }
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
            locationName: locationName, urlString: urlString,
            isPublic: isPublic,
            reminderMinutesBefore: PlanReminderTiming.templateMinutes(minutes: reminderMinutesBefore, date: reminderDate, start: startTime, isAllDay: isAllDay),
            isMemo: isMemo
        )
        return snapshot.hasValidTime && PlanExtraDetails.isValid(location: locationName, url: urlString) ? snapshot : nil
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

    private func save(approvedPromotion: [PlanMemoPromotionChange]? = nil, promotionMode: PlanMemoPromotionMode = .keepRemainders) {
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
        if let editingPlan, editingPlan.isMemo, !isMemo, !isAllDay, approvedPromotion == nil {
            guard let changes = store.memoPromotionPreview(start: startTime, end: endTime, excluding: editingPlan.id) else {
                saveError = "この時間にはメイン予定へ切り替えられません。日時を変更するか、予定メモのまま保存してください。"
                return
            }
            if !changes.isEmpty {
                memoPromotion = PlanMemoPromotionRequest(changes: changes)
                return
            }
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
        let configure: (PlanBlock) -> Bool = { plan in
            plan.reminderMinutesBefore = reminderDate == nil ? reminderMinutesBefore : nil
            plan.reminderDate = reminderDate
            if let recurrenceRule { return store.registerRecurrence(plan, rule: recurrenceRule) }
            return true
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
                isMemo: isMemo,
                isImportant: isImportant,
                note: note, locationName: locationName, urlString: urlString,
                isPublic: isPublic,
                audienceFriendIDs: audienceFriendIDs,
                audienceSource: audienceSource,
                hasAudienceSnapshot: shouldSaveAudienceSnapshot,
                approvedPromotion: approvedPromotion,
                promotionMode: promotionMode,
                beforeSave: configure
            )
        } else {
            didSave = store.createPlanBlock(
                category: selectedCategory,
                title: planTitle,
                startTime: resolvedStart,
                endTime: resolvedEnd,
                isAllDay: isAllDay,
                isMemo: isMemo,
                isImportant: isImportant,
                note: note, locationName: locationName, urlString: urlString,
                isPublic: isPublic,
                audienceFriendIDs: audienceFriendIDs,
                audienceSource: audienceSource,
                hasAudienceSnapshot: shouldSaveAudienceSnapshot,
                beforeSave: configure
            ) != nil
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
            locationName: locationName, urlString: urlString,
            isPublic: isPublic,
            reminderMinutesBefore: reminderMinutesBefore,
            templateItemID: snapshotEditor?.initial.templateItemID,
            isMemo: isMemo
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
    var planIsMemo: Bool?
    let content: Content

    init(tint: Color, planIsMemo: Bool? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.planIsMemo = planIsMemo
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LiminalTheme.surface))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint.opacity(planIsMemo == nil ? 0.1 : 0.55),
                                  style: StrokeStyle(lineWidth: 1, dash: planIsMemo == true ? [5, 4] : []))
            }
            .overlay(alignment: .leading) {
                if planIsMemo == false {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                }
            }
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

struct CategoryGridPickCell: View {
    let index: Int?
    let category: Category?
    let isSelected: Bool
    /// 予定編集のその場のテーブル用。ホームと同じ並びのまま高さを詰める。
    var compact = false

    private var circleSize: CGFloat { compact ? 30 : 42 }

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(fillColor)
                    .frame(width: circleSize, height: circleSize)

                Image(systemName: category?.icon ?? "plus")
                    .font(.system(size: compact ? 13 : 18, weight: .semibold))
                    .foregroundStyle(category?.displayColor ?? LiminalTheme.tertiaryText)
                    .frame(width: circleSize, height: circleSize)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: compact ? 12 : 15, weight: .bold))
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
        .frame(height: compact ? 58 : 86)
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

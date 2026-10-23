import SwiftData
import SwiftUI

struct PlanPresetSettingsView: View {
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: [
        SortDescriptor(\PlanPreset.sortOrder),
        SortDescriptor(\PlanPreset.createdAt)
    ]) private var presets: [PlanPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingCreateSheet = false
    @State private var isEditingPresets = false
    @State private var editingPreset: PlanPreset?
    @State private var recentPresetToRegister: PlanPreset?
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var operationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RecentPlanPresetShelf(presets: presets) { preset in
                    Button {
                        recentPresetToRegister = preset
                    } label: {
                        PlanPresetLibraryCard(preset: preset, category: category(for: preset),
                                              style: .quick, trailingSymbol: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.displayName)をプリセットに登録")
                }
                .allowsHitTesting(!isEditingPresets)
                .opacity(isEditingPresets ? 0.55 : 1)
                if presets.contains(where: { $0.recurrenceData != nil }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("繰り返しの予定", systemImage: "repeat").font(.headline)
                        ForEach(presets.filter { $0.recurrenceData != nil }) { preset in
                            Button { editingPreset = preset } label: {
                                HStack {
                                    Circle().fill(category(for: preset)?.displayColor ?? .secondary).frame(width: 8, height: 8)
                                    Text(preset.displayName)
                                    Spacer()
                                    Text(PlanRecurrenceRule.decode(preset.recurrenceData)?.summary ?? "設定を確認")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if presets.isEmpty {
                    ContentUnavailableView {
                        Label("予定プリセットはまだありません", systemImage: "bookmark")
                    } description: {
                        Text("予定作成画面のメニューから、入力中の内容をプリセットに保存できます。")
                    } actions: {
                        Button("新しく作る") {
                            showingCreateSheet = true
                        }
                    }
                } else {
                    presetSectionHeader(
                        title: "すべてのプリセット",
                        systemImage: "square.grid.3x3.fill"
                    )

                    settingsFilterControls
                        .padding(.horizontal, 16)
                        .allowsHitTesting(!isEditingPresets)
                        .opacity(isEditingPresets ? 0.5 : 1)

                    Group {
                        if displayedPresets.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                Text("一致するプリセットがありません")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        } else {
                            PlanPresetEditableGrid(
                                presets: displayedPresets,
                                isEditing: isEditingPresets,
                                categoryForPreset: category(for:),
                                onEdit: { editingPreset = $0 },
                                onDelete: deletePreset,
                                onMove: movePresets(from:to:)
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                }
            }
            .padding(.vertical, 16)
        }
        .background(LiminalTheme.plainSheetBackground.ignoresSafeArea())
        .navigationTitle("予定プリセット")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: presets.isEmpty) { _, isEmpty in
            if isEmpty { isEditingPresets = false }
        }
        .toolbar {
            if !presets.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    editToolbarButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                addToolbarButton
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            PlanPresetEditSheet(preset: nil)
        }
        .sheet(item: $recentPresetToRegister) { candidate in
            PlanPresetEditSheet(preset: nil, initialPreset: candidate)
        }
        .sheet(item: $editingPreset) { preset in
            PlanPresetEditSheet(preset: preset)
        }
        .alert("変更を保存できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func category(for preset: PlanPreset) -> Category? {
        guard let categoryID = preset.categoryID else { return nil }
        return categories.first { $0.id == categoryID }
    }

    private var displayedPresets: [PlanPreset] {
        guard !isEditingPresets else { return presets }
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.filter { preset in
            if let selectedCategoryID, preset.categoryID != selectedCategoryID {
                return false
            }
            guard !normalizedSearch.isEmpty else { return true }
            let categoryName = category(for: preset)?.name ?? ""
            return preset.displayName.localizedStandardContains(normalizedSearch)
                || categoryName.localizedStandardContains(normalizedSearch)
                || (preset.note?.localizedStandardContains(normalizedSearch) ?? false)
        }
    }

    private var filterCategories: [Category] {
        let usedIDs = Set(presets.compactMap(\.categoryID))
        return categories.filter { usedIDs.contains($0.id) }
    }

    private var settingsFilterControls: some View {
        PlanPresetFilterControls(
            searchText: $searchText,
            selectedCategoryID: $selectedCategoryID,
            categories: filterCategories,
            searchPrompt: "名前・カテゴリ・メモを検索"
        )
    }

    @ViewBuilder
    private var editToolbarButton: some View {
        Button {
            if !isEditingPresets {
                searchText = ""
                selectedCategoryID = nil
            }
            withAnimation(.snappy(duration: 0.2)) {
                isEditingPresets.toggle()
            }
            LiminalHaptics.selection()
        } label: {
            if isEditingPresets {
                Text("完了")
                    .fontWeight(.semibold)
            } else {
                Image(systemName: "pencil")
            }
        }
        .accessibilityLabel(isEditingPresets ? "編集を完了" : "予定プリセットを編集")
    }

    private var addToolbarButton: some View {
        Button {
            showingCreateSheet = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("予定プリセットを追加")
    }

    private func presetSectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(LiminalTheme.text)
            .padding(.horizontal, 16)
    }

    private func deletePreset(_ preset: PlanPreset) {
        guard presetStore.deletePlanPreset(preset) else {
            operationError = "時間をおいてもう一度試してください。"
            return
        }
        LiminalHaptics.commit()
    }

    @discardableResult
    private func movePresets(from source: IndexSet, to destination: Int) -> Bool {
        guard presetStore.movePlanPresets(from: source, to: destination) else {
            operationError = "時間をおいてもう一度試してください。"
            return false
        }
        return true
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented { operationError = nil }
        }
    }
}

private struct PlanPresetEditableGrid: View {
    let presets: [PlanPreset]
    let isEditing: Bool
    let categoryForPreset: (PlanPreset) -> Category?
    let onEdit: (PlanPreset) -> Void
    let onDelete: (PlanPreset) -> Void
    let onMove: (IndexSet, Int) -> Bool

    @State private var orderedPresetIDs: [UUID]
    @State private var dragStartPresetIDs: [UUID] = []
    @State private var draggedPresetID: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var dragLocation: CGPoint = .zero
    @State private var dragGrabOffset: CGSize = .zero

    init(
        presets: [PlanPreset],
        isEditing: Bool,
        categoryForPreset: @escaping (PlanPreset) -> Category?,
        onEdit: @escaping (PlanPreset) -> Void,
        onDelete: @escaping (PlanPreset) -> Void,
        onMove: @escaping (IndexSet, Int) -> Bool
    ) {
        self.presets = presets
        self.isEditing = isEditing
        self.categoryForPreset = categoryForPreset
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onMove = onMove
        _orderedPresetIDs = State(initialValue: presets.map(\.id))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6),
                    count: 3
                ),
                spacing: 6
            ) {
                ForEach(orderedPresets) { preset in
                    editableCard(preset)
                        .opacity(draggedPresetID == preset.id ? 0 : 1)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: PlanPresetGridFramePreferenceKey.self,
                                    value: [
                                        preset.id: proxy.frame(in: .named(Self.coordinateSpaceName))
                                    ]
                                )
                            }
                        }
                }
            }

            if let draggedPreset {
                PlanPresetLibraryCard(
                    preset: draggedPreset,
                    category: categoryForPreset(draggedPreset),
                    style: .library,
                    trailingSymbol: nil
                )
                .frame(width: cardFrames[draggedPreset.id]?.width)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                .scaleEffect(1.04)
                .position(
                    x: dragLocation.x - dragGrabOffset.width,
                    y: dragLocation.y - dragGrabOffset.height
                )
                .allowsHitTesting(false)
                .zIndex(10)
            }
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        .onPreferenceChange(PlanPresetGridFramePreferenceKey.self) { cardFrames = $0 }
        .animation(.snappy(duration: 0.18), value: orderedPresetIDs)
        .onChange(of: presets.map(\.id)) { _, presetIDs in
            guard draggedPresetID == nil else { return }
            orderedPresetIDs = presetIDs
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { cancelDrag() }
        }
    }

    @ViewBuilder
    private func editableCard(_ preset: PlanPreset) -> some View {
        let card = PlanPresetLibraryCard(
            preset: preset,
            category: categoryForPreset(preset),
            style: .library,
            trailingSymbol: nil
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

        if isEditing {
            card
                .highPriorityGesture(reorderGesture(for: preset))
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            onDelete(preset)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.red)
                    }
                    .buttonStyle(.plain)
                    .padding(3)
                    .accessibilityLabel("\(preset.displayName)を削除")
                }
        } else {
            card
                .onTapGesture { onEdit(preset) }
                .contextMenu {
                    Button {
                        onEdit(preset)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete(preset)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
                .accessibilityLabel("\(preset.displayName)を編集")
        }
    }

    private var orderedPresets: [PlanPreset] {
        let presetByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        return orderedPresetIDs.compactMap { presetByID[$0] }
    }

    private var draggedPreset: PlanPreset? {
        guard let draggedPresetID else { return nil }
        return presets.first { $0.id == draggedPresetID }
    }

    private func reorderGesture(
        for preset: PlanPreset
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 2,
            coordinateSpace: .named(Self.coordinateSpaceName)
        )
            .onChanged { drag in updateDrag(presetID: preset.id, drag: drag) }
            .onEnded { _ in finishDrag() }
    }

    private func updateDrag(presetID: UUID, drag: DragGesture.Value) {
        if draggedPresetID == nil {
            guard let frame = cardFrames[presetID] else { return }
            dragStartPresetIDs = orderedPresetIDs
            draggedPresetID = presetID
            dragGrabOffset = CGSize(
                width: drag.startLocation.x - frame.midX,
                height: drag.startLocation.y - frame.midY
            )
            LiminalHaptics.selection()
        }

        guard draggedPresetID == presetID else { return }
        dragLocation = drag.location
        movePlaceholder(toward: drag.location)
    }

    private func movePlaceholder(toward location: CGPoint) {
        guard let draggedPresetID,
              let source = orderedPresetIDs.firstIndex(of: draggedPresetID),
              let gridBounds = cardFrames.values.reduce(nil as CGRect?, { partial, frame in
                  partial?.union(frame) ?? frame
              }),
              gridBounds.insetBy(dx: -18, dy: -18).contains(location),
              let destinationID = orderedPresetIDs.compactMap({ id -> (UUID, CGFloat)? in
                  guard let frame = cardFrames[id] else { return nil }
                  let distance = hypot(location.x - frame.midX, location.y - frame.midY)
                  return (id, distance)
              }).min(by: { $0.1 < $1.1 })?.0,
              destinationID != draggedPresetID,
              let destination = orderedPresetIDs.firstIndex(of: destinationID)
        else { return }

        withAnimation(.snappy(duration: 0.18)) {
            orderedPresetIDs.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
        LiminalHaptics.selection()
    }

    private func finishDrag() {
        defer {
            draggedPresetID = nil
            dragStartPresetIDs = []
            dragLocation = .zero
            dragGrabOffset = .zero
        }

        guard let draggedPresetID,
              let source = dragStartPresetIDs.firstIndex(of: draggedPresetID),
              let destinationIndex = orderedPresetIDs.firstIndex(of: draggedPresetID),
              source != destinationIndex
        else { return }

        let destination = source < destinationIndex
            ? destinationIndex + 1
            : destinationIndex
        if onMove(IndexSet(integer: source), destination) {
            LiminalHaptics.commit()
        } else {
            orderedPresetIDs = dragStartPresetIDs
        }
    }

    private func cancelDrag() {
        if !dragStartPresetIDs.isEmpty {
            orderedPresetIDs = dragStartPresetIDs
        }
        draggedPresetID = nil
        dragStartPresetIDs = []
        dragLocation = .zero
        dragGrabOffset = .zero
    }

    private static let coordinateSpaceName = "plan-preset-edit-grid"
}

private struct PlanPresetGridFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PlanPresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]

    private let preset: PlanPreset?
    private let initialCategoryID: UUID?
    private let hasInitialContent: Bool

    @State private var recurrenceRule: PlanRecurrenceRule?
    @State private var reminderMinutesBefore: Int?
    @State private var title: String
    @State private var selectedCategory: Category?
    @State private var startTime: Date
    @State private var endMinute: Int
    @State private var durationMinutes: Int
    @State private var isMemo: Bool
    @State private var isAllDay: Bool
    @State private var isImportant: Bool
    @State private var note: String
    @State private var isPublic: Bool
    @State private var placementMode: PlanPresetPlacementMode
    @State private var showingCategoryPicker = false
    @State private var activeTimeEditor: PlanPresetTimeEditor?
    @State private var saveError: String?

    init(preset: PlanPreset?, initialPreset: PlanPreset? = nil) {
        self.preset = preset
        _recurrenceRule = State(initialValue: PlanRecurrenceRule.decode(preset?.recurrenceData))
        _reminderMinutesBefore = State(initialValue: (preset ?? initialPreset)?.reminderMinutesBefore)
        let initial = preset ?? initialPreset
        self.hasInitialContent = initial != nil
        self.initialCategoryID = initial?.categoryID
        let snapshot = initial?.snapshot ?? PlanTemplateSnapshot(
            title: "",
            categoryID: nil,
            startMinute: 9 * 60,
            endMinute: 10 * 60,
            isAllDay: false,
            isImportant: false,
            note: nil,
            isPublic: true
        )
        let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        _title = State(initialValue: initial?.displayName ?? snapshot.title)
        _selectedCategory = State(initialValue: nil)
        _startTime = State(initialValue: Self.date(minute: snapshot.startMinute, from: referenceDay))
        _endMinute = State(initialValue: snapshot.endMinute)
        _durationMinutes = State(initialValue: snapshot.durationMinutes)
        _isMemo = State(initialValue: snapshot.isMemo)
        _isAllDay = State(initialValue: snapshot.isAllDay)
        _isImportant = State(initialValue: snapshot.isImportant)
        _note = State(initialValue: snapshot.note ?? "")
        _isPublic = State(initialValue: snapshot.isPublic)
        _placementMode = State(initialValue: initial?.placementMode ?? .duration)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    identityCard
                    timeCard
                    categoryCard
                    PlanEditorCard(tint: selectedTint) {
                        PlanReminderControls(minutesBefore: $reminderMinutesBefore, isAllDay: isAllDay)
                    }
                    PlanEditorCard(tint: selectedTint) {
                        PlanRecurrenceControls(rule: $recurrenceRule)
                    }
                    visibilityCard
                    noteCard
                    if preset != nil {
                        deleteCard
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .accessibilityIdentifier("preset-editor-scroll")
            .background(LiminalTheme.canvasGradient)
            .navigationTitle(preset == nil ? "プリセットを追加" : "プリセットを編集")
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
            .onChange(of: recurrenceRule != nil) { _, enabled in
                if enabled { placementMode = .fixedTime }
            }
            .onAppear {
                if recurrenceRule != nil { placementMode = .fixedTime }
                guard selectedCategory == nil else { return }
                if let categoryID = initialCategoryID {
                    selectedCategory = categories.first { $0.id == categoryID }
                } else if !hasInitialContent {
                    selectedCategory = categories.first
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                PlanCategoryPickerSheet(
                    categorySets: categorySets,
                    categories: categories,
                    selectedCategory: $selectedCategory
                )
            }
            .sheet(item: $activeTimeEditor) { editor in
                PlanPresetWheelTimePickerSheet(
                    editor: editor,
                    initialMinute: minuteValue(for: editor),
                    onCommit: { updateMinute($0, for: editor) }
                )
            }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var presetPreviewCard: some View {
        let tint = selectedTint
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CategoryPreviewIcon(category: selectedCategory, size: 52)

                VStack(alignment: .leading, spacing: 7) {
                    Text(previewName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)

                    Text(previewSummary)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isImportant ? "star.fill" : "bookmark.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .liminalGlassFill(in: Circle())
            }

            HStack(spacing: 8) {
                PlanPreviewBadge(
                    text: isAllDay ? "終日" : placementMode.title,
                    systemImage: isAllDay
                        ? "sun.max.fill"
                        : placementMode == .fixedTime ? "clock.fill" : "timer",
                    tint: tint
                )
                PlanPreviewBadge(
                    text: isPublic ? "共有" : "非公開",
                    systemImage: isPublic ? "eye.fill" : "eye.slash.fill",
                    tint: isPublic ? LiminalTheme.accent : LiminalTheme.secondaryText
                )
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
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 1)
        }
    }

    private var identityCard: some View {
        PlanEditorCard(tint: selectedTint, planIsMemo: isMemo) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isMemo ? "予定メモ" : "メイン予定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .accessibilityIdentifier("plan-editor-kind")
                    Spacer()
                    PlanImportanceButton(isImportant: $isImportant)
                    PlanMemoButton(isMemo: $isMemo)
                }

                TextField("予定名", text: $title)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(
                        selectedTint.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
        }
    }

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
        }
    }

    private var categoryListCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(
                    title: "カテゴリ",
                    systemImage: "square.grid.2x2.fill",
                    tint: selectedTint
                )

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
                    .background(
                        selectedTint.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                PlanEditorSectionHeader(
                    title: "時間と呼び出し方",
                    systemImage: "clock.fill",
                    tint: selectedTint
                )

                Toggle(isOn: $isAllDay) {
                    Label("終日", systemImage: "sun.max.fill")
                }
                .tint(selectedTint)

                if !isAllDay {
                    Picker("呼び出し方", selection: $placementMode) {
                        ForEach(PlanPresetPlacementMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(recurrenceRule != nil)

                    VStack(spacing: 0) {
                        if placementMode == .duration {
                            timeEditorRow(
                                title: "長さ",
                                value: Self.durationText(durationMinutes),
                                systemImage: "timer"
                            ) {
                                activeTimeEditor = .duration
                            }
                        } else {
                            timeEditorRow(
                                title: "開始",
                                value: Self.timeText(computedStartMinute),
                                systemImage: "play.fill"
                            ) {
                                activeTimeEditor = .start
                            }

                            Divider()

                            timeEditorRow(
                                title: "終了",
                                value: Self.timeText(computedEndMinute),
                                systemImage: "stop.fill"
                            ) {
                                activeTimeEditor = .end
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        LiminalTheme.elevated,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                    if let timeValidationMessage {
                        PlanEditorStatusLabel(
                            text: timeValidationMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .red
                        )
                    }

                    PlanEditorStatusLabel(
                        text: placementMode == .fixedTime
                            ? "タップすると、この時刻に追加します。"
                            : "長押しして、置く時刻を決めます。",
                        systemImage: placementMode == .fixedTime ? "hand.tap.fill" : "hand.draw.fill",
                        tint: selectedTint
                    )
                }
            }
        }
    }

    private var noteCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text").foregroundStyle(selectedTint).padding(.top, 10)
                    TextField("メモを追加", text: $note, axis: .vertical)
                        .lineLimit(1...6)
                        .frame(minHeight: 44)
                        .accessibilityLabel("メモ")
                        .accessibilityIdentifier("preset-note")
                }

                if note.count > 200 {
                    PlanEditorStatusLabel(
                        text: "メモは200文字以内にしてください。",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red
                    )
                }
            }
        }
    }

    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            Toggle(isOn: $isPublic) {
                Label("友達に見せる", systemImage: isPublic ? "person.2" : "lock")
            }
            .font(.subheadline)
            .accessibilityIdentifier("preset-visibility")
        }
    }

    private var deleteCard: some View {
        PlanEditorCard(tint: .red) {
            Button(role: .destructive) {
                deletePreset()
            } label: {
                Label("プリセットを削除", systemImage: "trash.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedTint: Color {
        selectedCategory?.displayColor ?? LiminalTheme.accent
    }

    private var selectedCategorySetName: String {
        guard let selectedCategory else { return "未選択" }
        if let categorySet = categorySets.first(where: {
            $0.assignedIDs.contains(selectedCategory.id)
        }) {
            return "\(categorySet.name) セット"
        }
        return "すべてのカテゴリ"
    }

    private var previewName: String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle.isEmpty ? "新しい予定" : normalizedTitle
    }

    private var previewSummary: String {
        if isAllDay { return "終日" }
        if placementMode == .fixedTime {
            return "\(Self.timeText(computedStartMinute))–\(Self.timeText(computedEndMinute))"
        }
        return Self.durationText(durationMinutes)
    }

    private var canSave: Bool {
        guard note.count <= 200 else { return false }
        if isAllDay { return true }
        if placementMode == .duration {
            return (1...1440).contains(durationMinutes)
        }
        return computedEndMinute > computedStartMinute
            && computedEndMinute <= computedStartMinute + 1440
    }

    private var computedStartMinute: Int {
        Self.minuteOfDay(startTime)
    }

    private var computedEndMinute: Int {
        endMinute
    }

    private var timeValidationMessage: String? {
        guard !isAllDay else { return nil }
        if placementMode == .duration {
            if durationMinutes <= 0 { return "長さは1分以上にしてください。" }
            if durationMinutes > 1440 { return "長さは24時間以内にしてください。" }
            return nil
        }
        if computedEndMinute <= computedStartMinute {
            return "終了は開始より後の時刻にしてください。日をまたぐ場合は24時以降を選んでください。"
        }
        if computedEndMinute > computedStartMinute + 1440 {
            return "開始から終了までは24時間以内にしてください。"
        }
        return nil
    }

    private func timeEditorRow(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(LiminalTheme.text)
                Spacer()
                Text(value)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(selectedTint)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiminalTheme.tertiaryText)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(value)")
    }

    private func minuteValue(for editor: PlanPresetTimeEditor) -> Int {
        switch editor {
        case .start: computedStartMinute
        case .end: computedEndMinute
        case .duration: durationMinutes
        }
    }

    private func updateMinute(_ minute: Int, for editor: PlanPresetTimeEditor) {
        switch editor {
        case .start:
            let dayStart = Calendar.current.startOfDay(for: startTime)
            startTime = Self.date(minute: max(0, min(1439, minute)), from: dayStart)
        case .end:
            endMinute = max(0, min(2879, minute))
        case .duration:
            durationMinutes = max(1, min(1440, minute))
        }
    }

    private var snapshot: PlanTemplateSnapshot {
        let start: Int
        let end: Int
        if isAllDay {
            start = 0
            end = 1440
        } else if placementMode == .duration {
            start = 0
            end = durationMinutes
        } else {
            start = computedStartMinute
            end = computedEndMinute
        }

        return PlanTemplateSnapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: selectedCategory?.id,
            startMinute: start,
            endMinute: end,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            isPublic: isPublic,
            reminderMinutesBefore: reminderMinutesBefore,
            isMemo: isMemo
        )
    }

    private func save() {
        let didSave: Bool
        if let preset {
            didSave = presetStore.updatePlanPreset(
                preset,
                name: title,
                snapshot: snapshot,
                placementMode: recurrenceRule == nil ? placementMode : .fixedTime,
                recurrence: .some(recurrenceRule)
            )
        } else {
            didSave = presetStore.createPlanPreset(
                name: title,
                snapshot: snapshot,
                placementMode: recurrenceRule == nil ? placementMode : .fixedTime,
                recurrence: .some(recurrenceRule)
            ) != nil
        }
        guard didSave else {
            saveError = "時間をおいてもう一度試してください。"
            return
        }
        LiminalHaptics.commit()
        dismiss()
    }

    private func deletePreset() {
        guard let preset, presetStore.deletePlanPreset(preset) else {
            saveError = "プリセットを削除できませんでした。"
            return
        }
        LiminalHaptics.commit()
        dismiss()
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented { saveError = nil }
        }
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func timeText(_ minute: Int) -> String {
        let normalized = max(0, minute)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private static func durationText(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        if safeMinutes < 60 { return "\(safeMinutes)分" }
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }

    private static func date(minute: Int, from dayStart: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: dayStart)
            ?? dayStart.addingTimeInterval(TimeInterval(minute * 60))
    }
}

enum PlanPresetTimeEditor: String, Identifiable {
    case start
    case end
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: "開始時刻"
        case .end: "終了時刻"
        case .duration: "予定の長さ"
        }
    }

    var hourRange: Range<Int> {
        switch self {
        case .start: 0..<24
        case .end: 0..<48
        case .duration: 0..<25
        }
    }

    var hourUnit: String {
        self == .duration ? "時間" : "時"
    }

    func valueText(_ minute: Int) -> String {
        if self == .duration {
            let hours = minute / 60
            let remainder = minute % 60
            if hours == 0 { return "\(remainder)分" }
            return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
        }
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct PlanPresetWheelTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editor: PlanPresetTimeEditor
    let onCommit: (Int) -> Void

    @State private var hour: Int
    @State private var minute: Int

    init(
        editor: PlanPresetTimeEditor,
        initialMinute: Int,
        onCommit: @escaping (Int) -> Void
    ) {
        self.editor = editor
        self.onCommit = onCommit
        let maximumHour = max(editor.hourRange.lowerBound, editor.hourRange.upperBound - 1)
        _hour = State(initialValue: min(maximumHour, max(0, initialMinute / 60)))
        _minute = State(initialValue: max(0, initialMinute % 60))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(editor.valueText(selectedMinute))
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(LiminalTheme.text)

                HStack(spacing: 0) {
                    Picker(editor.hourUnit, selection: $hour) {
                        ForEach(editor.hourRange, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Text(editor.hourUnit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.secondaryText)

                    Picker("分", selection: $minute) {
                        ForEach(0..<60, id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Text("分")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .frame(height: 176)

                if editor == .duration && !isValidDuration {
                    Label("長さは1分以上24時間以内にしてください。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .background(LiminalTheme.plainSheetBackground.ignoresSafeArea())
            .navigationTitle(editor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onCommit(selectedMinute)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(editor == .duration && !isValidDuration)
                }
            }
        }
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.visible)
        .presentationBackground(LiminalTheme.plainSheetBackground)
    }

    private var selectedMinute: Int {
        hour * 60 + minute
    }

    private var isValidDuration: Bool {
        (1...1440).contains(selectedMinute)
    }
}

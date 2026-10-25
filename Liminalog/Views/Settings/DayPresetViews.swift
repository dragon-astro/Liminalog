import SwiftData
import SwiftUI

struct DayPresetSettingsView: View {
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: [
        SortDescriptor(\DayPreset.sortOrder),
        SortDescriptor(\DayPreset.createdAt)
    ]) private var presets: [DayPreset]

    @State private var operationError: String?
    @State private var editingPreset: DayPreset?
    @State private var showingCreateSheet = false
    @State private var searchText = ""
    @State private var deletionTarget: DeletionTarget?

    private struct DeletionTarget {
        let id: UUID
        let name: String
    }

    private var visiblePresets: [DayPreset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? presets : presets.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            if presets.isEmpty {
                ContentUnavailableView {
                    Label("一日プリセットはまだありません", systemImage: "calendar.badge.plus")
                } description: {
                    Text("ここで予定プリセットを組み合わせて、一日の型を作成できます。")
                } actions: {
                    Button("新しく作る") {
                        showingCreateSheet = true
                    }
                }
            } else {
                Section {
                    ForEach(visiblePresets) { preset in
                        Button {
                            editingPreset = preset
                        } label: {
                            DayPresetRow(preset: preset, decodeResult: presetStore.items(for: preset))
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .moveDisabled(!searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // destructive role は確認前に行が消えるアニメーションを起こすため付けない。
                            Button {
                                deletionTarget = DeletionTarget(id: preset.id, name: preset.name)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                    .onMove(perform: movePresets)
                }
            }
        }
        .navigationTitle("一日プリセット")
        .searchable(text: $searchText, prompt: "プリセットを検索")
        .scrollContentBackground(.hidden)
        .background(LiminalTheme.plainSheetBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !presets.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("一日プリセットを追加")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            DayPresetEditSheet(preset: nil)
        }
        .sheet(item: $editingPreset) { preset in
            DayPresetEditSheet(preset: preset)
        }
        .alert("一日プリセットを削除しますか？", isPresented: deletionPresented, presenting: deletionTarget) { target in
            Button("キャンセル", role: .cancel) { deletionTarget = nil }
            Button("削除", role: .destructive) { deletePreset(id: target.id) }
        } message: { target in
            Text("「\(target.name)」を削除します。この操作は取り消せません。適用済みの予定は残ります。")
        }
        .alert("変更を保存できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func deletePreset(id: UUID) {
        deletionTarget = nil
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        guard presetStore.deleteDayPreset(preset) else {
            operationError = "時間をおいてもう一度試してください。"
            return
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding {
            deletionTarget != nil
        } set: { isPresented in
            if !isPresented { deletionTarget = nil }
        }
    }

    private func movePresets(from source: IndexSet, to destination: Int) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard presetStore.moveDayPresets(from: source, to: destination) else {
            operationError = "時間をおいてもう一度試してください。"
            return
        }
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented { operationError = nil }
        }
    }
}

private struct DayPresetRow: View {
    let preset: DayPreset
    let decodeResult: Result<[PlanTemplateSnapshot], DayPresetItemsCodec.CodecError>
    private var tint: Color { Color(hex: preset.colorHex).liminalReadableDataColor() }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isReadable ? CategoryIconCatalog.displaySymbol(for: preset.icon) : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isReadable ? tint : Color.orange)
                .frame(width: 42, height: 42)
                .background(
                    (isReadable ? tint : Color.orange).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                if let rule = PlanRecurrenceRule.decode(preset.recurrenceData) {
                    Label(rule.summary, systemImage: "repeat").font(.caption).foregroundStyle(LiminalTheme.accent)
                }
                Text(isReadable ? "予定 \(preset.itemCount)件" : "このプリセットは開けません")
                    .font(.caption)
                    .foregroundStyle(isReadable ? LiminalTheme.secondaryText : Color.orange)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
    }

    private var isReadable: Bool {
        if case .success = decodeResult { return true }
        return false
    }
}

struct DayPresetApplySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: [
        SortDescriptor(\DayPreset.sortOrder),
        SortDescriptor(\DayPreset.createdAt)
    ]) private var presets: [DayPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var targetDate: Date
    let existingPlans: [PlanBlock]
    let allowsDateSelection: Bool
    let onAppliedToDate: (Date) -> Void
    /// 月表示のプリセット画面では、見出しの位置に「予定｜一日」の切替を置く。
    private let titleAccessory: AnyView?

    @State private var selectedPresetID: UUID?
    @State private var operationError: String?
    @State private var replacementRequest: PlanTemplateApplyRequest?

    init(targetDate: Date, existingPlans: [PlanBlock], allowsDateSelection: Bool = false,
         initialPresetID: UUID? = nil, titleAccessory: AnyView? = nil,
         onAppliedToDate: @escaping (Date) -> Void = { _ in }) {
        _targetDate = State(initialValue: targetDate)
        _selectedPresetID = State(initialValue: initialPresetID)
        self.existingPlans = existingPlans
        self.allowsDateSelection = allowsDateSelection
        self.titleAccessory = titleAccessory
        self.onAppliedToDate = onAppliedToDate
    }

    private var targetPlans: [PlanBlock] {
        guard allowsDateSelection else { return existingPlans }
        let start = Calendar.japanese.startOfDay(for: targetDate)
        let end = Calendar.japanese.date(byAdding: .day, value: 2, to: start) ?? start
        return store.plannedBlocks(from: start, to: end)
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsDateSelection {
                    Section {
                        DatePicker("追加する日", selection: $targetDate, displayedComponents: .date)
                            .accessibilityIdentifier("day-preset-target-date")
                    }
                }
                if presets.isEmpty {
                    ContentUnavailableView(
                        "一日プリセットはありません",
                        systemImage: "calendar.badge.plus",
                        description: Text("設定 ＞ カレンダー ＞ 一日プリセットで作成できます。")
                    )
                } else {
                    Section("プリセット") {
                        Picker("一日プリセット", selection: selectedPresetBinding) {
                            ForEach(presets) { preset in
                                Label(preset.name, systemImage: CategoryIconCatalog.displaySymbol(for: preset.icon))
                                    .foregroundStyle(Color(hex: preset.colorHex).liminalReadableDataColor())
                                    .tag(preset.id)
                            }
                        }
                    }

                    if let decodeError {
                        Section {
                            Label(decodeError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } else if !items.isEmpty {
                        Section {
                            ForEach(items.indices, id: \.self) { index in
                                DayPresetApplyRow(
                                    item: items[index],
                                    category: category(for: items[index]),
                                    verdict: verdicts[index],
                                    conflictingPlanNames: conflictingPlanNames(for: verdicts[index])
                                )
                            }
                        } header: {
                            SettingsSectionHeader(title: "この一日を丸ごと追加", explanation: "一日分をまとめて追加します。既存の予定と重なる場合は、置き換え方と変更内容を確認してから適用します。")
                        } footer: {
                            if !canApplyWholePreset { Text(applyFooterText) }
                        }
                    }
                }
            }
            .navigationTitle(allowsDateSelection ? "一日プリセット" : targetDate.japaneseMonthDayShortWeekday)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let titleAccessory {
                    ToolbarItem(placement: .principal) { titleAccessory }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("丸ごと追加") { apply() }
                        .fontWeight(.semibold)
                        .disabled(!canApplyWholePreset)
                }
            }
            .onAppear {
                if selectedPresetID == nil {
                    selectedPresetID = presets.first?.id
                }
            }
            .sheet(item: $replacementRequest) { request in
                PlanTemplateApplyConfirmationSheet(request: request, store: store, close: {
                    replacementRequest = nil
                })
            }
            .alert("追加できませんでした", isPresented: operationErrorPresented) {
                Button("OK", role: .cancel) { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    private var selectedPreset: DayPreset? {
        guard let selectedPresetID else { return nil }
        return presets.first { $0.id == selectedPresetID }
    }

    private var selectedPresetBinding: Binding<UUID> {
        Binding(
            get: { selectedPresetID ?? presets.first?.id ?? UUID() },
            set: { selectedPresetID = $0 }
        )
    }

    private var items: [PlanTemplateSnapshot] {
        guard let selectedPreset,
              case let .success(items) = presetStore.items(for: selectedPreset)
        else { return [] }
        return items
    }

    private var decodeError: String? {
        guard let selectedPreset else { return nil }
        switch presetStore.items(for: selectedPreset) {
        case .success:
            return nil
        case .failure(.invalidPayload):
            return "プリセットのデータを読み取れませんでした。"
        case .failure(.unsupportedVersion):
            return "新しいバージョンで作成されたプリセットの可能性があります。"
        }
    }

    private var verdicts: [DayPresetApplyPlanner.ItemVerdict] {
        DayPresetApplyPlanner.plan(
            items: items,
            targetDate: targetDate,
            existing: targetPlans.map {
                DayPresetApplyPlanner.ExistingInterval(
                    id: $0.id,
                    start: $0.startTime,
                    end: $0.endTime,
                    isAllDay: $0.isAllDay, isMemo: $0.isMemo
                )
            },
            now: Date(),
            calendar: .japanese
        )
    }

    private func category(for item: PlanTemplateSnapshot) -> Category? {
        guard let categoryID = item.categoryID else { return nil }
        return categories.first { $0.id == categoryID }
    }

    private func conflictingPlanNames(
        for verdict: DayPresetApplyPlanner.ItemVerdict
    ) -> String? {
        guard case let .conflictsWithExisting(ids) = verdict else { return nil }
        let idSet = Set(ids)
        let names = targetPlans.filter { idSet.contains($0.id) }.map(\.title)
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    private var canApplyWholePreset: Bool {
        !verdicts.isEmpty && verdicts.allSatisfy { verdict in
            if verdict == .insertable { return true }
            if case .conflictsWithExisting = verdict { return true }
            return false
        }
    }

    private var applyFooterText: String {
        if canApplyWholePreset {
            return "一日分をまとめて追加します。既存の予定と重なる場合は、置き換え方と変更内容を確認してから適用します。"
        }
        return "重なる予定などがあるため、この一日はまだ追加できません。対象日の予定を調整してからもう一度お試しください。"
    }

    private func apply() {
        guard let selectedPreset, canApplyWholePreset else { return }
        let date = Calendar.japanese.startOfDay(for: targetDate)
        let applications = items.map { item in
            PlanStore.TemplateApplication(
                snapshot: item,
                resolvedCategory: category(for: item)
            )
        }
        if verdicts.contains(where: { if case .conflictsWithExisting = $0 { return true }; return false }) {
            replacementRequest = PlanTemplateApplyRequest(applications: applications, targetDate: date,
                onApplied: {
                    _ = presetStore.markUsed(selectedPreset)
                    onAppliedToDate(date)
                    dismiss()
                })
            return
        }
        guard store.applyPlanTemplates(applications, to: date) else {
            operationError = "予定の重なりや日付が変わった可能性があります。内容を確認してもう一度お試しください。"
            return
        }
        _ = presetStore.markUsed(selectedPreset)
        LiminalHaptics.commit()
        onAppliedToDate(date)
        dismiss()
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented { operationError = nil }
        }
    }
}

private struct DayPresetApplyRow: View {
    let item: PlanTemplateSnapshot
    let category: Category?
    let verdict: DayPresetApplyPlanner.ItemVerdict
    let conflictingPlanNames: String?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: verdict == .insertable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(verdict == .insertable ? LiminalTheme.accent : statusTint)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(category?.displayColor ?? LiminalTheme.secondaryText)
                        .frame(width: 8, height: 8)
                    Text(item.title.isEmpty ? (category?.name ?? "予定") : item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                }
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LiminalTheme.secondaryText)
                if verdict != .insertable {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusTint: Color {
        verdict == .insertable ? LiminalTheme.secondaryText : .orange
    }

    private var statusText: String {
        switch verdict {
        case .insertable:
            return "まとめて追加されます"
        case .conflictsWithExisting:
            if let conflictingPlanNames {
                return "「\(conflictingPlanNames)」と重なっています"
            }
            return "既存の予定と重なっています"
        case .conflictsWithinPreset:
            return "プリセット内で時刻が重なっています"
        case .lockedDay:
            return "時間指定の予定は明日以降に追加できます"
        case .invalidTime:
            return "時刻を読み取れません"
        }
    }

    private var timeText: String {
        if item.isAllDay { return "終日" }
        return "\(Self.time(item.startMinute))–\(Self.time(item.endMinute))"
    }

    private static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

import SwiftData
import SwiftUI

struct DayPresetSettingsView: View {
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: [
        SortDescriptor(\DayPreset.sortOrder),
        SortDescriptor(\DayPreset.createdAt)
    ]) private var presets: [DayPreset]

    @State private var operationError: String?

    var body: some View {
        List {
            if presets.isEmpty {
                ContentUnavailableView {
                    Label("一日プリセットはまだありません", systemImage: "calendar.badge.plus")
                } description: {
                    Text("カレンダーの日別画面で、登録済みの予定を一日プリセットとして保存できます。")
                }
            } else {
                Section {
                    ForEach(presets) { preset in
                        DayPresetRow(preset: preset, decodeResult: presetStore.items(for: preset))
                    }
                    .onDelete(perform: deletePresets)
                    .onMove(perform: movePresets)
                } footer: {
                    Text("一日プリセットの作成と適用は、カレンダーの日別画面から行えます。")
                }
            }
        }
        .navigationTitle("一日プリセット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !presets.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .alert("変更を保存できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func deletePresets(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard presets.indices.contains(index),
                  presetStore.deleteDayPreset(presets[index])
            else {
                operationError = "時間をおいてもう一度試してください。"
                return
            }
        }
    }

    private func movePresets(from source: IndexSet, to destination: Int) {
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isReadable ? "calendar.badge.clock" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isReadable ? LiminalTheme.accent : Color.orange)
                .frame(width: 34, height: 34)
                .background(
                    (isReadable ? LiminalTheme.accent : Color.orange).opacity(0.14),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                Text(isReadable ? "予定 \(preset.itemCount)件" : "このプリセットは開けません")
                    .font(.caption)
                    .foregroundStyle(isReadable ? LiminalTheme.secondaryText : Color.orange)
            }
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

    let targetDate: Date
    let existingPlans: [PlanBlock]

    @State private var selectedPresetID: UUID?
    @State private var selectedIndices: Set<Int> = []
    @State private var operationError: String?

    var body: some View {
        NavigationStack {
            List {
                if presets.isEmpty {
                    ContentUnavailableView(
                        "一日プリセットはありません",
                        systemImage: "calendar.badge.plus",
                        description: Text("この日の予定を保存すると、別の日にまとめて呼び出せます。")
                    )
                } else {
                    Section("プリセット") {
                        Picker("一日プリセット", selection: selectedPresetBinding) {
                            ForEach(presets) { preset in
                                Text(preset.name).tag(preset.id)
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
                                    isSelected: selectedIndices.contains(index),
                                    conflictingPlanNames: conflictingPlanNames(for: verdicts[index])
                                ) {
                                    toggle(index)
                                }
                            }
                        } header: {
                            Text("追加する予定")
                        } footer: {
                            Text("重なる予定は自動で外しています。確定時にももう一度確認し、途中まで追加されることはありません。")
                        }
                    }
                }
            }
            .navigationTitle(targetDate.japaneseMonthDayShortWeekday)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(selectedIndices.count)件を追加") { apply() }
                        .fontWeight(.semibold)
                        .disabled(selectedIndices.isEmpty)
                }
            }
            .onAppear {
                if selectedPresetID == nil {
                    selectedPresetID = presets.first?.id
                }
                resetSelection()
            }
            .onChange(of: selectedPresetID) { _, _ in
                resetSelection()
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
            existing: existingPlans.map {
                DayPresetApplyPlanner.ExistingInterval(
                    id: $0.id,
                    start: $0.startTime,
                    end: $0.endTime,
                    isAllDay: $0.isAllDay
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
        let names = existingPlans.filter { idSet.contains($0.id) }.map(\.title)
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    private func toggle(_ index: Int) {
        guard verdicts.indices.contains(index), verdicts[index] == .insertable else { return }
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
        LiminalHaptics.selection()
    }

    private func resetSelection() {
        selectedIndices = Set(verdicts.indices.filter { verdicts[$0] == .insertable })
    }

    private func apply() {
        guard let selectedPreset else { return }
        let applications = selectedIndices.sorted().map { index in
            PlanStore.TemplateApplication(
                snapshot: items[index],
                resolvedCategory: category(for: items[index])
            )
        }
        guard store.applyPlanTemplates(applications, to: targetDate) else {
            operationError = "予定の重なりや日付が変わった可能性があります。内容を確認してもう一度お試しください。"
            return
        }
        _ = presetStore.markUsed(selectedPreset)
        LiminalHaptics.commit()
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
    let isSelected: Bool
    let conflictingPlanNames: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : selectionIcon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? LiminalTheme.accent : statusTint)

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
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(verdict != .insertable)
    }

    private var selectionIcon: String {
        verdict == .insertable ? "circle" : "minus.circle.fill"
    }

    private var statusTint: Color {
        verdict == .insertable ? LiminalTheme.secondaryText : .orange
    }

    private var statusText: String {
        switch verdict {
        case .insertable:
            return isSelected ? "追加" : "追加しない"
        case .conflictsWithExisting:
            if let conflictingPlanNames {
                return "「\(conflictingPlanNames)」と重なるためスキップ"
            }
            return "既存の予定と重なるためスキップ"
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
        let value = minute % 1440
        let suffix = minute >= 1440 ? " 翌日" : ""
        return String(format: "%02d:%02d%@", value / 60, value % 60, suffix)
    }
}

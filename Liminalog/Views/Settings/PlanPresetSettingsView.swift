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
    @State private var operationError: String?

    var body: some View {
        List {
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
                Section {
                    ForEach(presets) { preset in
                        NavigationLink {
                            PlanPresetEditSheet(preset: preset)
                        } label: {
                            PlanPresetRow(
                                preset: preset,
                                category: category(for: preset)
                            )
                        }
                    }
                    .onDelete(perform: deletePresets)
                    .onMove(perform: movePresets)
                } footer: {
                    Text("予定作成画面でタップすると、名前・カテゴリ・長さなどをすぐに呼び出せます。")
                }
            }
        }
        .navigationTitle("予定プリセット")
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
                .accessibilityLabel("予定プリセットを追加")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            PlanPresetEditSheet(preset: nil)
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

    private func deletePresets(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard presets.indices.contains(index),
                  presetStore.deletePlanPreset(presets[index])
            else {
                operationError = "時間をおいてもう一度試してください。"
                return
            }
        }
    }

    private func movePresets(from source: IndexSet, to destination: Int) {
        guard presetStore.movePlanPresets(from: source, to: destination) else {
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

private struct PlanPresetRow: View {
    let preset: PlanPreset
    let category: Category?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.icon ?? "bookmark.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        category?.displayColor ?? LiminalTheme.secondaryText
    }

    private var summary: String {
        let categoryName = category?.name ?? "カテゴリなし"
        if preset.isAllDay {
            return "\(categoryName) / 終日"
        }
        return "\(categoryName) / \(Self.timeText(preset.startMinute))–\(Self.timeText(preset.endMinute))"
    }

    private static func timeText(_ minute: Int) -> String {
        let normalized = minute % 1440
        let suffix = minute >= 1440 ? " 翌日" : ""
        return String(format: "%02d:%02d%@", normalized / 60, normalized % 60, suffix)
    }
}

struct PlanPresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]

    private let preset: PlanPreset?

    @State private var name: String
    @State private var title: String
    @State private var selectedCategory: Category?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var endsNextDay: Bool
    @State private var isAllDay: Bool
    @State private var isImportant: Bool
    @State private var note: String
    @State private var isPublic: Bool
    @State private var showingCategoryPicker = false
    @State private var saveError: String?

    init(preset: PlanPreset?) {
        self.preset = preset
        let snapshot = preset?.snapshot ?? PlanTemplateSnapshot(
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
        _name = State(initialValue: preset?.name ?? "")
        _title = State(initialValue: snapshot.title)
        _selectedCategory = State(initialValue: nil)
        _startTime = State(initialValue: Self.date(minute: snapshot.startMinute, from: referenceDay))
        _endTime = State(initialValue: Self.date(minute: snapshot.endMinute, from: referenceDay))
        _endsNextDay = State(initialValue: snapshot.endMinute >= 1440)
        _isAllDay = State(initialValue: snapshot.isAllDay)
        _isImportant = State(initialValue: snapshot.isImportant)
        _note = State(initialValue: snapshot.note ?? "")
        _isPublic = State(initialValue: snapshot.isPublic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("プリセット名", text: $name)
                    TextField("予定名", text: $title)
                }

                Section("カテゴリ") {
                    Button {
                        showingCategoryPicker = true
                    } label: {
                        HStack {
                            CategoryPreviewIcon(category: selectedCategory, size: 34)
                            Text(selectedCategory?.name ?? "カテゴリなし")
                                .foregroundStyle(LiminalTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LiminalTheme.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("時間") {
                    Toggle("終日", isOn: $isAllDay)
                    if !isAllDay {
                        DatePicker("開始", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $endTime, displayedComponents: .hourAndMinute)
                        Toggle("終了は翌日", isOn: $endsNextDay)
                    }
                    Toggle("重要な予定", isOn: $isImportant)
                }

                Section("メモ") {
                    TextField("メモを追加…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                    if note.count > 200 {
                        Text("メモは200文字以内にしてください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("公開") {
                    Toggle("友達に見せる", isOn: $isPublic)
                }

                if preset != nil {
                    Section {
                        Button("プリセットを削除", role: .destructive) {
                            deletePreset()
                        }
                    }
                }
            }
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
            .onAppear {
                guard selectedCategory == nil,
                      let categoryID = preset?.categoryID
                else { return }
                selectedCategory = categories.first { $0.id == categoryID }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                PlanCategoryPickerSheet(
                    categorySets: categorySets,
                    categories: categories,
                    selectedCategory: $selectedCategory
                )
            }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var canSave: Bool {
        guard note.count <= 200 else { return false }
        if isAllDay { return true }
        return computedEndMinute > computedStartMinute
            && computedEndMinute <= computedStartMinute + 1440
    }

    private var computedStartMinute: Int {
        Self.minuteOfDay(startTime)
    }

    private var computedEndMinute: Int {
        Self.minuteOfDay(endTime) + (endsNextDay ? 1440 : 0)
    }

    private var snapshot: PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: selectedCategory?.id,
            startMinute: isAllDay ? 0 : computedStartMinute,
            endMinute: isAllDay ? 1440 : computedEndMinute,
            isAllDay: isAllDay,
            isImportant: isImportant,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            isPublic: isPublic
        )
    }

    private func save() {
        let didSave: Bool
        if let preset {
            didSave = presetStore.updatePlanPreset(preset, name: name, snapshot: snapshot)
        } else {
            didSave = presetStore.createPlanPreset(name: name, snapshot: snapshot) != nil
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

    private static func date(minute: Int, from dayStart: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute, to: dayStart)
            ?? dayStart.addingTimeInterval(TimeInterval(minute * 60))
    }
}

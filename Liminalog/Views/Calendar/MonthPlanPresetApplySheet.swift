import SwiftData
import SwiftUI

/// Shares the timeline hold gesture; the month cell supplies the day, not a time.
struct MonthPlanPresetApplySheet: View {
    let targetDate: Date
    var allowsDateSelection = false
    /// 見出しの位置に置く「予定｜一日」の切替。
    var titleAccessory: AnyView? = nil
    var onAppliedToDate: (Date) -> Void = { _ in }
    @Environment(\.monthPlanTransfer) private var transfer
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var presetStore
    @State private var placementDate: Date?
    @State private var replacementRequest: PlanTemplateApplyRequest?
    @State private var error: String?
    @State private var detent: PresentationDetent = .fraction(0.65)
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PlanPreset.sortOrder), SortDescriptor(\PlanPreset.createdAt)]) private var presets: [PlanPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedPreset: PlanPreset?

    private var filteredPresets: [PlanPreset] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.filter {
            (selectedCategoryID == nil || $0.categoryID == selectedCategoryID)
                && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if transfer != nil {
                        Text("長押ししてカレンダーの日付へ置く")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 14)
                    }
                    RecentPlanPresetShelf(presets: presets) { preset in tile(preset, style: .quick) }
                    Divider()
                    PlanPresetFilterControls(searchText: $searchText, selectedCategoryID: $selectedCategoryID,
                        categories: categories.filter { category in presets.contains { $0.categoryID == category.id } }, compact: true)
                        .padding(.horizontal, 14)
                    if filteredPresets.isEmpty {
                        ContentUnavailableView(presets.isEmpty ? "予定プリセットはありません" : "該当するプリセットはありません",
                            systemImage: "bookmark", description: Text(presets.isEmpty
                                ? "最近作った予定からも追加できます。プリセットの登録はカレンダー設定から行えます。" : "検索やカテゴリを変えてください。"))
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(filteredPresets) { preset in tile(preset, style: .library) }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("予定プリセット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let titleAccessory {
                    ToolbarItem(placement: .principal) { titleAccessory }
                }
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .navigationDestination(item: $selectedPreset) { preset in
                MonthPlanPresetPlacementView(preset: preset, targetDate: placementDate ?? targetDate,
                    allowsDateSelection: allowsDateSelection && placementDate == nil,
                    category: categories.first { $0.id == preset.categoryID }, onApplied: { date in
                        onAppliedToDate(date); dismiss()
                    })
            }
        }
        .presentationDetents([.height(300), .fraction(0.65), .large], selection: $detent)
        .background(CalendarSheetRetreatBridge(isRetreated: transfer?.presetRequest != nil))
        .sheet(item: $replacementRequest) { request in
            PlanTemplateApplyConfirmationSheet(request: request, store: store, close: { replacementRequest = nil })
        }
        .alert("追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { _ = transfer?.endPreset(at: nil) }
        .presentationDragIndicator(.visible)
    }

    private func tile(_ preset: PlanPreset, style: PlanPresetLibraryCardStyle) -> some View {
        PlanPresetLibraryCard(preset: preset, category: categories.first { $0.id == preset.categoryID },
                                  style: style, trailingSymbol: preset.isAllDay || preset.placementMode == .fixedTime
                                    ? "plus.circle.fill" : "hand.draw.fill")
        .overlay {
            TimelinePlanPresetLongPressDragSurface(minimumDuration: 0.14, maximumDistance: 12,
                onTap: { placementDate = nil; selectedPreset = preset; detent = .large }) { event in
                switch event {
                case .began(let point):
                    transfer?.beginPreset(preset, tint: categories.first { $0.id == preset.categoryID }?.displayColor ?? LiminalTheme.accent, at: point)
                case .changed(let point): transfer?.updateDrag(at: point)
                case .ended(let point):
                    guard let date = transfer?.endPreset(at: point) else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(240))
                        guard !Task.isCancelled else { return }
                        if preset.isAllDay || preset.placementMode == .fixedTime { applyFixed(preset, to: date) }
                        else { placementDate = date; selectedPreset = preset; detent = .large }
                    }
                case .cancelled: _ = transfer?.endPreset(at: nil)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { placementDate = nil; selectedPreset = preset; detent = .large }
        .accessibilityLabel(preset.displayName)
        .accessibilityIdentifier("month-preset-\(preset.id)")
    }
    private func applyFixed(_ preset: PlanPreset, to date: Date) {
        let applications = [PlanStore.TemplateApplication(snapshot: preset.snapshot,
            resolvedCategory: categories.first { $0.id == preset.categoryID })]
        guard let preview = store.templateReplacementPreview(applications, to: date, mode: .keepRemainders) else {
            error = "この日には追加できません。確定済みの予定や日付を確認してください。"
            return
        }
        let finish: () -> Void = { _ = presetStore.markUsed(preset); onAppliedToDate(date); dismiss() }
        if !preview.changes.isEmpty {
            replacementRequest = PlanTemplateApplyRequest(applications: applications, targetDate: date, onApplied: finish)
        } else if store.applyPlanTemplates(applications, to: date) {
            LiminalHaptics.commit(); finish()
        } else { error = "予定が変更されたか、保存できませんでした。もう一度お試しください。" }
    }

}

private struct MonthPlanPresetPlacementView: View {
    let preset: PlanPreset
    @State private var targetDate: Date
    let allowsDateSelection: Bool
    let category: Category?
    let onApplied: (Date) -> Void
    @Environment(ChapterStore.self) private var store
    @Environment(PlanPresetStore.self) private var presetStore
    @State private var startTime: Date
    @State private var error: String?
    @State private var replacementRequest: PlanTemplateApplyRequest?

    init(preset: PlanPreset, targetDate: Date, allowsDateSelection: Bool,
         category: Category?, onApplied: @escaping (Date) -> Void) {
        self.preset = preset
        _targetDate = State(initialValue: targetDate)
        self.allowsDateSelection = allowsDateSelection
        self.category = category
        self.onApplied = onApplied
        _startTime = State(initialValue: Calendar.current.date(bySettingHour: max(0, preset.startMinute) / 60 % 24,
            minute: max(0, preset.startMinute) % 60, second: 0, of: targetDate) ?? targetDate)
    }

    private var needsStartTime: Bool { !preset.isAllDay && preset.placementMode == .duration }
    private var snapshot: PlanTemplateSnapshot? {
        guard needsStartTime else { return preset.snapshot }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return preset.snapshot.placed(at: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if allowsDateSelection {
                    DatePicker("追加する日", selection: $targetDate, displayedComponents: .date)
                        .accessibilityIdentifier("month-preset-target-date")
                } else {
                    Label(targetDate.japaneseMonthDayShortWeekday, systemImage: "calendar")
                        .font(.headline)
                }
                if let snapshot, let interval = snapshot.interval(on: targetDate) {
                    PlanReplacementPlanCard(title: snapshot.title.isEmpty ? (category?.name ?? "予定") : snapshot.title,
                        colorHex: category?.colorHex, icon: category?.icon,
                        time: snapshot.isAllDay ? "終日" : PlanReplacementPlanCard.time(interval, targetDate: targetDate))
                        .frame(minHeight: 94)
                        .accessibilityIdentifier("month-preset-placement-preview")
                }
                if needsStartTime {
                    Text("開始時刻").font(.subheadline.weight(.semibold))
                    DatePicker("開始時刻", selection: $startTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .accessibilityIdentifier("month-preset-start-time")
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.orange) }
            }
            .padding(16)
        }
        .navigationTitle(preset.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("この日に追加", action: apply)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(snapshot == nil)
                .accessibilityIdentifier("month-preset-apply")
                .padding(16)
                .background(.background)
        }
        .sheet(item: $replacementRequest) { request in
            PlanTemplateApplyConfirmationSheet(request: request, store: store, close: { replacementRequest = nil })
        }
    }

    private func finish(on date: Date) {
        _ = presetStore.markUsed(preset)
        onApplied(date)
    }

    private func apply() {
        guard let snapshot else { return }
        let date = Calendar.current.startOfDay(for: targetDate)
        let applications = [PlanStore.TemplateApplication(snapshot: snapshot, resolvedCategory: category)]
        guard let preview = store.templateReplacementPreview(applications, to: date, mode: .keepRemainders) else {
            error = "この日時には追加できません。確定済み・外部カレンダーの予定や、時刻を確認してください。"
            return
        }
        if !preview.changes.isEmpty {
            replacementRequest = PlanTemplateApplyRequest(applications: applications, targetDate: date,
                onApplied: { finish(on: date) })
            return
        }
        guard store.applyPlanTemplates(applications, to: date) else {
            error = "予定が変更されたか、保存できませんでした。もう一度お試しください。"
            return
        }
        LiminalHaptics.commit()
        finish(on: date)
    }
}

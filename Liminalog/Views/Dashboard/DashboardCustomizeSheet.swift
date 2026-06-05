import SwiftData
import SwiftUI

struct DashboardCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]

    let period: DashboardPeriod

    @State private var orderedKeys: [DashboardCardKey] = []
    @State private var hiddenKeys: Set<DashboardCardKey> = []
    @State private var saveError: String?

    private var availableKeys: [DashboardCardKey] {
        DashboardCardKey.defaultOrder(for: period)
    }

    private var visibleCount: Int {
        orderedKeys.filter { $0 == .hero || !hiddenKeys.contains($0) }.count
    }

    private var hasCustomLayout: Bool {
        orderedKeys != availableKeys || hiddenKeys.contains { availableKeys.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedKeys) { key in
                        Toggle(isOn: visibilityBinding(for: key)) {
                            Label {
                                Text(key.title)
                            } icon: {
                                Image(systemName: key.symbolName)
                                    .foregroundStyle(tint(for: key))
                            }
                        }
                        .disabled(key == .hero || (!hiddenKeys.contains(key) && visibleCount <= 1))
                        .accessibilityHint(key == .hero ? "サマリーは常に表示されます" : "")
                    }
                    .onMove(perform: moveCards)
                } footer: {
                    Text("サマリーは常に表示されます。並び順は編集モードで変更できます。")
                }
            }
            .navigationTitle("カード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完了") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(!hasCustomLayout)
                    .accessibilityLabel("初期順に戻す")
                    .accessibilityHint(hasCustomLayout ? "カードの表示と並び順を初期状態に戻します" : "現在は初期状態です")

                    EditButton()
                }
            }
            .onAppear(perform: loadDraft)
            .alert("カード設定を保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func visibilityBinding(for key: DashboardCardKey) -> Binding<Bool> {
        Binding {
            key == .hero || !hiddenKeys.contains(key)
        } set: { isVisible in
            guard key != .hero else { return }
            if isVisible {
                hiddenKeys.remove(key)
            } else {
                hiddenKeys.insert(key)
            }
            persist()
        }
    }

    private func moveCards(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty, source.allSatisfy({ orderedKeys.indices.contains($0) }) else {
            return
        }

        var nextOrder = orderedKeys
        let movingKeys = source.map { nextOrder[$0] }
        for index in source.sorted(by: >) {
            nextOrder.remove(at: index)
        }

        let adjustedDestination = destination - source.filter { $0 < destination }.count
        let insertionIndex = min(max(adjustedDestination, 0), nextOrder.count)
        nextOrder.insert(contentsOf: movingKeys, at: insertionIndex)
        guard nextOrder != orderedKeys else { return }

        orderedKeys = nextOrder
        persist()
    }

    private func reset() {
        orderedKeys = availableKeys
        hiddenKeys.subtract(availableKeys)
        persist()
    }

    private func loadDraft() {
        let settings = settings(createIfNeeded: true)
        orderedKeys = DashboardCardKey.displayOrder(from: settings.dashboardCardOrder, for: period)
        hiddenKeys = Set(settings.dashboardHiddenCardKeys.compactMap(DashboardCardKey.init(rawValue:)))
        hiddenKeys.remove(.hero)
    }

    private func persist() {
        let settings = settings(createIfNeeded: true)
        let available = Set(availableKeys)
        let storedUnavailableOrder = settings.dashboardCardOrder
            .compactMap(DashboardCardKey.init(rawValue:))
            .filter { !available.contains($0) }
        let nextOrder = orderedKeys + storedUnavailableOrder.filter { !orderedKeys.contains($0) }

        let storedUnavailableHidden = settings.dashboardHiddenCardKeys
            .compactMap(DashboardCardKey.init(rawValue:))
            .filter { !available.contains($0) }
        let nextHidden = Set(storedUnavailableHidden)
            .union(hiddenKeys.filter { available.contains($0) && $0 != .hero })

        settings.dashboardCardOrder = nextOrder.map(\.rawValue)
        settings.dashboardHiddenCardKeys = DashboardCardKey.allCases
            .filter { nextHidden.contains($0) }
            .map(\.rawValue)
        settings.updatedAt = Date()
        guard saveSettingsChange("dashboard layout") else {
            loadDraft()
            return
        }
    }

    private func settings(createIfNeeded: Bool) -> UserSettings {
        if let existing = settingsList.first {
            return existing
        }

        let created = UserSettings()
        if createIfNeeded {
            modelContext.insert(created)
        }
        return created
    }

    private func saveSettingsChange(_ action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            saveError = "時間をおいてもう一度試してください。"
            return false
        }
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

    private func tint(for key: DashboardCardKey) -> Color {
        switch key {
        case .hero, .scoreTrend, .periodDelta:
            return Color(hex: "#F2994A")
        case .metrics, .scoreBreakdown:
            return LiminalTheme.accent
        case .hourRhythm:
            return Color(hex: "#00A8A8")
        case .categoryShare:
            return Color(hex: "#6C5CE7")
        case .recentTrend:
            return Color(hex: "#EB5757")
        }
    }
}

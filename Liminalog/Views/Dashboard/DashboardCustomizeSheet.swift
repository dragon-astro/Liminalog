import SwiftData
import SwiftUI

struct DashboardCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]

    let period: DashboardPeriod

    @State private var orderedKeys: [DashboardCardKey] = []
    @State private var hiddenKeys: Set<DashboardCardKey> = []

    private var availableKeys: [DashboardCardKey] {
        DashboardCardKey.defaultOrder(for: period)
    }

    private var visibleCount: Int {
        orderedKeys.filter { $0 == .hero || !hiddenKeys.contains($0) }.count
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
                    .accessibilityLabel("初期順に戻す")

                    EditButton()
                }
            }
            .onAppear(perform: loadDraft)
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
        orderedKeys.move(fromOffsets: source, toOffset: destination)
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
        try? modelContext.save()
    }

    private func settings(createIfNeeded: Bool) -> UserSettings {
        if let existing = settingsList.first {
            return existing
        }

        let created = UserSettings()
        if createIfNeeded {
            modelContext.insert(created)
            try? modelContext.save()
        }
        return created
    }

    private func tint(for key: DashboardCardKey) -> Color {
        switch key {
        case .hero, .scoreTrend, .periodDelta:
            return Color(hex: "#F2994A")
        case .metrics, .scoreBreakdown:
            return Color.accentColor
        case .timeOfDayTrend, .hourRhythm:
            return Color(hex: "#00A8A8")
        case .categoryShare:
            return Color(hex: "#6C5CE7")
        case .recentTrend:
            return Color(hex: "#EB5757")
        }
    }
}

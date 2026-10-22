import SwiftUI
import SwiftData

/// 予定編集のカテゴリ欄。閉じている時は選択中のカテゴリだけを1行で見せ、
/// 開くとホームと同じ並びのテーブルと、テーブルにないカテゴリ（その他）をその場に出す。
struct PlanCategoryInlinePicker: View {
    private enum OtherOrder: String, CaseIterable, Identifiable {
        case usage
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .usage: "よく使う順"
            case .manual: "設定の順"
            }
        }
    }

    @Environment(ChapterStore.self) private var store
    @AppStorage("planEditor.categoryPickerExpanded") private var isExpanded = true
    @AppStorage("planEditor.otherCategoryOrder") private var otherOrderRawValue = OtherOrder.usage.rawValue
    /// ホームで今使っているテーブル。ここでは読むだけで、切り替えてもホームには反映しない。
    @AppStorage("activeCategorySetID") private var homeActiveSetIDString = ""

    let categories: [Category]
    let categorySets: [CategorySet]
    @Binding var selectedCategory: Category?

    @State private var tableID: UUID?
    @State private var scrolledTableID: UUID?
    @State private var usageCounts: [UUID: Int] = [:]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isExpanded {
                if currentTable != nil {
                    if categorySets.count > 1 {
                        tableSwitcher
                    }
                    tablePages
                    if categorySets.count > 1 { pageIndicator }
                }
                if !otherCategories.isEmpty {
                    otherSection
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("plan-category-others")
                }
            }
        }
        .onAppear {
            resolveInitialTable()
            scrolledTableID = tableID
        }
        .onChange(of: categorySets.map(\.id)) { _, ids in
            if let tableID, ids.contains(tableID) { return }
            tableID = nil
            resolveInitialTable()
            scrolledTableID = tableID
        }
        .onChange(of: scrolledTableID) { _, id in
            guard let id, id != tableID else { return }
            tableID = id
        }
        .task(id: usageLoadKey) {
            guard usageLoadKey != nil else { return }
            loadUsageCounts()
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            LiminalHaptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Label("カテゴリ", systemImage: "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.text)
                Spacer(minLength: 8)
                selectedPill
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(width: 20)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("カテゴリ")
        .accessibilityValue(selectedCategory?.name ?? "未設定")
        .accessibilityHint(isExpanded ? "選択肢を閉じる" : "選択肢を開く")
        .accessibilityIdentifier("plan-category-picker")
    }

    @ViewBuilder
    private var selectedPill: some View {
        if let category = selectedCategory {
            HStack(spacing: 5) {
                Image(systemName: category.icon ?? "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(category.displayColor)
                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Capsule().fill(category.displayColor.opacity(0.14)))
            .overlay(Capsule().stroke(category.displayColor.opacity(0.5), lineWidth: 1))
        } else {
            Text("未設定")
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.secondaryText)
        }
    }

    // MARK: - Table

    /// ホームの「平日 ⇆」と同じ見た目のメニュー。
    private var tableSwitcher: some View {
        Menu {
            ForEach(categorySets) { set in
                Button {
                    LiminalHaptics.selection()
                    tableID = set.id
                    withAnimation(.easeInOut(duration: 0.22)) { scrolledTableID = set.id }
                } label: {
                    if set.id == currentTable?.id {
                        Label(set.name, systemImage: "checkmark")
                    } else {
                        Text(set.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(currentTable?.name ?? "")
                    .lineLimit(1)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(LiminalTheme.secondaryText)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("カテゴリテーブルを切り替え")
        .accessibilityValue(currentTable?.name ?? "")
        .accessibilityIdentifier("plan-category-set-switcher")
    }

    private var tablePages: some View {
        let lookup = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(categorySets) { set in
                        tableGrid(set: set, lookup: lookup)
                            .padding(2)
                            .containerRelativeFrame(.horizontal)
                            .id(set.id)
                            .accessibilityHidden(set.id != tableID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledTableID, anchor: .center)
            .scrollIndicators(.hidden)
            .frame(height: 128)
            .accessibilityIdentifier("plan-category-board-pager")
            .onAppear {
                // A non-first page needs its laid-out offset on editor reopen.
                // Do not reassert this position during the user's swipe.
                DispatchQueue.main.async {
                    if let tableID { proxy.scrollTo(tableID, anchor: .center) }
                }
            }
        }
    }

    private func tableGrid(set: CategorySet, lookup: [UUID: Category]) -> some View {
        let slots = CategorySet.normalize(set.slots).map { $0.flatMap { lookup[$0] } }
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, category in
                if let category {
                    Button { select(category) } label: {
                        CategoryGridPickCell(index: index, category: category,
                            isSelected: category.id == selectedCategory?.id, compact: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    CategoryGridPickCell(index: index, category: nil, isSelected: false, compact: true)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(categorySets) { set in
                Circle()
                    .fill(set.id == tableID ? LiminalTheme.text : LiminalTheme.text.opacity(0.25))
                    .frame(width: set.id == tableID ? 7 : 6, height: set.id == tableID ? 7 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("カテゴリテーブル")
        .accessibilityValue("\((categorySets.firstIndex { $0.id == tableID } ?? 0) + 1)/\(categorySets.count)")
    }

    // MARK: - Others

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentTable == nil ? "カテゴリ" : "その他")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                Spacer()
                Menu {
                    Picker("並び順", selection: $otherOrderRawValue) {
                        ForEach(OtherOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    HStack(spacing: 3) {
                        Text(otherOrder.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("その他の並び順")
                .accessibilityValue(otherOrder.title)
            }

            ChipFlowLayout(spacing: 8) {
                ForEach(otherCategories) { category in
                    Button {
                        select(category)
                    } label: {
                        TimelineCategoryChip(category: category, isSelected: category.id == selectedCategory?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Data

    private var otherOrder: OtherOrder {
        OtherOrder(rawValue: otherOrderRawValue) ?? .usage
    }

    private var currentTable: CategorySet? {
        guard let tableID else { return nil }
        return categorySets.first { $0.id == tableID }
    }

    private var otherCategories: [Category] {
        let tableIDs = Set(categorySets.flatMap(\.assignedIDs))
        let others = categories.filter { !tableIDs.contains($0.id) }
        switch otherOrder {
        case .usage:
            return CategoryUsageRanking.ordered(others, counts: usageCounts)
        case .manual:
            return others.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    /// 「よく使う順」で「その他」が見えている時だけ数える。
    private struct UsageLoadKey: Equatable {
        let contentRevision: Int
        let externalRevision: Int
        let day: Date
    }

    private var usageLoadKey: UsageLoadKey? {
        guard isExpanded, otherOrder == .usage, !otherCategories.isEmpty else { return nil }
        return UsageLoadKey(contentRevision: store.contentRevision,
                            externalRevision: store.categoryUsageRevision,
                            day: Calendar.current.startOfDay(for: Date()))
    }

    private func select(_ category: Category) {
        guard category.id != selectedCategory?.id else { return }
        LiminalHaptics.selection()
        selectedCategory = category
    }

    /// 選択中のカテゴリが入っているテーブルを優先し、なければホームで使っているテーブル。
    private func resolveInitialTable() {
        guard tableID == nil else { return }
        let homeTable = UUID(uuidString: homeActiveSetIDString).flatMap { id in
            categorySets.first { $0.id == id }
        }
        if let selectedID = selectedCategory?.id {
            if let homeTable, homeTable.assignedIDs.contains(selectedID) {
                tableID = homeTable.id
                return
            }
            if let containing = categorySets.first(where: { $0.assignedIDs.contains(selectedID) }) {
                tableID = containing.id
                return
            }
        }
        tableID = homeTable?.id ?? categorySets.first?.id
    }

    private func loadUsageCounts() {
        guard let counts = store.categoryUsageCounts() else { return }
        usageCounts = counts
    }
}

import SwiftUI
import SwiftData

struct CategoryGrid: View {
    @Environment(ChapterStore.self) private var store
    @AppStorage("activeCategorySetID") private var activeSetIDString: String = ""
    @AppStorage("homeCategoryGridExpanded") private var isExpanded = true
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var selectedSetID: UUID?
    @State private var activeID: UUID? = nil
    @State private var editingSetFromEmptySlot: CategorySet? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var categoryByID: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        if categorySets.isEmpty {
            emptyState
                .onAppear { syncSelection() }
                .onChange(of: categorySets.map(\.id)) { _, _ in syncSelection() }
        } else {
            VStack(spacing: 8) {
                headerBar

                if isExpanded {
                    TabView(selection: $selectedSetID) {
                        ForEach(categorySets) { set in
                            gridPage(set: set)
                                .tag(Optional(set.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 196)

                    if categorySets.count > 1 {
                        pageIndicator
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
            .onAppear { syncSelection() }
            .onChange(of: store.activeChapter?.category?.id) { _, newID in
                activeID = newID
            }
            .onChange(of: store.revision) { _, _ in
                activeID = store.activeChapter?.category?.id
            }
            .onChange(of: categorySets.map(\.id)) { _, _ in
                syncSelection()
            }
            .onChange(of: selectedSetID) { _, newID in
                persistSelection(newID)
            }
            .sheet(item: $editingSetFromEmptySlot) { set in
                CategorySetEditSheet(categorySet: set)
            }
        }
    }

    // MARK: - Header

    /// セット名 + 折りたたみトグル。常時表示（折りたたみ時はこのバーだけ残る）。
    private var headerBar: some View {
        HStack(spacing: 6) {
            Text(currentSetName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "カテゴリグリッドを隠す" : "カテゴリグリッドを表示")
        }
        .padding(.horizontal, 2)
    }

    private var currentSetName: String {
        categorySets.first { $0.id == selectedSetID }?.name ?? categorySets.first?.name ?? ""
    }

    // MARK: - Grid page

    private func gridPage(set: CategorySet) -> some View {
        let cells = slottedCategories(for: set)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<CategorySet.slotCount, id: \.self) { index in
                if let category = cells[index] {
                    CategoryGridButton(
                        category: category,
                        isActive: activeID == category.id
                    ) {
                        store.startChapter(category: category, categorySet: set)
                        activeID = category.id
                    }
                } else {
                    Button {
                        editingSetFromEmptySlot = set
                    } label: {
                        EmptyGridSlot()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("空きスロットにカテゴリを割り当て")
                }
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(categorySets) { set in
                Circle()
                    .fill(selectedSetID == set.id ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: selectedSetID == set.id ? 7 : 6, height: selectedSetID == set.id ? 7 : 6)
                    .animation(.easeInOut(duration: 0.18), value: selectedSetID)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("カテゴリセットがありません")
                .font(.subheadline.weight(.semibold))
            Text("設定からセットを作成すると、ここに記録ボタンが並びます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                CategorySettingsView()
            } label: {
                Text("セットを作成")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Sync

    private func syncSelection() {
        activeID = store.activeChapter?.category?.id

        // 復元: AppStorageから前回の選択を読み取り、存在すれば適用
        let storedID = UUID(uuidString: activeSetIDString)
        if let storedID, categorySets.contains(where: { $0.id == storedID }) {
            selectedSetID = storedID
        } else if selectedSetID == nil || !categorySets.contains(where: { $0.id == selectedSetID }) {
            selectedSetID = categorySets.first?.id
        }
    }

    private func persistSelection(_ id: UUID?) {
        let newString = id?.uuidString ?? ""
        guard activeSetIDString != newString else { return }
        activeSetIDString = newString
        store.setEnabledCategorySetID(id)
    }

    private func slottedCategories(for set: CategorySet) -> [Category?] {
        CategorySet.normalize(set.slots).map { id in
            id.flatMap { categoryByID[$0] }
        }
    }
}

// MARK: - Empty slot placeholder

private struct EmptyGridSlot: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .strokeBorder(
                    Color(.separator).opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                )
                .frame(width: 42, height: 42)

            Text(" ")
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground).opacity(0.45))
        )
    }
}

import SwiftUI
import SwiftData

struct CategoryGrid: View {
    @Environment(ChapterStore.self) private var store
    @AppStorage("activeCategorySetID") private var activeSetIDString: String = ""
    @AppStorage("homeCategoryGridExpanded") private var isExpanded = true
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(
        filter: #Predicate<Chapter> { $0.endTime == nil },
        sort: [SortDescriptor(\.startTime, order: .reverse)]
    ) private var activeChapters: [Chapter]

    @State private var selectedSetID: UUID?
    @State private var scrolledSetID: UUID?
    @State private var activeID: UUID? = nil
    @State private var editingCategory: Category? = nil
    @State private var editingSetFromEmptySlot: CategorySet? = nil
    @State private var operationError: String?

    private let cardPadding: CGFloat = 14
    private let gridSpacing: CGFloat = 10
    private let pageInset: CGFloat = 2
    private let tableHeight: CGFloat = 170

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 4)
    }

    private var categoryByID: [UUID: Category] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        if categorySets.isEmpty {
            emptyState
                .onAppear { syncSelectionAfterLayout() }
                .onChange(of: categorySets.map(\.id)) { _, _ in syncSelection() }
        } else {
            VStack(spacing: 8) {
                headerBar

                if isExpanded {
                    categoryPages

                    if categorySets.count > 1 {
                        pageIndicator
                        sectionDivider
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isExpanded)
            .onAppear { syncSelectionAfterLayout() }
            .onChange(of: activeChapters.first?.category?.id) { _, newID in
                activeID = newID
            }
            .onChange(of: categorySets.map(\.id)) { _, _ in
                syncSelection()
            }
            .onChange(of: scrolledSetID) { _, newID in
                // スクロール追従用IDから選択IDへは一方向で反映。selectedSetID は
                // scrollPosition に束ねないので、ユーザー操作中に位置を再主張してロックしない。
                guard let newID, newID != selectedSetID else { return }
                selectedSetID = newID
            }
            .onChange(of: selectedSetID) { _, newID in
                persistSelection(newID)
            }
            .sheet(item: $editingSetFromEmptySlot) { set in
                CategorySetEditSheet(categorySet: set)
            }
            .sheet(item: $editingCategory) { category in
                CategoryEditSheet(category: category)
            }
            .alert("記録を開始できませんでした", isPresented: operationErrorPresented) {
                Button("OK", role: .cancel) {
                    operationError = nil
                }
            } message: {
                Text(operationError ?? "")
            }
        }
    }

    // MARK: - Header

    /// セット名 + 折りたたみトグル。常時表示（折りたたみ時はこのバーだけ残る）。
    private var headerBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(categorySets) { set in
                    Button {
                        selectCategorySet(set)
                    } label: {
                        if selectedSetID == set.id {
                            Label(set.name, systemImage: "checkmark")
                        } else {
                            Text(set.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(currentSetName)
                        .lineLimit(1)

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("カテゴリテーブルを切り替え")
            .accessibilityValue(currentSetName)
            .accessibilityIdentifier("category-set-switcher")

            Spacer()

            Button {
                LiminalHaptics.selection()
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(width: 44, height: 44)
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

    private var categoryPages: some View {
        // CategoryGridの状態更新でbodyが再評価されても、全ページ分のUUID辞書を一度だけ作る。
        let lookup = categoryByID
        return ScrollView(.horizontal) {
            // セット数は少数（数個）なので遅延生成は逆効果。HStack で全ページを
            // 事前生成し、スクロール中のページ生成によるヒッチを防ぐ。
            HStack(spacing: 0) {
                ForEach(categorySets) { set in
                    gridPage(set: set, categoryByID: lookup)
                        .padding(pageInset)
                        .containerRelativeFrame(.horizontal)
                        .id(set.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledSetID, anchor: .center)
        .scrollIndicators(.hidden)
        .frame(height: tableHeight)
        .liminalSectionCard(padding: cardPadding)
        .accessibilityIdentifier("category-board-pager")
    }

    private func gridPage(
        set: CategorySet,
        categoryByID: [UUID: Category]
    ) -> some View {
        let cells = slottedCategories(for: set, categoryByID: categoryByID)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<CategorySet.slotCount, id: \.self) { index in
                if let category = cells[index] {
                    CategoryGridButton(
                        category: category,
                        isActive: activeID == category.id
                    ) {
                        guard store.startChapter(category: category, categorySet: set) else {
                            LiminalHaptics.failure()
                            operationError = "時間をおいてもう一度試してください。"
                            return
                        }
                        LiminalHaptics.commit()
                        activeID = category.id
                    }
                    .contextMenu {
                        Button {
                            LiminalHaptics.openSheet()
                            editingCategory = category
                        } label: {
                            Label("カテゴリを編集", systemImage: "pencil")
                        }
                    }
                    .accessibilityHint("長押しするとカテゴリを編集できます")
                    .accessibilityAction(named: "カテゴリを編集") {
                        LiminalHaptics.openSheet()
                        editingCategory = category
                    }
                } else {
                    Button {
                        LiminalHaptics.openSheet()
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
                    .fill(selectedSetID == set.id ? LiminalTheme.text : LiminalTheme.text.opacity(0.25))
                    .frame(width: selectedSetID == set.id ? 7 : 6, height: selectedSetID == set.id ? 7 : 6)
                    .animation(.easeInOut(duration: 0.18), value: selectedSetID)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ボードページ")
        .accessibilityValue(pageIndicatorValue)
    }

    private var pageIndicatorValue: String {
        guard let selectedSetID,
              let index = categorySets.firstIndex(where: { $0.id == selectedSetID })
        else { return "" }
        return "\(index + 1)/\(categorySets.count)"
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(LiminalTheme.divider.opacity(0.55))
            .frame(height: 1)
            .padding(.horizontal, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(LiminalTheme.tertiaryText)
            Text("カテゴリセットがありません")
                .font(.subheadline.weight(.semibold))
            Text("設定からセットを作成すると、ここに記録ボタンが並びます。")
                .font(.caption)
                .foregroundStyle(LiminalTheme.secondaryText)
                .multilineTextAlignment(.center)
            NavigationLink {
                CategorySettingsView()
            } label: {
                Text("セットを作成")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(LiminalTheme.accent.opacity(0.16)))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LiminalTheme.surface)
        )
    }

    // MARK: - Sync

    private func syncSelection() {
        activeID = activeChapters.first?.category?.id

        let restoration = CategoryBoardSelectionPolicy.restore(
            storedID: UUID(uuidString: activeSetIDString),
            availableIDs: categorySets.map(\.id)
        )
        if selectedSetID != restoration.selectedID {
            selectedSetID = restoration.selectedID
        }

        let normalizedStoredID = selectedSetID?.uuidString ?? ""
        if activeSetIDString != normalizedStoredID {
            activeSetIDString = normalizedStoredID
        }
        // 復元時はスクロール位置も合わせる（ユーザー操作中は scrolledSetID を触らない）。
        if scrolledSetID != selectedSetID {
            scrolledSetID = selectedSetID
        }
        store.scheduleEnabledCategorySetSnapshot(recordingSurfaceSnapshot(for: selectedSetID))
    }

    private func syncSelectionAfterLayout() {
        syncSelection()
        DispatchQueue.main.async {
            syncSelection()
        }
    }

    private func persistSelection(_ id: UUID?) {
        let newString = id?.uuidString ?? ""
        if activeSetIDString != newString {
            activeSetIDString = newString
        }
        store.scheduleEnabledCategorySetSnapshot(recordingSurfaceSnapshot(for: id))
    }

    private func selectCategorySet(_ set: CategorySet) {
        guard selectedSetID != set.id else { return }
        LiminalHaptics.selection()
        selectedSetID = set.id
        withAnimation(.easeInOut(duration: 0.22)) {
            scrolledSetID = set.id
        }
    }

    private func slottedCategories(
        for set: CategorySet,
        categoryByID: [UUID: Category]
    ) -> [Category?] {
        CategorySet.normalize(set.slots).map { id in
            id.flatMap { categoryByID[$0] }
        }
    }

    private func recordingSurfaceSnapshot(for id: UUID?) -> RecordingSurfaceSnapshot? {
        guard let id,
              let set = categorySets.first(where: { $0.id == id })
        else { return nil }
        let lookup = categoryByID
        let cells: [RecordingSurfaceSnapshot.Cell?] = CategorySet.normalize(set.slots).map { categoryID in
            guard let categoryID, let category = lookup[categoryID] else { return nil }
            return RecordingSurfaceSnapshot.Cell(
                id: category.id,
                name: category.name,
                colorHex: category.colorHex,
                icon: category.icon
            )
        }
        return RecordingSurfaceSnapshot(
            selectedCategorySetID: set.id,
            categorySetName: set.name,
            cells: cells
        )
    }
}

// MARK: - Empty slot placeholder

private struct EmptyGridSlot: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .strokeBorder(
                    LiminalTheme.divider.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                )
                .frame(width: 42, height: 42)

            Text(" ")
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

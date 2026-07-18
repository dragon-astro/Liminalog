import SwiftUI

/// CategoryEditSheetの表側。旧30候補を軽く表示し、全カタログは明示的に＋から開く。
struct CategoryIconPicker: View {
    @Binding var selection: String
    let tint: Color

    @State private var showingLibrary = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private var readableTint: Color {
        tint.liminalReadableDataColor()
    }

    private var nonLegacySelection: CategoryIconCatalogItem? {
        guard !CategoryIconCatalog.legacySymbols.contains(selection) else { return nil }
        return CategoryIconCatalog.item(for: selection) ?? CategoryIconCatalogItem(
            symbol: selection,
            label: "選択中のアイコン",
            genre: .study
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            if let current = nonLegacySelection {
                iconButton(current, accessibilityLabel: "選択中、\(current.label)")
            }

            ForEach(CategoryIconCatalog.legacyItems) { item in
                iconButton(item, accessibilityLabel: item.label)
            }

            Button {
                showingLibrary = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LiminalTheme.elevated)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LiminalTheme.divider, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("すべてのアイコンから選ぶ")
            .accessibilityHint("検索とジャンル別のアイコンライブラリを開きます")
            .accessibilityIdentifier("category-icon-open-library")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingLibrary) {
            CategoryIconLibrarySheet(selection: $selection, tint: tint)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func iconButton(
        _ item: CategoryIconCatalogItem,
        accessibilityLabel: String
    ) -> some View {
        let selected = selection == item.symbol

        return Button {
            selection = item.symbol
            LiminalHaptics.selection()
        } label: {
            Image(systemName: CategoryIconCatalog.displaySymbol(for: item.symbol))
                .font(.headline)
                .frame(width: 40, height: 40)
                .foregroundStyle(selected ? readableTint.liminalContrastingTextColor : readableTint)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? readableTint : readableTint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selected ? "選択中" : "")
        .accessibilityIdentifier("category-icon-compact-\(item.symbol)")
    }
}

private struct CategoryIconLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    let tint: Color

    @State private var searchText = ""
    @State private var pinnedSymbols: [String] = []
    @State private var expandedGenres: Set<CategoryIconGenre> = [.study]
    @State private var didLoadPins = false
    @FocusState private var searchFieldFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 84), spacing: 8, alignment: .top),
    ]

    private var readableTint: Color {
        tint.liminalReadableDataColor()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectedIconRow
                    searchField
                    pinnedSection

                    if hasSearchQuery {
                        searchResultsSection
                    } else {
                        genreSections
                    }
                }
                .padding(16)
            }
            .background(LiminalTheme.canvas)
            .navigationTitle("すべてのアイコン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard !didLoadPins else { return }
            pinnedSymbols = CategoryIconPinStore.load()
            didLoadPins = true
        }
        .accessibilityIdentifier("category-icon-library")
    }

    private var selectedIconRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(readableTint)
                    .frame(width: 48, height: 48)

                Image(systemName: CategoryIconCatalog.displaySymbol(for: selection))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(readableTint.liminalContrastingTextColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("選択中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                Text(selectedLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
                Text(selection)
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiminalTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                togglePin(selection)
            } label: {
                Image(systemName: isPinned(selection) ? "pin.fill" : "pin")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isPinned(selection) ? LiminalTheme.accent : LiminalTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LiminalTheme.elevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned(selection) ? "よく使うから外す" : "よく使うに追加")
            .accessibilityIdentifier("category-icon-current-pin")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LiminalTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LiminalTheme.divider, lineWidth: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LiminalTheme.secondaryText)

            TextField("ラベルやシンボル名を検索", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($searchFieldFocused)
                .onSubmit { searchFieldFocused = false }
                .foregroundStyle(LiminalTheme.text)
                .accessibilityIdentifier("category-icon-search")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LiminalTheme.tertiaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索をクリア")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LiminalTheme.elevated)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LiminalTheme.divider, lineWidth: 1)
        }
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "よく使う", symbol: "pin.fill", count: pinnedSymbols.count)

            if pinnedSymbols.isEmpty {
                Text("アイコンを長押しすると、ここへ追加できます。")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(pinnedSymbols, id: \.self) { symbol in
                        iconCell(
                            symbol: symbol,
                            label: CategoryIconCatalog.item(for: symbol)?.label ?? symbol
                        )
                    }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(LiminalTheme.divider)
            sectionHeader(title: "検索結果", symbol: "magnifyingglass", count: searchResults.count)

            if searchResults.isEmpty {
                ContentUnavailableView(
                    "見つかりませんでした",
                    systemImage: "magnifyingglass",
                    description: Text("日本語のラベルまたはSF Symbol名で検索できます。")
                )
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(searchResults) { item in
                        iconCell(symbol: item.symbol, label: item.label)
                    }
                }
            }
        }
    }

    private var genreSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(CategoryIconCatalog.sections) { section in
                Divider().overlay(LiminalTheme.divider)

                DisclosureGroup(isExpanded: expandedBinding(for: section.genre)) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(section.items) { item in
                            iconCell(symbol: item.symbol, label: item.label)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    sectionHeader(
                        title: section.genre.title,
                        symbol: section.genre.symbol,
                        count: section.items.count
                    )
                }
                .tint(LiminalTheme.secondaryText)
            }
        }
    }

    private func sectionHeader(title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(LiminalTheme.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(LiminalTheme.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private func iconCell(symbol: String, label: String) -> some View {
        let selected = selection == symbol
        let pinned = isPinned(symbol)

        return Button {
            selection = symbol
            searchFieldFocused = false
            LiminalHaptics.selection()
            dismiss()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: CategoryIconCatalog.displaySymbol(for: symbol))
                        .font(.headline)
                        .foregroundStyle(selected ? readableTint.liminalContrastingTextColor : readableTint)
                        .frame(maxWidth: .infinity, minHeight: 38)

                    if pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(selected ? readableTint.liminalContrastingTextColor : LiminalTheme.accent)
                            .padding(4)
                    }
                }

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(selected ? readableTint.liminalContrastingTextColor : LiminalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? readableTint : LiminalTheme.elevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        selected ? readableTint : (pinned ? LiminalTheme.accent : LiminalTheme.divider),
                        lineWidth: selected || pinned ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                togglePin(symbol)
            } label: {
                Label(
                    pinned ? "よく使うから外す" : "よく使うに追加",
                    systemImage: pinned ? "pin.slash" : "pin"
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue(selected: selected, pinned: pinned))
        .accessibilityHint("ダブルタップで選択して編集画面へ戻ります。長押しでよく使うを変更できます。")
        .accessibilityAction(named: Text(pinned ? "よく使うから外す" : "よく使うに追加")) {
            togglePin(symbol)
        }
        .accessibilityIdentifier("category-icon-\(symbol)")
    }

    private var selectedLabel: String {
        CategoryIconCatalog.item(for: selection)?.label ?? "保存済みのアイコン"
    }

    private var hasSearchQuery: Bool {
        !CategoryIconCatalog.normalizedSearchText(searchText).isEmpty
    }

    private var searchResults: [CategoryIconCatalogItem] {
        CategoryIconCatalog.search(searchText)
    }

    private func expandedBinding(for genre: CategoryIconGenre) -> Binding<Bool> {
        Binding {
            expandedGenres.contains(genre)
        } set: { isExpanded in
            if isExpanded {
                expandedGenres.insert(genre)
            } else {
                expandedGenres.remove(genre)
            }
        }
    }

    private func isPinned(_ symbol: String) -> Bool {
        pinnedSymbols.contains(symbol)
    }

    private func togglePin(_ symbol: String) {
        pinnedSymbols = CategoryIconPinStore.toggled(symbol, in: pinnedSymbols)
        CategoryIconPinStore.save(pinnedSymbols)
        LiminalHaptics.selection()
    }

    private func accessibilityValue(selected: Bool, pinned: Bool) -> String {
        switch (selected, pinned) {
        case (true, true): "選択中、よく使う"
        case (true, false): "選択中"
        case (false, true): "よく使う"
        case (false, false): ""
        }
    }
}

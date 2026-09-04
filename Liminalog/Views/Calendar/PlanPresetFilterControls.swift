import SwiftUI

/// 設定の一覧とタイムラインのドロワーで共有する検索・カテゴリ選択。
struct PlanPresetFilterControls: View {
    @Binding var searchText: String
    @Binding var selectedCategoryID: UUID?
    let categories: [Category]
    var searchPrompt = "検索"
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LiminalTheme.secondaryText)
                TextField(searchPrompt, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .font(compact ? .caption : .subheadline)
            .padding(.horizontal, 13)
            .frame(height: compact ? 32 : 38)
            .background(Color(uiColor: .secondarySystemFill), in: Capsule())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryButton(id: nil, name: "すべて", symbol: "square.grid.2x2.fill", tint: LiminalTheme.accent)
                    ForEach(categories) { category in
                        categoryButton(
                            id: category.id,
                            name: category.name,
                            symbol: CategoryIconCatalog.displaySymbol(for: category.icon ?? "circle.fill"),
                            tint: category.displayColor
                        )
                    }
                }
                .padding(.vertical, 5)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: categories.map(\.id)) { _, ids in
            if let selectedCategoryID, !ids.contains(selectedCategoryID) {
                self.selectedCategoryID = nil
            }
        }
    }

    private func categoryButton(id: UUID?, name: String, symbol: String, tint: Color) -> some View {
        let selected = selectedCategoryID == id
        let selectedText = id == nil ? LiminalTheme.accentFilledText : tint.liminalContrastingTextColor
        return Button {
            LiminalHaptics.selection()
            selectedCategoryID = id
        } label: {
            Label(name, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? selectedText : tint.liminalReadableDataColor())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(selected ? tint : LiminalTheme.elevated, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(tint.opacity(selected ? 0 : 0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)で絞り込む")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

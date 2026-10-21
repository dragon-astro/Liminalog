import SwiftUI

/// 日間・週間・月表示からの拡大で、同じカテゴリ選択とプリセット入口を使う。
struct CalendarTimelineCategoryPalette: View {
    let categories: [Category]
    @Binding var selectedCategoryID: UUID?
    /// 左端に固定するプリセットの入口（しおり1つ）。カレンダータブの日・週は見出しに置くので出さない。
    let showsPresetEntry: Bool
    let usesCustomFilter: Bool
    let onOpenPresets: () -> Void
    let onOpenFilter: () -> Void
    let onCreateCategory: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showsPresetEntry {
                PresetEntryButton(action: onOpenPresets)
                PresetEntryDivider()
            }
            categoryScroller
        }
        .padding(.leading, showsPresetEntry ? 12 : 0)
        .padding(.top, 6)
    }

    private var categoryScroller: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if categories.isEmpty {
                    Button {
                        LiminalHaptics.openSheet()
                        onOpenFilter()
                    } label: {
                        TimelineCategoryStatusChip(
                            title: usesCustomFilter ? "表示カテゴリなし" : "カテゴリなし",
                            systemImage: usesCustomFilter ? "line.3.horizontal.decrease.circle.fill" : "square.grid.2x2",
                            accessibilityLabel: usesCustomFilter ? "表示カテゴリなし。フィルタを開く" : "カテゴリなし"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(categories) { category in
                        Button {
                            LiminalHaptics.selection()
                            selectedCategoryID = category.id
                        } label: {
                            TimelineCategoryChip(
                                category: category,
                                isSelected: category.id == selectedCategoryID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    LiminalHaptics.openSheet()
                    onCreateCategory()
                } label: {
                    TimelineCreateCategoryChip()
                }
                .buttonStyle(.plain)

            }
            .padding(.vertical, 2)
            .padding(.leading, showsPresetEntry ? 0 : 12)
            .padding(.trailing, 12)
        }
        .scrollIndicators(.hidden)
    }

}

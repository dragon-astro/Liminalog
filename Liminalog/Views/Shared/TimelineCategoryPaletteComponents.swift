import SwiftUI

struct TimelineCategoryChipStyle: Equatable {
    let tintOpacity: Double
    let strokeOpacity: Double
    let strokeWidth: Double
    let showsSelectionMark: Bool

    static func resolve(isSelected: Bool) -> TimelineCategoryChipStyle {
        TimelineCategoryChipStyle(
            tintOpacity: isSelected ? 0.2 : 0.08,
            strokeOpacity: isSelected ? 0.86 : 0.3,
            strokeWidth: isSelected ? 2 : 1,
            showsSelectionMark: isSelected
        )
    }

    func leadingSystemImage(categoryIcon: String?) -> String {
        showsSelectionMark ? "checkmark.circle.fill" : (categoryIcon ?? "circle.fill")
    }
}

struct TimelineCategoryChip: View {
    let category: Category
    let isSelected: Bool

    var body: some View {
        let style = TimelineCategoryChipStyle.resolve(isSelected: isSelected)

        HStack(spacing: 4) {
            ZStack {
                Image(systemName: category.icon ?? "circle.fill")
                    .opacity(style.showsSelectionMark ? 0 : 1)

                Image(systemName: "checkmark.circle.fill")
                    .opacity(style.showsSelectionMark ? 1 : 0)
            }
            .font(.system(size: 10, weight: .bold))
            .frame(width: 11, height: 11)
            .foregroundStyle(category.displayColor)

            Text(category.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(LiminalTheme.text)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background {
            Capsule()
                .fill(LiminalTheme.elevated)
                .overlay {
                    Capsule()
                        .fill(category.displayColor.opacity(style.tintOpacity))
                }
        }
        .overlay {
            Capsule()
                .stroke(
                    category.displayColor.opacity(style.strokeOpacity),
                    lineWidth: style.strokeWidth
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name)を選択")
        .accessibilityValue(isSelected ? "選択中" : "未選択")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TimelineCategoryStatusChip: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(LiminalTheme.secondaryText)
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background {
            Capsule()
                .fill(LiminalTheme.elevated)
        }
        .overlay {
            Capsule()
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TimelineCreateCategoryChip: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus")
                .font(.system(size: 10.5, weight: .bold))

            Text("新しいカテゴリ")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(LiminalTheme.accent)
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background {
            Capsule()
                .fill(LiminalTheme.elevated)
        }
        .overlay {
            Capsule()
                .stroke(LiminalTheme.accent.opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("新しいカテゴリを追加")
    }
}

struct TimelineCreatedCategorySelection: Equatable {
    let selectedCategoryID: UUID
    let customFilterIDs: Set<UUID>?

    static func resolve(
        createdCategoryID: UUID,
        availableCategoryIDs: Set<UUID>,
        usesCustomFilter: Bool,
        storedFilterIDs: Set<UUID>
    ) -> TimelineCreatedCategorySelection? {
        guard availableCategoryIDs.contains(createdCategoryID) else { return nil }
        return TimelineCreatedCategorySelection(
            selectedCategoryID: createdCategoryID,
            customFilterIDs: usesCustomFilter ? storedFilterIDs.union([createdCategoryID]) : nil
        )
    }
}

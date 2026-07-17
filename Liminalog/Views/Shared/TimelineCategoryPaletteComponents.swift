import SwiftUI

struct TimelineCategoryChip: View {
    let category: Category
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon ?? "circle.fill")
                .font(.system(size: 10, weight: .bold))

            Text(category.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(isSelected ? category.displayColor.liminalContrastingTextColor : category.displayColor)
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background {
            Capsule()
                .fill(LiminalTheme.elevated)
                .overlay {
                    Capsule()
                        .fill(category.displayColor.opacity(isSelected ? 1 : 0.12))
                }
        }
        .overlay {
            Capsule()
                .stroke(category.displayColor.opacity(isSelected ? 0.9 : 0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name)を選択")
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

import SwiftUI

struct CategoryGridButton: View {
    let category: Category
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(category.color.opacity(isActive ? 1.0 : 0.18))
                        .frame(width: 42, height: 42)

                    if isActive {
                        Circle()
                            .stroke(category.color, lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                    }

                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? .white : category.color)
                }

                Text(category.name)
                    .font(.caption2)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? category.color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive
                        ? category.color.opacity(0.1)
                        : Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

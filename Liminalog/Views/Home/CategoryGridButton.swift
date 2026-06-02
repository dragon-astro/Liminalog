import SwiftUI

struct CategoryGridButton: View {
    let category: Category
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(category.displayColor.opacity(isActive ? 1.0 : 0.18))
                        .frame(width: 40, height: 40)

                    if isActive {
                        Circle()
                            .stroke(category.displayColor, lineWidth: 2.5)
                            .frame(width: 46, height: 46)
                    }

                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isActive ? .white : category.displayColor)
                }

                Text(category.name)
                    .font(.caption2)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? category.displayColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(category.displayColor.opacity(isActive ? 0.18 : 0.1))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

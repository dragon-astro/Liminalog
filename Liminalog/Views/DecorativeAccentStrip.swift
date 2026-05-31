import SwiftUI

struct DecorativeAccentStrip: View {
    let color: Color
    var height: CGFloat = 14

    var body: some View {
        HStack(alignment: .bottom) {
            accentCluster
            Spacer(minLength: 0)
            accentCluster
                .scaleEffect(x: -1, y: 1)
        }
        .padding(.horizontal, max(10, height * 0.8))
        .padding(.bottom, max(2, height * 0.24))
        .frame(height: height, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var accentCluster: some View {
        let markHeight = max(1.4, height * 0.13)
        return HStack(spacing: max(3, height * 0.18)) {
            Capsule()
                .fill(color.opacity(0.16))
                .frame(width: max(12, height * 1.1), height: markHeight)
            Capsule()
                .fill(color.opacity(0.08))
                .frame(width: max(5, height * 0.42), height: markHeight)
            Circle()
                .fill(color.opacity(0.08))
                .frame(width: markHeight, height: markHeight)
        }
    }
}

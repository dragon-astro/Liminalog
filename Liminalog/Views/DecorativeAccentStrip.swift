import SwiftUI

struct DecorativeAccentStrip: View {
    let color: Color
    var height: CGFloat = 18

    private let marks: [DecorativeAccentMark] = [
        DecorativeAccentMark(id: 0, x: 0.07, y: 0.62, widthRatio: 0.1, minWidth: 18, maxWidth: 32, rotation: -18, opacity: 0.34),
        DecorativeAccentMark(id: 1, x: 0.16, y: 0.34, widthRatio: 0.05, minWidth: 10, maxWidth: 16, rotation: -18, opacity: 0.18),
        DecorativeAccentMark(id: 2, x: 0.28, y: 0.66, widthRatio: 0.14, minWidth: 28, maxWidth: 48, rotation: -18, opacity: 0.2),
        DecorativeAccentMark(id: 3, x: 0.72, y: 0.38, widthRatio: 0.06, minWidth: 12, maxWidth: 18, rotation: -18, opacity: 0.18),
        DecorativeAccentMark(id: 4, x: 0.82, y: 0.66, widthRatio: 0.13, minWidth: 26, maxWidth: 44, rotation: -18, opacity: 0.28),
        DecorativeAccentMark(id: 5, x: 0.94, y: 0.34, widthRatio: 0.08, minWidth: 14, maxWidth: 24, rotation: -18, opacity: 0.18)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(marks) { mark in
                    let markWidth = min(mark.maxWidth, max(mark.minWidth, proxy.size.width * mark.widthRatio))
                    let markHeight = max(2, height * 0.22)
                    Capsule()
                        .fill(color.opacity(mark.opacity))
                        .frame(width: markWidth, height: markHeight)
                        .rotationEffect(.degrees(mark.rotation))
                        .position(x: proxy.size.width * mark.x, y: height * mark.y)
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DecorativeAccentMark: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let widthRatio: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let rotation: Double
    let opacity: Double
}

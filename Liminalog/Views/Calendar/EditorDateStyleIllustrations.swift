import SwiftUI

/// Small, noninteractive examples make the two date-selection styles recognizable.
struct EditorDateStyleIllustrations: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            example(title: "カレンダー", caption: "日付をタップ") { calendar }
            example(title: "ホイール", caption: "上下に回す") { wheel }
        }
    }

    private func example<Content: View>(title: String, caption: String, @ViewBuilder drawing: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            drawing()
                .frame(height: 110)
                .padding(6)
                .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LiminalTheme.divider, lineWidth: 1))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            Text(caption)
                .font(.caption)
                .foregroundStyle(LiminalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var calendar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("10月").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 7, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.system(size: 8)).foregroundStyle(LiminalTheme.secondaryText)
                }
                // October 2026 starts on Thursday; both diagrams select the 15th.
                ForEach(0..<35) { cell in
                    let day = cell - 3
                    Text(day > 0 ? "\(day)" : " ")
                        .font(.system(size: 9, weight: day == 15 ? .bold : .regular, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 14)
                        .background {
                            if day == 15 {
                                Circle().fill(LiminalTheme.accent.opacity(0.2))
                                    .overlay(Circle().stroke(LiminalTheme.accent, lineWidth: 1))
                            }
                        }
                }
            }
        }
    }

    private var wheel: some View {
        VStack(spacing: 0) {
            ForEach(-2...2, id: \.self) { offset in
                HStack(spacing: 3) {
                    Text(String(2026 + offset) + "年").frame(minWidth: 42, maxWidth: .infinity)
                    Text("\(10 + offset)月").frame(maxWidth: .infinity)
                    Text("\(15 + offset)日").frame(maxWidth: .infinity)
                }
                .font(.system(size: 10, weight: offset == 0 ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 22)
                .opacity(offset == 0 ? 1 : (abs(offset) == 1 ? 0.55 : 0.22))
                .background {
                    if offset == 0 {
                        RoundedRectangle(cornerRadius: 6).fill(LiminalTheme.accent.opacity(0.16))
                    }
                }
            }
        }
    }
}

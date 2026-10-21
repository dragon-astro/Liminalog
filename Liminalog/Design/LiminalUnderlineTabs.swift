import SwiftUI

/// 表示先の切替に使う文字＋下線。保存する値の選択には使わない。
struct LiminalUnderlineTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var symbol: String? = nil
        var accessibilityLabel: String? = nil
        var accessibilityIdentifier = ""
        var isEnabled = true
        var hint = ""
        var showsIndicator = false
        var id: Value { value }
    }

    let items: [Item]
    let selection: Value
    var spacing: CGFloat = 24
    var font: Font = .subheadline
    var inactiveOpacity: Double = 0.76
    var labelSpacing: CGFloat = 4
    var underlineWidth: CGFloat? = 24
    var underlineHeight: CGFloat = 2
    var minimumWidth: CGFloat? = nil
    var minimumHeight: CGFloat? = 44
    var animation: Animation? = nil
    let onSelect: (Value) -> Void
    @Namespace private var underlineNamespace

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items) { item in
                let selected = selection == item.value
                Button {
                    withAnimation(animation) { onSelect(item.value) }
                } label: {
                    VStack(spacing: labelSpacing) {
                        ZStack(alignment: .topTrailing) {
                            HStack(spacing: 5) {
                                if let symbol = item.symbol {
                                    Image(systemName: symbol).font(.caption.weight(.semibold))
                                }
                                Text(item.title)
                                    .font(font.weight(selected ? .bold : .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? LiminalTheme.text : LiminalTheme.secondaryText.opacity(item.isEnabled ? inactiveOpacity : 0.36))
                            if item.showsIndicator {
                                Circle().fill(LiminalTheme.reward)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 8, y: -1)
                                    .accessibilityHidden(true)
                            }
                        }
                        ZStack {
                            Capsule().fill(.clear)
                                .frame(width: underlineWidth, height: underlineHeight)
                            if selected {
                                Capsule().fill(LiminalTheme.accent)
                                    .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                                    .frame(width: underlineWidth, height: underlineHeight)
                            }
                        }
                    }
                    .fixedSize()
                    .frame(minWidth: minimumWidth, minHeight: minimumHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.accessibilityLabel ?? item.title)
                .accessibilityValue(selected ? "選択中" : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(item.hint)
                .accessibilityIdentifier(item.accessibilityIdentifier)
            }
        }
    }
}

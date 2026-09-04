import SwiftUI

/// 補足は常時表示せず、必要なときだけ読める設定セクション見出し。
struct SettingsSectionHeader: View {
    let title: String
    let explanation: String
    @State private var showingExplanation = false

    var body: some View {
        Button {
            showingExplanation = true
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .regular))
                    .popover(
                        isPresented: $showingExplanation,
                        attachmentAnchor: .rect(.bounds)
                    ) {
                        explanationPopover
                            // iPhoneでもシートに変換せず、アイコンから吹き出す。
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(LiminalTheme.plainSheetBackground)
                    }
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LiminalTheme.secondaryText)
        .textCase(nil)
        .accessibilityLabel("\(title)の説明")
        .accessibilityHint("説明を表示します")
    }

    private var explanationPopover: some View {
        ViewThatFits(in: .vertical) {
            explanationContent
            ScrollView {
                explanationContent
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(idealWidth: 280, maxWidth: 320)
        .padding(16)
        .textCase(nil)
    }

    private var explanationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
    }
}

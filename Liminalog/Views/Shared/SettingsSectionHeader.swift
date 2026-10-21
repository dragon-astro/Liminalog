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
                        InformationPopoverContent(title: title, explanation: explanation)
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

}

/// Optional help uses an anchored bubble throughout the app, including compact iPhone layouts.
struct InformationButton: View {
    let title: String
    let explanation: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(LiminalTheme.secondaryText)
        .accessibilityLabel("\(title)について")
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds)) {
            InformationPopoverContent(title: title, explanation: explanation)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(LiminalTheme.plainSheetBackground)
        }
    }
}

private struct InformationPopoverContent: View {
    let title: String
    let explanation: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            explanationContent
            ScrollView { explanationContent }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(idealWidth: 280, maxWidth: 320)
        .padding(16)
        .textCase(nil)
        .accessibilityIdentifier("information-popover")
    }

    private var explanationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(explanation).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
    }
}

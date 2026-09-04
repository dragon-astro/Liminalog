import SwiftUI

/// The date-free part of the ordinary plan editor. End times can exceed 24:00.
struct PlanTemplateTimeFields: View {
    @Binding var startMinute: Int
    @Binding var endMinute: Int
    @State private var activeEditor: PlanPresetTimeEditor?

    var body: some View {
        VStack(spacing: 10) {
            row("開始", minute: startMinute, editor: .start)
            row("終了", minute: endMinute, editor: .end)
        }
        .sheet(item: $activeEditor) { editor in
            PlanPresetWheelTimePickerSheet(
                editor: editor,
                initialMinute: editor == .start ? startMinute : endMinute
            ) { value in
                if editor == .start { startMinute = value } else { endMinute = value }
            }
        }
    }

    private func row(_ title: String, minute: Int, editor: PlanPresetTimeEditor) -> some View {
        Button { activeEditor = editor } label: {
            HStack {
                Text(title)
                Spacer()
                Text(editor.valueText(minute))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .foregroundStyle(LiminalTheme.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(editor.valueText(minute))")
    }
}

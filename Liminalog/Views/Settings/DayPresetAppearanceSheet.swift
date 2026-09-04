import SwiftUI

struct DayPresetAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var color: Color
    @Binding var icon: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: CategoryIconCatalog.displaySymbol(for: icon))
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(color.liminalReadableDataColor())
                        .frame(width: 76, height: 76)
                        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                    ColorPicker("カラー", selection: $color, supportsOpacity: false)
                    CategoryIconPicker(selection: $icon, tint: color)
                }
                .padding(20)
            }
            .background(LiminalTheme.plainSheetBackground)
            .navigationTitle("色とアイコン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

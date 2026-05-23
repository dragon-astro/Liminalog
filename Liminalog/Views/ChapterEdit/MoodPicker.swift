import SwiftUI

private let moods = ["😊", "😄", "😌", "🤩", "😴", "😤", "😔", "🤔", "🔥", "💪", "☕️", "🎵"]

struct MoodPicker: View {
    @Binding var selection: String?

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(moods, id: \.self) { mood in
                Button {
                    selection = selection == mood ? nil : mood
                } label: {
                    Text(mood)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == mood
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(.tertiarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selection == mood ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Mood Picker") {
    @Previewable @State var mood: String? = "🔥"

    Form {
        MoodPicker(selection: $mood)
    }
}

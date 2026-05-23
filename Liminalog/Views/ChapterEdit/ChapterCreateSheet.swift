import SwiftUI

struct ChapterCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedCategory: Category?
    @State private var note = ""
    @State private var mood: String?
    @State private var locationName = ""
    @State private var isPublic = true
    @State private var categories: [Category] = []

    init(initialDate: Date = Date()) {
        let start = initialDate
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $selectedCategory) {
                        Text("選択").tag(Optional<Category>.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.icon ?? "circle.fill")
                                .tag(Optional(category))
                        }
                    }
                }

                Section("時間") {
                    DatePicker("開始", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("終了", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("メモ") {
                    TextField("メモを追加...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("場所") {
                    TextField("場所名を追加...", text: $locationName)
                }

                Section("気分") {
                    MoodPicker(selection: $mood)
                }

                Section("公開設定") {
                    Toggle(isOn: $isPublic) {
                        Label(isPublic ? "友達に見せる" : "自分だけ", systemImage: isPublic ? "eye" : "eye.slash")
                    }
                }
            }
            .navigationTitle("チャプターを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(selectedCategory == nil || endTime <= startTime)
                }
            }
            .onAppear {
                categories = store.allCategories()
                selectedCategory = categories.first
            }
        }
    }

    private func save() {
        guard let selectedCategory else { return }
        store.addChapter(
            category: selectedCategory,
            startTime: startTime,
            endTime: endTime,
            note: note,
            mood: mood,
            locationName: locationName,
            isPublic: isPublic
        )
        dismiss()
    }
}

#Preview("Create Chapter") {
    ChapterCreateSheet()
        .liminalogPreviewEnvironment()
}

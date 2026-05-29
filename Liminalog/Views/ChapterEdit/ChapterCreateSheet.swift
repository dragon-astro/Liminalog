import SwiftUI
import SwiftData

struct ChapterCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedCategory: Category?
    @State private var note = ""
    @State private var mood: String?
    @State private var locationName = ""
    @State private var isPublic = true

    init(initialDate: Date = Date()) {
        let now = Date()
        let dayStart = DayBoundary.dayStart(for: now)
        var start = min(max(initialDate, dayStart), now)
        var end = min(Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start, now)
        if end <= start {
            start = max(dayStart, Calendar.current.date(byAdding: .minute, value: -30, to: now) ?? dayStart)
            end = now
        }
        _startTime = State(initialValue: start)
        _endTime = State(initialValue: end)
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
                    DatePicker("開始", selection: $startTime, in: todayRange, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("終了", selection: $endTime, in: endTimeRange, displayedComponents: [.date, .hourAndMinute])

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("実績の手動追加は今日の現在時刻までの範囲で保存できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        .disabled(!canSave)
                }
            }
            .onAppear {
                selectedCategory = categories.first
                clampToToday()
            }
        }
    }

    private var todayRange: ClosedRange<Date> {
        let now = Date()
        let start = DayBoundary.dayStart(for: now)
        return start...now
    }

    private var endTimeRange: ClosedRange<Date> {
        let now = Date()
        return startTime...max(startTime, now)
    }

    private var canSave: Bool {
        guard selectedCategory != nil else { return false }
        return store.canCreateChapter(startTime: startTime, endTime: endTime)
    }

    private var validationMessage: String? {
        if selectedCategory == nil {
            return "カテゴリを選択してください。"
        }
        if startTime >= endTime {
            return "終了時刻は開始時刻より後にしてください。"
        }
        if store.hasChapterOverlap(startTime: startTime, endTime: endTime) {
            return "既存の実績と時間が重なっています。"
        }
        if !store.canCreateChapter(startTime: startTime, endTime: endTime) {
            return "実績の追加は今日の現在時刻までの範囲だけ可能です。"
        }
        return nil
    }

    private func clampToToday() {
        let now = Date()
        let dayStart = DayBoundary.dayStart(for: now)
        startTime = min(max(startTime, dayStart), now)
        endTime = min(max(endTime, startTime), now)
        if endTime <= startTime, let fallbackEnd = Calendar.current.date(byAdding: .minute, value: 1, to: startTime) {
            endTime = min(fallbackEnd, now)
        }
    }

    private func save() {
        guard let selectedCategory else { return }
        guard store.addChapter(
            category: selectedCategory,
            startTime: startTime,
            endTime: endTime,
            note: note,
            mood: mood,
            locationName: locationName,
            isPublic: isPublic
        ) else { return }
        dismiss()
    }
}

#Preview("Create Chapter") {
    ChapterCreateSheet()
        .liminalogPreviewEnvironment()
}

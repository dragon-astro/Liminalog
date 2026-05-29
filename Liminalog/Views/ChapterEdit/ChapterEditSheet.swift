import SwiftUI
import SwiftData

struct ChapterEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let chapter: Chapter

    @State private var startTime: Date = Date()
    @State private var endTime: Date? = nil
    @State private var note: String = ""
    @State private var mood: String? = nil
    @State private var locationName: String = ""
    @State private var isPublic: Bool = true
    @State private var selectedCategory: Category? = nil
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $selectedCategory) {
                        Text("なし").tag(Optional<Category>.none)
                        ForEach(categories) { cat in
                            HStack {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 10, height: 10)
                                Text(cat.name)
                            }
                            .tag(Optional(cat))
                        }
                    }
                    .labelsHidden()
                    .disabled(isTimeLocked)
                }

                Section("時間") {
                    DatePicker("開始", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .disabled(isTimeLocked)
                    if endTime != nil {
                        DatePicker("終了", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .disabled(isTimeLocked)
                    } else {
                        HStack {
                            Text("終了")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("記録中")
                                .font(.subheadline)
                                .foregroundStyle(selectedCategory?.color ?? .accentColor)
                        }
                    }

                    if isTimeLocked {
                        Label("前日以前の実績はスコア公平性のため、時間とカテゴリを変更できません。メモ・気分・場所は後から編集できます。", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
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

                Section {
                    if isTimeLocked {
                        Label("前日以前の実績は削除できません", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(chapter.isActive ? "記録中のチャプター" : "チャプターを編集")
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
            .confirmationDialog("チャプターを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    store.deleteChapter(chapter)
                    dismiss()
                }
            }
            .onAppear { loadValues() }
        }
    }

    private func loadValues() {
        startTime = chapter.startTime
        endTime = chapter.endTime
        note = chapter.note ?? ""
        mood = chapter.mood
        locationName = chapter.locationName ?? ""
        isPublic = chapter.isPublic
        selectedCategory = chapter.category
    }

    private var isTimeLocked: Bool {
        store.isChapterTimeLocked(chapter)
    }

    private var canSave: Bool {
        guard !isTimeLocked else { return true }
        let validationEnd = endTime ?? Date()
        return startTime < validationEnd
            && validationEnd <= Date()
            && !store.hasChapterOverlap(startTime: startTime, endTime: validationEnd, excluding: chapter.id)
    }

    private var validationMessage: String? {
        guard !isTimeLocked, !canSave else { return nil }
        return chapterValidationMessage
    }

    private func save() {
        guard canSave else { return }
        guard store.saveChapter(
            chapter,
            startTime: startTime,
            endTime: endTime,
            category: selectedCategory,
            note: note,
            mood: mood,
            locationName: locationName,
            isPublic: isPublic
        ) else { return }
        dismiss()
    }

    private var chapterValidationMessage: String {
        let validationEnd = endTime ?? Date()
        if startTime >= validationEnd {
            return "終了時刻は開始時刻より後にしてください。"
        }
        if validationEnd > Date() {
            return "実績の終了時刻は現在時刻以前にしてください。"
        }
        if store.hasChapterOverlap(startTime: startTime, endTime: validationEnd, excluding: chapter.id) {
            return "既存の実績と時間が重なっています。"
        }
        return "この時間では保存できません。"
    }
}

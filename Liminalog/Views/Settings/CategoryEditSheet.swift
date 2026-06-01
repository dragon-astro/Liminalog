import SwiftUI

struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let category: Category?

    @State private var name: String = ""
    @State private var color: Color = .blue
    @State private var icon: String = "circle.fill"
    @State private var dailyCardIntent: DailyCardCategoryIntent = .neutral
    @State private var isDailyCardSleepCategory = false

    private let icons = ["book.closed.fill", "briefcase.fill", "sparkles", "cup.and.saucer.fill", "tram.fill", "moon.fill", "fork.knife", "figure.run", "gamecontroller.fill", "music.note", "heart.fill", "paintpalette.fill"]

    var isNew: Bool { category == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("カテゴリ名") {
                    TextField("例: 勉強", text: $name)
                }

                Section("カラー") {
                    ColorPicker("カテゴリカラー", selection: $color, supportsOpacity: false)
                }

                Section("アイコン") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.headline)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(icon == symbol ? .white : color)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(icon == symbol ? color : color.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("デイリーカード") {
                    Picker("傾向", selection: $dailyCardIntent) {
                        ForEach(DailyCardCategoryIntent.allCases) { intent in
                            Text(intent.title).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("睡眠として扱う", isOn: $isDailyCardSleepCategory)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Circle()
                                .fill(color)
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: icon)
                                        .foregroundStyle(.white)
                                }
                            Text(name.isEmpty ? "カテゴリ名" : name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("プレビュー")
                }
            }
            .navigationTitle(isNew ? "カテゴリを追加" : "カテゴリを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let cat = category {
                    name = cat.name
                    color = cat.color
                    icon = cat.icon ?? "circle.fill"
                    dailyCardIntent = cat.dailyCardIntent
                    isDailyCardSleepCategory = cat.isDailyCardSleepCategory
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let cat = category {
            store.updateCategory(
                cat,
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                isDailyCardSleepCategory: isDailyCardSleepCategory
            )
        } else {
            store.addCategory(
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                isDailyCardSleepCategory: isDailyCardSleepCategory
            )
        }
        dismiss()
    }
}

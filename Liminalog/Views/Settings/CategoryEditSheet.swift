import SwiftUI
import SwiftData

struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let category: Category?

    @State private var name: String = ""
    @State private var color: Color = .blue
    @State private var icon: String = "circle.fill"
    @State private var dailyCardIntent: DailyCardCategoryIntent = .neutral
    @State private var isDailyCardSleepCategory = false
    @State private var defaultAudienceFriendSetIDs: [UUID] = []
    @State private var defaultAudienceIncludedFriendIDs: [UUID] = []
    @State private var defaultAudienceExcludedFriendIDs: [UUID] = []
    @State private var showingAudiencePicker = false
    @State private var saveError: String?
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

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
                    Button {
                        showingAudiencePicker = true
                    } label: {
                        AudienceSummaryRow(
                            title: "新規チャプター/予定の公開相手",
                            count: resolvedAudienceCount,
                            systemImage: "person.2.fill",
                            tint: color
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("デフォルト公開相手")
                } footer: {
                    Text("通常は新しく作るものにだけコピーされます。必要な時だけ、公開相手の編集画面から過去の予定にも反映できます。")
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
                            Text(trimmedName.isEmpty ? "カテゴリ名" : trimmedName)
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.secondaryText)
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
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if let cat = category {
                    name = cat.name
                    color = cat.color
                    icon = cat.icon ?? "circle.fill"
                    dailyCardIntent = cat.dailyCardIntent
                    isDailyCardSleepCategory = cat.isDailyCardSleepCategory
                    defaultAudienceFriendSetIDs = cat.defaultAudienceFriendSetIDs
                    defaultAudienceIncludedFriendIDs = cat.defaultAudienceIncludedFriendIDs
                    defaultAudienceExcludedFriendIDs = cat.defaultAudienceExcludedFriendIDs
                }
            }
            .sheet(isPresented: $showingAudiencePicker) {
                CategoryAudiencePickerSheet(
                    category: category,
                    friendSetIDs: $defaultAudienceFriendSetIDs,
                    includedFriendIDs: $defaultAudienceIncludedFriendIDs,
                    excludedFriendIDs: $defaultAudienceExcludedFriendIDs
                )
            }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK") {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var resolvedAudienceCount: Int {
        AudienceResolver.resolve(
            friendSetIDs: defaultAudienceFriendSetIDs,
            includedFriendIDs: defaultAudienceIncludedFriendIDs,
            excludedFriendIDs: defaultAudienceExcludedFriendIDs,
            friendSets: friendSets,
            friends: friends
        ).count
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented {
                saveError = nil
            }
        }
    }

    private func save() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }

        let didSave: Bool
        if let cat = category {
            didSave = store.updateCategory(
                cat,
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                isDailyCardSleepCategory: isDailyCardSleepCategory,
                defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
                defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
                defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
            )
        } else {
            didSave = store.addCategory(
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                isDailyCardSleepCategory: isDailyCardSleepCategory,
                defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
                defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
                defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
            )
        }
        guard didSave else {
            saveError = "カテゴリの変更を保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        dismiss()
    }
}

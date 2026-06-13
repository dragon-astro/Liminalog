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
    @State private var showingCustomColorPicker = false
    @State private var customColorDraft: Color = .blue
    @State private var saveError: String?
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

    private let icons = [
        "book.closed.fill",
        "graduationcap.fill",
        "pencil.and.outline",
        "briefcase.fill",
        "laptopcomputer",
        "doc.text.fill",
        "tram.fill",
        "car.fill",
        "airplane",
        "figure.walk",
        "figure.run",
        "bicycle",
        "cup.and.saucer.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "moon.fill",
        "bed.double.fill",
        "sparkles",
        "gamecontroller.fill",
        "music.note",
        "paintpalette.fill",
        "camera.fill",
        "tv.fill",
        "heart.fill",
        "cross.case.fill",
        "house.fill",
        "washer.fill",
        "cart.fill",
        "leaf.fill",
        "person.2.fill",
        "dumbbell.fill"
    ]

    private let colorPresets: [CategoryColorPreset] = [
        .init(name: "青", hex: "#2F80ED"),
        .init(name: "紫", hex: "#7C5CFF"),
        .init(name: "水色", hex: "#2D9CDB"),
        .init(name: "緑", hex: "#27AE60"),
        .init(name: "ミント", hex: "#00A896"),
        .init(name: "黄", hex: "#F2C94C"),
        .init(name: "橙", hex: "#F2994A"),
        .init(name: "赤", hex: "#EB5757"),
        .init(name: "桃", hex: "#D946EF"),
        .init(name: "グレー", hex: "#607D8B")
    ]

    var isNew: Bool { category == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("カテゴリ名") {
                    TextField("例: 勉強", text: $name)
                }

                Section("カラー") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(colorPresets) { preset in
                            Button {
                                color = Color(hex: preset.hex)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: preset.hex))
                                        .frame(width: 34, height: 34)
                                    if isSelectedColor(preset.hex) {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color(hex: preset.hex).liminalContrastingTextColor)
                                    }
                                }
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle()
                                        .stroke(isSelectedColor(preset.hex) ? Color(hex: preset.hex) : LiminalTheme.tertiaryText.opacity(0.22), lineWidth: isSelectedColor(preset.hex) ? 3 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }

                        Button {
                            customColorDraft = color
                            showingCustomColorPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(LiminalTheme.text.opacity(0.08)))
                                .frame(width: 42, height: 42)
                                .background(Circle().stroke(LiminalTheme.tertiaryText.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("色を追加")
                    }
                    .padding(.vertical, 4)
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
            .sheet(isPresented: $showingCustomColorPicker) {
                CategoryCustomColorSheet(
                    color: $customColorDraft,
                    icon: icon,
                    name: trimmedName.isEmpty ? "カテゴリ名" : trimmedName
                ) {
                    color = customColorDraft
                    showingCustomColorPicker = false
                }
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

    private func isSelectedColor(_ hex: String) -> Bool {
        color.hexString.uppercased() == hex.uppercased()
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

private struct CategoryColorPreset: Identifiable {
    var id: String { hex }
    let name: String
    let hex: String
}

private struct CategoryCustomColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var color: Color
    let icon: String
    let name: String
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("カラー") {
                    ColorPicker("カテゴリカラー", selection: $color, supportsOpacity: false)
                }

                Section("プレビュー") {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Circle()
                                .fill(color)
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: icon)
                                        .foregroundStyle(color.liminalContrastingTextColor)
                                }
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("色を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { apply() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

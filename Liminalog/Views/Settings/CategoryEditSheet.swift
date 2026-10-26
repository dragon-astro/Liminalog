import SwiftUI
import SwiftData

struct CategoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let category: Category?
    let onSaved: ((Category) -> Void)?

    init(category: Category?, onSaved: ((Category) -> Void)? = nil) {
        self.category = category
        self.onSaved = onSaved
    }

    @State private var name: String = ""
    @State private var color: Color = .blue
    @State private var icon: String = "circle.fill"
    @State private var dailyCardIntent: DailyCardCategoryIntent = .neutral
    @State private var analysisKind: CategoryAnalysisKind = .unspecified
    @State private var defaultAudienceFriendSetIDs: [UUID] = []
    @State private var defaultAudienceIncludedFriendIDs: [UUID] = []
    @State private var defaultAudienceExcludedFriendIDs: [UUID] = []
    @State private var showingAudiencePicker = false
    @State private var showingCustomColorPicker = false
    @State private var customColorDraft: Color = .blue
    @State private var saveError: String?
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

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
                    CategoryIconPicker(selection: $icon, tint: color)
                }

                Section("デイリーカード") {
                    Picker("傾向", selection: $dailyCardIntent) {
                        ForEach(DailyCardCategoryIntent.allCases) { intent in
                            Text(intent.title).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("扱い", selection: $analysisKind) {
                        ForEach(CategoryAnalysisKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } header: {
                    SettingsSectionHeader(title: "分析での扱い", explanation: "設定したカテゴリだけ、統計やプロフィールバッジの判定に使われます。未指定のカテゴリは判定に使われません。カテゴリ名や表示には影響しません。")
                }

                Section {
                    Button {
                        showingAudiencePicker = true
                    } label: {
                        AudienceSummaryRow(
                            title: "新しい実績・予定の公開相手",
                            count: resolvedAudienceCount,
                            systemImage: "person.2.fill",
                            tint: color
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    SettingsSectionHeader(title: "デフォルト公開相手", explanation: "通常は新しく作るものにだけコピーされます。必要な時だけ、公開相手の編集画面から過去の予定にも反映できます。")
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
                    analysisKind = cat.analysisKind
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

        let savedCategory: Category?
        if let cat = category {
            let didSave = store.updateCategory(
                cat,
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                analysisKind: analysisKind,
                isDailyCardSleepCategory: analysisKind == .sleep,
                defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
                defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
                defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
            )
            savedCategory = didSave ? cat : nil
        } else {
            savedCategory = store.createCategory(
                name: trimmed,
                colorHex: color.hexString,
                icon: icon,
                dailyCardIntent: dailyCardIntent,
                analysisKind: analysisKind,
                isDailyCardSleepCategory: analysisKind == .sleep,
                defaultAudienceFriendSetIDs: defaultAudienceFriendSetIDs,
                defaultAudienceIncludedFriendIDs: defaultAudienceIncludedFriendIDs,
                defaultAudienceExcludedFriendIDs: defaultAudienceExcludedFriendIDs
            )
        }
        guard let savedCategory else {
            saveError = "カテゴリの変更を保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        onSaved?(savedCategory)
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

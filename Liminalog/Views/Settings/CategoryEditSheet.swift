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

    private let icons: [CategoryIconOption] = [
        .init(symbol: "book.closed.fill", label: "読書・学習"),
        .init(symbol: "graduationcap.fill", label: "授業・講義"),
        .init(symbol: "pencil.and.outline", label: "ノート・執筆"),
        .init(symbol: "briefcase.fill", label: "仕事"),
        .init(symbol: "laptopcomputer", label: "PC作業"),
        .init(symbol: "doc.text.fill", label: "書類・事務"),
        .init(symbol: "checklist", label: "タスク"),
        .init(symbol: "calendar", label: "予定"),
        .init(symbol: "clock.fill", label: "予定・ルーティン"),
        .init(symbol: "tram.fill", label: "電車移動"),
        .init(symbol: "figure.walk", label: "徒歩"),
        .init(symbol: "figure.run", label: "ランニング"),
        .init(symbol: "airplane", label: "旅行・遠出"),
        .init(symbol: "house.fill", label: "家事・生活"),
        .init(symbol: "wrench.and.screwdriver.fill", label: "整理・メンテナンス"),
        .init(symbol: "cart.fill", label: "買い物"),
        .init(symbol: "fork.knife", label: "料理・食事"),
        .init(symbol: "cup.and.saucer.fill", label: "休憩"),
        .init(symbol: "sparkles", label: "自由時間"),
        .init(symbol: "gamecontroller.fill", label: "ゲーム"),
        .init(symbol: "music.note", label: "音楽"),
        .init(symbol: "paintpalette.fill", label: "創作"),
        .init(symbol: "camera.fill", label: "写真"),
        .init(symbol: "movieclapper.fill", label: "動画・鑑賞"),
        .init(symbol: "heart.fill", label: "ケア"),
        .init(symbol: "cross.case.fill", label: "通院・体調"),
        .init(symbol: "dumbbell.fill", label: "筋トレ"),
        .init(symbol: "bed.double.fill", label: "睡眠"),
        .init(symbol: "moon.fill", label: "休息・夜"),
        .init(symbol: "person.2.fill", label: "人付き合い")
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
                        ForEach(icons) { option in
                            Button {
                                icon = option.symbol
                            } label: {
                                Image(systemName: option.symbol)
                                    .font(.headline)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(icon == option.symbol ? .white : color)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(icon == option.symbol ? color : color.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.label)
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
                }

                Section {
                    Picker("扱い", selection: $analysisKind) {
                        ForEach(CategoryAnalysisKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } header: {
                    Text("分析での扱い")
                } footer: {
                    Text("設定したカテゴリだけ、統計やプロフィールバッジの判定に使われます。未指定のカテゴリは判定に使われません。カテゴリ名や表示には影響しません。")
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

        let didSave: Bool
        if let cat = category {
            didSave = store.updateCategory(
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
        } else {
            didSave = store.addCategory(
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

private struct CategoryIconOption: Identifiable {
    var id: String { symbol }
    let symbol: String
    let label: String
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

import SwiftUI
import SwiftData

struct VisibilityPresetSettingsView: View {
    @State private var showingCreateSheet = false
    @Query(sort: [SortDescriptor(\VisibilityPreset.sortOrder), SortDescriptor(\VisibilityPreset.createdAt)]) private var presets: [VisibilityPreset]

    var body: some View {
        List {
            Section {
                ForEach(presets) { preset in
                    NavigationLink {
                        VisibilityPresetEditView(preset: preset)
                    } label: {
                        VisibilityPresetRow(preset: preset)
                    }
                }
            } footer: {
                Text("ここで決めた見え方は、そのプリセットを割り当てた友達に適用されます。公開相手に含まれていても、オフの友達には共有されません。")
            }
        }
        .navigationTitle("見え方プリセット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("見え方プリセットを追加")
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            VisibilityPresetCreateSheet()
        }
    }
}

private struct VisibilityPresetRow: View {
    let preset: VisibilityPreset

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    private var iconName: String {
        switch preset.publishMode {
        case .realtime:
            return "dot.radiowaves.left.and.right"
        case .nextDay:
            return "calendar.badge.clock"
        case .none:
            return "eye.slash.fill"
        }
    }

    private var tint: Color {
        switch preset.publishMode {
        case .realtime:
            return LiminalTheme.accent
        case .nextDay:
            return LiminalTheme.reward
        case .none:
            return LiminalTheme.secondaryText
        }
    }

    private var summary: String {
        if preset.publishMode == .none {
            return "共有しない"
        }

        var parts: [String] = [preset.publishMode.displayName]
        if preset.freeTimeOnly { parts.append("予定は予定あり") }
        if preset.hideMoodAndNote { parts.append("メモ非表示") }
        if preset.hideLocation { parts.append("場所非表示") }
        if preset.hidePhoto { parts.append("写真非表示") }
        return parts.joined(separator: " / ")
    }
}

private struct VisibilityPresetEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @State private var showDeleteConfirm = false
    @State private var saveError: String?

    let preset: VisibilityPreset

    var body: some View {
        Form {
            Section("名前") {
                if preset.isBuiltIn {
                    LabeledContent("プリセット名", value: preset.name)
                } else {
                    TextField("プリセット名", text: nameBinding)
                }
            }

            Section {
                Picker("公開タイミング", selection: publishModeBinding) {
                    ForEach(PublishMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(preset.publishMode.description)
            }

            Section {
                Toggle("予定は「予定あり」として見せる", isOn: boolBinding(\.freeTimeOnly))
                Toggle("メモ・気分を隠す", isOn: boolBinding(\.hideMoodAndNote))
                Toggle("場所を隠す", isOn: boolBinding(\.hideLocation))
                Toggle("写真を隠す", isOn: boolBinding(\.hidePhoto))
            } header: {
                Text("隠す項目")
            } footer: {
                Text("カテゴリごとの公開相手は変えず、この友達に見える詳しさだけを調整します。")
            }
            .disabled(preset.publishMode == .none)

            if preset.publishMode == .none {
                Section {
                    Label("このプリセットの友達には共有されません", systemImage: "eye.slash.fill")
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }

            if !preset.isBuiltIn {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("プリセットを削除", systemImage: "trash.fill")
                    }
                } footer: {
                    Text("このプリセットを使っている友達は、標準の控えめ設定に戻ります。")
                }
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("プリセットを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                deletePreset()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は元に戻せません。")
        }
        .alert("保存できませんでした", isPresented: saveErrorPresented) {
            Button("OK") {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var nameBinding: Binding<String> {
        Binding {
            preset.name
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            preset.name = trimmed.isEmpty ? preset.name : newValue
            VisibilityPresetCustomization.markCustomized(preset.id)
            preset.updatedAt = Date()
            save()
        }
    }

    private var publishModeBinding: Binding<PublishMode> {
        Binding {
            preset.publishMode
        } set: { newValue in
            preset.publishMode = newValue
            VisibilityPresetCustomization.markCustomized(preset.id)
            normalizeLevel()
            save()
        }
    }

    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<VisibilityPreset, Bool>) -> Binding<Bool> {
        Binding {
            preset[keyPath: keyPath]
        } set: { newValue in
            preset[keyPath: keyPath] = newValue
            VisibilityPresetCustomization.markCustomized(preset.id)
            normalizeLevel()
            save()
        }
    }

    private func normalizeLevel() {
        if preset.publishMode == .none {
            preset.level = .none
        } else if preset.publishMode == .nextDay || preset.hideMoodAndNote || preset.hidePhoto || preset.hideLocation || preset.freeTimeOnly {
            preset.level = .partial
        } else {
            preset.level = .all
        }
        preset.updatedAt = Date()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save visibility preset setting: \(String(describing: error))")
        }
    }

    private func deletePreset() {
        let fallbackID = friends.isEmpty ? nil : defaultVisibilityPresetID
        for friend in friends where friend.visibilityPresetID == preset.id {
            friend.visibilityPresetID = fallbackID
            friend.updatedAt = Date()
        }
        modelContext.delete(preset)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "プリセットを削除できませんでした。時間をおいてもう一度試してください。"
            NSLog("Liminalog: failed to delete visibility preset: \(String(describing: error))")
        }
    }

    private var defaultVisibilityPresetID: UUID? {
        let descriptor = FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        guard let presets = try? modelContext.fetch(descriptor) else { return nil }
        return presets.first { $0.builtInKey == "acquaintances" }?.id
            ?? presets.first { $0.name == "控えめ" }?.id
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
}

private struct VisibilityPresetCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\VisibilityPreset.sortOrder), SortDescriptor(\VisibilityPreset.createdAt)]) private var presets: [VisibilityPreset]

    @State private var name = ""
    @State private var publishMode: PublishMode = .nextDay
    @State private var freeTimeOnly = true
    @State private var hideMoodAndNote = true
    @State private var hideLocation = true
    @State private var hidePhoto = true
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: 学校の友達", text: $name)
                }

                Section {
                    Picker("公開タイミング", selection: $publishMode) {
                        ForEach(PublishMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(publishMode.description)
                }

                Section {
                    Toggle("予定は「予定あり」として見せる", isOn: $freeTimeOnly)
                    Toggle("メモ・気分を隠す", isOn: $hideMoodAndNote)
                    Toggle("場所を隠す", isOn: $hideLocation)
                    Toggle("写真を隠す", isOn: $hidePhoto)
                } header: {
                    Text("隠す項目")
                }
                .disabled(publishMode == .none)
            }
            .navigationTitle("プリセットを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { createPreset() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
            .alert("追加できませんでした", isPresented: saveErrorPresented) {
                Button("OK") {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createPreset() {
        let now = Date()
        let preset = VisibilityPreset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            level: normalizedLevel,
            sortOrder: nextSortOrder,
            publishMode: publishMode,
            hideMoodAndNote: publishMode == .none ? true : hideMoodAndNote,
            hidePhoto: publishMode == .none ? true : hidePhoto,
            hideLocation: publishMode == .none ? true : hideLocation,
            freeTimeOnly: publishMode == .none ? true : freeTimeOnly,
            now: now
        )
        modelContext.insert(preset)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "プリセットを追加できませんでした。時間をおいてもう一度試してください。"
            NSLog("Liminalog: failed to create visibility preset: \(String(describing: error))")
        }
    }

    private var normalizedLevel: VisibilityLevel {
        if publishMode == .none {
            return .none
        }
        if publishMode == .nextDay || hideMoodAndNote || hidePhoto || hideLocation || freeTimeOnly {
            return .partial
        }
        return .all
    }

    private var nextSortOrder: Int {
        (presets.map(\.sortOrder).max() ?? 0) + 10
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
}

private extension PublishMode {
    var displayName: String {
        switch self {
        case .realtime:
            return "リアルタイム"
        case .nextDay:
            return "翌日"
        case .none:
            return "オフ"
        }
    }

    var description: String {
        switch self {
        case .realtime:
            return "記録中の状態や予定をそのまま共有します。"
        case .nextDay:
            return "リアルタイム性を落として、控えめに共有します。"
        case .none:
            return "公開相手に含まれていても、このプリセットの友達には共有しません。"
        }
    }
}

#Preview("Visibility Presets") {
    NavigationStack {
        VisibilityPresetSettingsView()
            .liminalogPreviewEnvironment()
    }
}

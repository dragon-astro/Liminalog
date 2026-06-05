import SwiftUI
import SwiftData

/// テーマ切替UI。選択は UserSettings.themeName に保存し、アプリ全体が即追従する
/// （RootTabView が themeName を監視して activeThemeID / preferredColorScheme を同期）。
/// 解放ゲートはコレクション側の UnlockItem を参照し、設定画面では解放済みテーマだけ選択できる。
struct ThemePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.liminalThemeTransitionProgress) private var themeTransitionProgress
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query(sort: \UnlockItem.sortOrder) private var unlockItems: [UnlockItem]
    @State private var saveError: String?
    #if DEBUG
    @AppStorage("debug.unlocks.allowLockedDecorations") private var allowsLockedDecorationTesting = false
    #endif

    private var settings: UserSettings? { settingsList.first }
    private var selectedID: String { unlocks.equippedThemeID(settings?.themeName) }
    private var unlocks: ProfileDecorationUnlocks {
        ProfileDecorationUnlocks(
            unlockItems: unlockItems,
            includesLockedCatalogItems: allowsLockedDecorationSelection
        )
    }

    private var allowsLockedDecorationSelection: Bool {
        #if DEBUG
        allowsLockedDecorationTesting
        #else
        false
        #endif
    }

    var body: some View {
        List {
            Section {
                themeRow(
                    id: LiminalThemeCatalog.systemThemeID,
                    name: "システム追従",
                    subtitle: "ライトでは曙、ダークでは宵",
                    definition: nil,
                    isUnlocked: true
                )

                ForEach(LiminalThemeCatalog.fixedDefaultThemes, id: \.id) { definition in
                    themeRow(
                        id: definition.id,
                        name: definition.name,
                        subtitle: "固定",
                        definition: definition,
                        isUnlocked: true
                    )
                }
            } header: {
                Text("標準テーマ")
            } footer: {
                Text("標準テーマは常に選べます。システム追従だけが端末のライト/ダークに合わせて切り替わります。")
            }

            Section {
                ForEach(LiminalThemeCatalog.selectableThemes, id: \.id) { definition in
                    themeRow(
                        id: definition.id,
                        name: definition.name,
                        subtitle: nil,
                        definition: definition,
                        isUnlocked: unlocks.themeIsUnlocked(definition.id)
                    )
                }
            } header: {
                Text("解放テーマ")
            } footer: {
                Text("未解放のテーマはコレクションで条件を満たすと選べるようになります。")
            }
        }
        .navigationTitle("テーマ")
        .navigationBarTitleDisplayMode(.inline)
        .alert("テーマを変更できませんでした", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private func themeRow(id: String, name: String, subtitle: String?, definition: LiminalThemeDefinition?, isUnlocked: Bool) -> some View {
        let _ = themeTransitionProgress
        Button {
            guard isUnlocked else { return }
            apply(id)
        } label: {
            HStack(spacing: 14) {
                ThemeSwatch(definition: definition)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(LiminalTheme.secondaryText)
                    } else if !isUnlocked {
                        Text("未解放")
                            .font(.caption)
                            .foregroundStyle(LiminalTheme.secondaryText)
                    }
                }

                Spacer()

                if selectedID == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LiminalTheme.accent)
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }

    private func apply(_ id: String) {
        let target: UserSettings
        if let settings {
            guard settings.themeName != id else { return }
            target = settings
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            target = created
        }
        target.themeName = id
        target.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            NSLog("Liminalog: failed to save theme setting: \(String(describing: error))")
            modelContext.rollback()
            saveError = "時間をおいてもう一度試してください。"
        }
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

private struct ThemeSwatch: View {
    let definition: LiminalThemeDefinition?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(gradient)
            .frame(width: 46, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(swatchRingColor, lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if let definition {
                    Circle()
                        .fill(Color(definition.palette.accent))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(accentRingColor(for: definition), lineWidth: 1))
                        .padding(4)
                }
            }
    }

    private func accentRingColor(for definition: LiminalThemeDefinition) -> Color {
        if definition.id == LiminalThemeCatalog.daybreak.id {
            return Color(hex: "#7E777C").opacity(0.7)
        }
        if definition.appearance == .light {
            return Color(definition.palette.text).opacity(0.5)
        }
        return .white.opacity(0.5)
    }

    private var swatchRingColor: Color {
        guard let definition else {
            return .white.opacity(0.18)
        }
        if definition.id == LiminalThemeCatalog.daybreak.id {
            return Color(hex: "#8B8186").opacity(0.42)
        }
        if definition.appearance == .light {
            return Color(definition.palette.text).opacity(0.18)
        }
        return .white.opacity(0.18)
    }

    private var gradient: LinearGradient {
        if let definition {
            return LinearGradient(
                colors: [
                    Color(definition.palette.gradientTop),
                    Color(definition.palette.gradientMiddle),
                    Color(definition.palette.gradientBottom)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        // default = 宵 → 曙 のヒント
        return LinearGradient(
            colors: [
                Color(LiminalThemeCatalog.dusk.palette.canvas),
                Color(LiminalThemeCatalog.dusk.palette.gradientMiddle),
                Color(LiminalThemeCatalog.daybreak.palette.gradientBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

import SwiftUI
import SwiftData

struct ChapterEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store

    let chapter: Chapter

    @State private var startTime: Date = Date()
    @State private var endTime: Date? = nil
    @State private var note: String = ""
    @State private var locationName: String = ""
    @State private var isPublic: Bool = true
    @State private var selectedCategory: Category? = nil
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]
    @State private var showDeleteConfirm = false
    @State private var showingCategoryPicker = false
    @State private var showingAudiencePicker = false
    @State private var audienceFriendIDs: [UUID] = []
    @State private var audienceSource: AudienceSource = .categoryDefaultSnapshot
    @State private var didLoadValues = false
    @State private var isLoadingValues = false
    @State private var saveError: String?

    private struct Draft: Equatable {
        var start: Date
        var end: Date?
        var categoryID: UUID?
        var note: String
        var location: String
        var isPublic: Bool
        var audience: Set<UUID>
        var source: AudienceSource
    }
    private var draft: Draft {
        Draft(start: startTime,
              end: endTime,
              categoryID: selectedCategory?.id,
              note: note.trimmingCharacters(in: .whitespacesAndNewlines),
              location: locationName.trimmingCharacters(in: .whitespacesAndNewlines),
              isPublic: isPublic,
              audience: Set(audienceFriendIDs),
              source: audienceSource)
    }

    @State private var initialDraft: Draft?
    @State private var showingDiscardConfirmation = false
    private var hasChanges: Bool { initialDraft.map { $0 != draft } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ActualEditorIdentityCard(category: selectedCategory, isActive: chapter.isActive)
                    timeCard
                    categoryCard
                    visibilityCard
                    EditorTextRow(title: "場所", symbol: "mappin.and.ellipse", text: $locationName, tint: selectedTint)
                    EditorTextRow(title: "メモ", symbol: "note.text", text: $note, tint: selectedTint)
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .accessibilityIdentifier("chapter-editor-scroll")
            .background(LiminalTheme.canvasGradient)
            .editorDateSelectionScope()
            .navigationTitle(chapter.isActive ? "記録中の実績" : "実績を編集")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissGuard(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation) { dismiss() }
                }.sharedBackgroundVisibility(.hidden)
                if !isTimeLocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditorActionsMenu {
                            Button("実績を削除", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                        }
                    }.sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditorSaveButton(isEmphasized: hasChanges, canSave: canSave) { save() }
                }.sharedBackgroundVisibility(.hidden)
            }
            .confirmationDialog("実績を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if store.deleteChapter(chapter) {
                        dismiss()
                    } else {
                        saveError = "実績を削除できませんでした。時間をおいてもう一度試してください。"
                    }
                }
            }
            .onAppear {
                guard !didLoadValues else { return }
                loadValues()
                initialDraft = draft
            }
            .sheet(isPresented: $showingCategoryPicker) {
                PlanCategoryPickerSheet(
                    categorySets: categorySets,
                    categories: categories,
                    selectedCategory: $selectedCategory
                )
            }
            .sheet(isPresented: $showingAudiencePicker) {
                AudienceSnapshotPickerSheet(audienceFriendIDs: $audienceFriendIDs)
            }
            .onChange(of: selectedCategory?.id) { _, _ in
                guard didLoadValues, !isLoadingValues, audienceSource == .categoryDefaultSnapshot else { return }
                resetAudienceToCategoryDefault()
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

    @ViewBuilder
    private var categoryCard: some View {
        if categories.isEmpty {
            categoryListCard
        } else {
            PlanEditorCard(tint: selectedTint) {
                VStack(alignment: .leading, spacing: 10) {
                    PlanCategoryInlinePicker(
                        categories: categories,
                        categorySets: categorySets,
                        selectedCategory: $selectedCategory
                    )
                    if selectedCategory != nil && !isTimeLocked {
                        Button { selectedCategory = nil } label: {
                            Label("カテゴリを外す", systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(LiminalTheme.secondaryText)
                    }
                }
            }
            .disabled(isTimeLocked)
        }
    }

    private var categoryListCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "カテゴリ", systemImage: "square.grid.2x2.fill", tint: selectedTint)

                Button {
                    showingCategoryPicker = true
                } label: {
                    HStack(spacing: 12) {
                        CategoryPreviewIcon(category: selectedCategory, size: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCategory?.name ?? "カテゴリなし")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                            Text(selectedCategorySetName)
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiminalTheme.tertiaryText)
                    }
                    .padding(12)
                    .background(selectedTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isTimeLocked)

                if selectedCategory != nil && !isTimeLocked {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Label("カテゴリを外す", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
    }

    private var timeCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                EditorDateRow(title: "開始", date: $startTime)
                    .disabled(isTimeLocked)
                if endTime != nil {
                    EditorDateRow(title: "終了", date: Binding(get: { endTime ?? Date() }, set: { endTime = $0 }))
                        .disabled(isTimeLocked)
                } else {
                    HStack {
                        Text("終了").foregroundStyle(LiminalTheme.secondaryText)
                        Spacer()
                        Text("記録中").font(.subheadline.weight(.semibold))
                    }.frame(minHeight: 34)
                }
                validationStatus
            }
        }
    }

    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isPublic) {
                    Label("友達に見せる", systemImage: isPublic ? "person.2" : "lock")
                }
                .font(.subheadline)
                .accessibilityIdentifier("chapter-visibility")

                if isPublic {
                    Button {
                        showingAudiencePicker = true
                        audienceSource = .custom
                    } label: {
                        AudienceSummaryRow(
                            title: "公開相手",
                            count: audienceFriendIDs.count,
                            systemImage: "person.2.fill",
                            tint: selectedTint
                        )
                        .padding(12)
                        .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        resetAudienceToCategoryDefault()
                    } label: {
                        Label("カテゴリ既定値に戻す", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
    }

    private func loadValues() {
        isLoadingValues = true
        defer {
            isLoadingValues = false
            didLoadValues = true
        }
        startTime = chapter.startTime
        endTime = chapter.endTime
        note = chapter.note ?? ""
        locationName = chapter.locationName ?? ""
        isPublic = chapter.isPublic
        selectedCategory = chapter.category
        if chapter.hasAudienceSnapshot {
            audienceFriendIDs = chapter.audienceFriendIDs
            audienceSource = chapter.audienceSource
        } else {
            resetAudienceToCategoryDefault()
        }
    }

    private func resetAudienceToCategoryDefault() {
        audienceFriendIDs = AudienceResolver.categoryDefaultAudience(
            for: selectedCategory,
            friendSets: friendSets,
            friends: friends
        )
        audienceSource = .categoryDefaultSnapshot
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

    @ViewBuilder
    private var validationStatus: some View {
        if isTimeLocked {
            PlanEditorStatusLabel(
                text: "前日以前の実績はスコア公平性のため、時間とカテゴリを変更できません。メモ・場所は後から編集できます。",
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if let validationMessage {
            PlanEditorStatusLabel(
                text: validationMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    private var selectedTint: Color {
        selectedCategory?.displayColor ?? LiminalTheme.accent
    }

    private var selectedCategorySetName: String {
        guard let selectedCategory else { return "未分類" }
        if let set = categorySets.first(where: { $0.assignedIDs.contains(selectedCategory.id) }) {
            return "\(set.name) セット"
        }
        return "すべてのカテゴリ"
    }

    private func save() {
        guard canSave else { return }
        guard store.saveChapter(
            chapter,
            startTime: startTime,
            endTime: endTime,
            category: selectedCategory,
            note: note,
            mood: chapter.mood,
            locationName: locationName,
            isPublic: isPublic,
            audienceFriendIDs: audienceFriendIDs,
            audienceSource: audienceSource,
            hasAudienceSnapshot: shouldSaveAudienceSnapshot
        ) else {
            saveError = "実績の変更を保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        dismiss()
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

    private var shouldSaveAudienceSnapshot: Bool {
        AudienceSnapshotPolicy.shouldSaveSnapshot(
            isPublic: isPublic,
            audienceSource: audienceSource,
            audienceFriendIDs: audienceFriendIDs
        )
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

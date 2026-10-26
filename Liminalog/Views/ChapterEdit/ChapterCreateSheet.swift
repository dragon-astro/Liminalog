import SwiftUI
import SwiftData

struct ChapterCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChapterStore.self) private var store
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]
    @Query(sort: \FriendSet.sortOrder) private var friendSets: [FriendSet]
    @Query(sort: \Friend.displayName) private var friends: [Friend]

    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedCategory: Category?
    @State private var note = ""
    @State private var locationName = ""
    @State private var isPublic = true
    @State private var audienceFriendIDs: [UUID] = []
    @State private var audienceSource: AudienceSource = .categoryDefaultSnapshot
    @State private var showingAudiencePicker = false
    @State private var didInitializeAudience = false
    @State private var saveError: String?

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
                    ActualEditorIdentityCard(category: selectedCategory, isNew: true)
                    PlanEditorCard(tint: selectedTint) {
                        VStack(alignment: .leading, spacing: 12) {
                            EditorDateRow(title: "開始", date: $startTime, range: todayRange)
                            EditorDateRow(title: "終了", date: $endTime, range: endTimeRange)
                            if let validationMessage {
                                PlanEditorStatusLabel(text: validationMessage, systemImage: "exclamationmark.triangle.fill", tint: LiminalTheme.reward)
                            }
                        }
                    }
                    PlanEditorCard(tint: selectedTint) {
                        PlanCategoryInlinePicker(categories: categories, categorySets: categorySets, selectedCategory: $selectedCategory)
                    }
                    visibilityCard
                    EditorTextRow(title: "場所", symbol: "mappin.and.ellipse", text: $locationName, tint: selectedTint)
                    EditorTextRow(title: "メモ", symbol: "note.text", text: $note, tint: selectedTint)
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .accessibilityIdentifier("chapter-create-form")
            .background(LiminalTheme.canvasGradient)
            .editorDateSelectionScope()
            .navigationTitle("実績を追加")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissGuard(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton(hasChanges: hasChanges, showingConfirmation: $showingDiscardConfirmation) { dismiss() }
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    EditorSaveButton(isEmphasized: true, canSave: canSave) { save() }
                }.sharedBackgroundVisibility(.hidden)
            }
            .onAppear {
                if !didInitializeAudience {
                    resetAudienceToCategoryDefault()
                    didInitializeAudience = true
                }
                clampToToday()
                if initialDraft == nil { initialDraft = draft }
            }
            .onChange(of: selectedCategory?.id) { _, _ in
                guard didInitializeAudience, audienceSource == .categoryDefaultSnapshot else { return }
                resetAudienceToCategoryDefault()
            }
            .sheet(isPresented: $showingAudiencePicker) {
                AudienceSnapshotPickerSheet(audienceFriendIDs: $audienceFriendIDs)
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

    private var selectedTint: Color { selectedCategory?.displayColor ?? LiminalTheme.accent }

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

    private func resetAudienceToCategoryDefault() {
        audienceFriendIDs = AudienceResolver.categoryDefaultAudience(
            for: selectedCategory,
            friendSets: friendSets,
            friends: friends
        )
        audienceSource = .categoryDefaultSnapshot
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

    private func save() {
        guard let selectedCategory else { return }
        guard store.addChapter(
            category: selectedCategory,
            startTime: startTime,
            endTime: endTime,
            note: note,
            mood: nil,
            locationName: locationName,
            isPublic: isPublic,
            audienceFriendIDs: audienceFriendIDs,
            audienceSource: audienceSource,
            hasAudienceSnapshot: shouldSaveAudienceSnapshot
        ) else {
            saveError = "実績を保存できませんでした。時間をおいてもう一度試してください。"
            return
        }
        dismiss()
    }
}

#Preview("Create Chapter") {
    ChapterCreateSheet()
        .liminalogPreviewEnvironment()
}

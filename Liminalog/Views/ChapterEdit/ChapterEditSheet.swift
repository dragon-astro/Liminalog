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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    chapterPreviewCard
                    categoryCard
                    timeCard
                    noteCard
                    locationCard
                    visibilityCard
                    deleteCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(LiminalTheme.canvasGradient)
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
                    if store.deleteChapter(chapter) {
                        dismiss()
                    } else {
                        saveError = "チャプターを削除できませんでした。時間をおいてもう一度試してください。"
                    }
                }
            }
            .onAppear {
                guard !didLoadValues else { return }
                loadValues()
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

    private var chapterPreviewCard: some View {
        let tint = selectedTint
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CategoryPreviewIcon(category: selectedCategory, size: 52)

                VStack(alignment: .leading, spacing: 7) {
                    Text(previewTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)

                    Text(previewTimeText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: chapter.isActive ? "record.circle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .liminalGlassFill(in: Circle())
            }

            HStack(spacing: 8) {
                PlanPreviewBadge(
                    text: chapter.isActive ? "記録中" : "記録済み",
                    systemImage: chapter.isActive ? "record.circle.fill" : "checkmark.circle.fill",
                    tint: tint
                )
                PlanPreviewBadge(
                    text: previewDurationText,
                    systemImage: "clock.fill",
                    tint: tint
                )
                PlanPreviewBadge(
                    text: isPublic ? "共有" : "非公開",
                    systemImage: isPublic ? "eye.fill" : "eye.slash.fill",
                    tint: isPublic ? LiminalTheme.accent : LiminalTheme.secondaryText
                )
                if isTimeLocked {
                    PlanPreviewBadge(text: "ロック", systemImage: "lock.fill", tint: LiminalTheme.secondaryText)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiminalTheme.surface)
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: tint)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    private var categoryCard: some View {
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
                PlanEditorSectionHeader(title: "時間", systemImage: "clock.fill", tint: selectedTint)

                VStack(spacing: 10) {
                    DatePicker("開始", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(LiminalTheme.text)
                        .tint(LiminalTheme.text)
                        .allowsHitTesting(!isTimeLocked)

                    if endTime != nil {
                        DatePicker("終了", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .foregroundStyle(LiminalTheme.text)
                        .tint(LiminalTheme.text)
                        .allowsHitTesting(!isTimeLocked)
                    } else {
                        HStack {
                            Text("終了")
                                .foregroundStyle(LiminalTheme.secondaryText)
                            Spacer()
                            Text("記録中")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                        }
                    }
                }
                .padding(12)
                .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                validationStatus
            }
        }
    }

    private var noteCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "メモ", systemImage: "note.text", tint: selectedTint)
                TextField("メモを追加...", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var locationCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 10) {
                PlanEditorSectionHeader(title: "場所", systemImage: "mappin.and.ellipse", tint: selectedTint)
                TextField("場所名を追加...", text: $locationName)
                    .padding(12)
                    .background(LiminalTheme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var visibilityCard: some View {
        PlanEditorCard(tint: selectedTint) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isPublic) {
                    PlanEditorSectionHeader(
                        title: isPublic ? "友達に見せる" : "自分だけ",
                        systemImage: isPublic ? "eye.fill" : "eye.slash.fill",
                        tint: isPublic ? LiminalTheme.accent : LiminalTheme.secondaryText
                    )
                }
                .tint(selectedTint)

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

    private var deleteCard: some View {
        PlanEditorCard(tint: isTimeLocked ? LiminalTheme.secondaryText : Color.red) {
            if isTimeLocked {
                PlanEditorStatusLabel(
                    text: "前日以前の実績は削除できません。",
                    systemImage: "lock.fill",
                    tint: LiminalTheme.secondaryText
                )
            } else {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("チャプターを削除", systemImage: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var previewTitle: String {
        selectedCategory?.name ?? "カテゴリなしの実績"
    }

    private var previewTimeText: String {
        let resolvedEnd = endTime ?? Date()
        if Calendar.current.isDate(startTime, inSameDayAs: resolvedEnd) {
            return "\(startTime.japaneseMonthDayShortWeekday) \(startTime.shortTime) - \(resolvedEnd.shortTime)"
        }
        return "\(startTime.japaneseMonthDayShortWeekday) \(startTime.shortTime) - \(resolvedEnd.japaneseMonthDayShortWeekday) \(resolvedEnd.shortTime)"
    }

    private var previewDurationText: String {
        let resolvedEnd = endTime ?? Date()
        return compactDuration(max(0, resolvedEnd.timeIntervalSince(startTime)))
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
            saveError = "チャプターの変更を保存できませんでした。時間をおいてもう一度試してください。"
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
        guard isPublic else { return false }
        if audienceSource == .custom {
            return true
        }
        return !audienceFriendIDs.isEmpty
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

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)時間"
        }
        return "\(hours)時間\(remainingMinutes)分"
    }
}

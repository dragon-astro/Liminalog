import SwiftUI
import SwiftData

let currentTimeMarkerID = "current-time-marker"

private enum TimelineTab: String, CaseIterable, Identifiable {
    case actual
    case plan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plan:
            return "予定"
        case .actual:
            return "実績"
        }
    }

    var systemImage: String {
        switch self {
        case .plan:
            return "calendar"
        case .actual:
            return "checkmark.circle.fill"
        }
    }
}

private enum TimelineEntryKind {
    case plan
    case actual
    case gap(TimelineTab)

    var tab: TimelineTab {
        switch self {
        case .plan:
            return .plan
        case .actual:
            return .actual
        case .gap(let tab):
            return tab
        }
    }

    var isGap: Bool {
        if case .gap = self { return true }
        return false
    }
}

private struct TimelineEntryMetadata {
    var note: String?
    var mood: String?
    var locationName: String?
    var plannedMatchTitle: String?
    var isShort: Bool
    var continuesFromPreviousDay: Bool
    var continuesToNextDay: Bool
}

private struct TimelineEntry: Identifiable {
    let id: String
    let kind: TimelineEntryKind
    let sourceID: UUID?
    let start: Date
    let end: Date
    let clippedStart: Date
    let clippedEnd: Date
    let title: String
    let subtitle: String?
    let categoryName: String
    let categoryIconName: String
    let categoryColorHex: String
    let isActive: Bool
    let chapter: Chapter?
    let plan: PlanBlock?
    let metadata: TimelineEntryMetadata

    var color: Color {
        Color(hex: categoryColorHex)
    }

    var clippedDuration: TimeInterval {
        max(clippedEnd.timeIntervalSince(clippedStart), 0)
    }

    var timeRangeText: String {
        return "\(clippedStart.shortTime) - \(clippedEnd.shortTime)"
    }

    var durationText: String {
        displayDuration(clippedDuration)
    }
}

struct TimelineView: View {
    @Environment(ChapterStore.self) private var store
    @AppStorage("timelineSelectedTab") private var selectedTabRawValue = TimelineTab.actual.rawValue
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]

    let date: Date
    let title: String
    var compactEmptyState = false
    var allowsChapterCreation = true
    var allowsPlanCreation = true
    var focusedPlanID: UUID?
    @Binding var editingChapter: Chapter?

    // 24時間バーの現在時刻表示は粗くてよい（1分≒1px未満）。毎秒だとタイムライン全体の
    // 再構築が毎秒走りスワイプ等がカクつくため、60秒間隔にする。ライブの秒カウントは
    // CurrentChapterCard 側（軽量テキスト）が担当する。
    @State private var clock = TickClock(interval: 60)
    @State private var editingPlan: PlanBlock?
    @State private var highlightedEntryID: String?
    @State private var quickDetailEntry: TimelineEntry?
    @State private var showingChapterCreate = false
    @State private var showingPlanCreate = false
    @State private var gapStartDate: Date = Date()

    private var now: Date {
        clock.now
    }

    init(
        date: Date,
        title: String,
        compactEmptyState: Bool = false,
        editingChapter: Binding<Chapter?>,
        allowsChapterCreation: Bool = true,
        allowsPlanCreation: Bool = true,
        focusedPlanID: UUID? = nil
    ) {
        self.date = date
        self.title = title
        self.compactEmptyState = compactEmptyState
        self.allowsChapterCreation = allowsChapterCreation
        self.allowsPlanCreation = allowsPlanCreation
        self.focusedPlanID = focusedPlanID
        self._editingChapter = editingChapter

        let boundary = DayBoundary(date: date, calendar: .japanese)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let chapterLookbackStart = Calendar.japanese.date(byAdding: .day, value: -14, to: dayStart) ?? dayStart
        self._queriedChapters = Query(
            filter: #Predicate<Chapter> {
                $0.startTime >= chapterLookbackStart && $0.startTime < dayEnd
            },
            sort: [SortDescriptor(\.startTime)]
        )
        self._queriedPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < dayEnd && $0.endTime > dayStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    private var selectedTab: TimelineTab {
        TimelineTab(rawValue: selectedTabRawValue) ?? .actual
    }

    private var selectedEntries: [TimelineEntry] {
        switch selectedTab {
        case .plan:
            return planEntries
        case .actual:
            return actualEntries
        }
    }

    private var actualEntries: [TimelineEntry] {
        entries(for: timelineChapters, tab: .actual)
    }

    private var planEntries: [TimelineEntry] {
        entries(for: timelinePlans, tab: .plan)
    }

    private var timelineChapters: [Chapter] {
        queriedChapters
            .filter { chapter in
                chapter.startTime < dayEnd && (chapter.endTime ?? now) > dayStart
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private var timelinePlans: [PlanBlock] {
        queriedPlans
            .filter { plan in
                !plan.isAllDay && plan.startTime < dayEnd && plan.endTime > dayStart
            }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        // エントリ計算（フィルタ＋ソート＋gapマージ）は重いので、1描画で1回だけ実施し
        // バー・リストで使い回す（従来は computed プロパティ参照で3〜4回再計算していた）。
        let actual = actualEntries
        let plan = planEntries
        let selected = selectedTab == .actual ? actual : plan
        return VStack(alignment: .leading, spacing: 12) {
            DayOverviewBar(
                date: date,
                now: now,
                planEntries: plan.filter { !$0.kind.isGap },
                actualEntries: actual.filter { !$0.kind.isGap },
                onEntryTap: focusEntry
            )
            .id(currentTimeMarkerID)

            if let quickDetailEntry {
                TimelineQuickDetail(entry: quickDetailEntry) {
                    self.quickDetailEntry = nil
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            timelineHeader

            Picker("表示", selection: $selectedTabRawValue) {
                ForEach(TimelineTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.systemImage)
                        .tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("タイムライン表示")

            TimelineEntryList(
                entries: selected,
                highlightedEntryID: highlightedEntryID,
                onEntryTap: handleEntryTap,
                onGapTap: handleGapTap,
                canCreateGap: canCreateGap,
                onToggleVisibility: toggleVisibility,
                canDeleteEntry: canDeleteEntry,
                onDeleteEntry: deleteEntry
            )
        }
        .onAppear {
            clock.start()
            focusPlanIfNeeded()
        }
        .onDisappear {
            clock.stop()
        }
        .sheet(item: $editingPlan) { plan in
            PlanCreateSheet(plan: plan)
        }
        .sheet(isPresented: $showingChapterCreate) {
            ChapterCreateSheet(initialDate: gapStartDate)
        }
        .sheet(isPresented: $showingPlanCreate) {
            PlanCreateSheet(initialDate: gapStartDate)
        }
    }

    @ViewBuilder
    private var timelineHeader: some View {
        if !title.isEmpty {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private func focusEntry(_ entry: TimelineEntry) {
        selectedTabRawValue = entry.kind.tab.rawValue
        highlightedEntryID = entry.id
        quickDetailEntry = entry

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if highlightedEntryID == entry.id {
                highlightedEntryID = nil
            }
            if quickDetailEntry?.id == entry.id {
                quickDetailEntry = nil
            }
        }
    }

    private func focusPlanIfNeeded() {
        guard let focusedPlanID else { return }
        DispatchQueue.main.async {
            guard let entry = planEntries.first(where: { $0.plan?.id == focusedPlanID }) else { return }
            focusEntry(entry)
        }
    }

    private func handleEntryTap(_ entry: TimelineEntry) {
        if let chapter = entry.chapter {
            editingChapter = chapter
        } else if let plan = entry.plan {
            editingPlan = plan
        } else {
            quickDetailEntry = entry
        }
    }

    private func handleGapTap(_ entry: TimelineEntry) {
        guard canCreateGap(entry) else { return }
        switch selectedTab {
        case .actual:
            gapStartDate = defaultChapterStart(for: entry)
            showingChapterCreate = true
        case .plan:
            gapStartDate = entry.clippedStart
            showingPlanCreate = true
        }
    }

    private func canCreateGap(_ entry: TimelineEntry) -> Bool {
        switch entry.kind {
        case .gap(.actual):
            let current = Date()
            guard entry.clippedStart < current else { return false }
            let start = defaultChapterStart(for: entry)
            return allowsChapterCreation
                && store.canCreateChapter(
                    startTime: start,
                    endTime: min(entry.clippedEnd, current)
                )
        case .gap(.plan):
            return allowsPlanCreation && store.canCreatePlan(startTime: entry.clippedStart, isAllDay: false)
        default:
            return false
        }
    }

    private func toggleVisibility(_ entry: TimelineEntry) {
        guard let chapter = entry.chapter else { return }
        store.setChapterVisibility(chapter, isPublic: !chapter.isPublic)
    }

    private func deleteEntry(_ entry: TimelineEntry) {
        if let chapter = entry.chapter {
            store.deleteChapter(chapter)
        } else if let plan = entry.plan {
            store.deletePlanBlock(plan)
        }
    }

    private func canDeleteEntry(_ entry: TimelineEntry) -> Bool {
        if let chapter = entry.chapter {
            return !store.isChapterTimeLocked(chapter)
        }
        if let plan = entry.plan {
            return !store.isPlanScheduleLocked(plan)
        }
        return false
    }

    private func defaultChapterStart(for entry: TimelineEntry) -> Date {
        let current = Date()
        let latestValidStart = Calendar.current.date(byAdding: .minute, value: -1, to: current) ?? current
        return max(dayStart, min(entry.clippedStart, latestValidStart))
    }

}

struct TimelineDisplaySnapshot: Identifiable, Hashable {
    let id: String
    let sourceID: UUID?
    let start: Date
    let end: Date
    let title: String
    let subtitle: String?
    let categoryName: String
    let categoryIconName: String
    let categoryColorHex: String
    let isActive: Bool
    let note: String?
    let mood: String?
    let locationName: String?
    let plannedMatchTitle: String?

    init(
        id: String,
        sourceID: UUID? = nil,
        start: Date,
        end: Date,
        title: String,
        subtitle: String? = nil,
        categoryName: String? = nil,
        categoryIconName: String,
        categoryColorHex: String,
        isActive: Bool = false,
        note: String? = nil,
        mood: String? = nil,
        locationName: String? = nil,
        plannedMatchTitle: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.start = start
        self.end = end
        self.title = title
        self.subtitle = subtitle
        self.categoryName = categoryName ?? title
        self.categoryIconName = categoryIconName
        self.categoryColorHex = categoryColorHex
        self.isActive = isActive
        self.note = note
        self.mood = mood
        self.locationName = locationName
        self.plannedMatchTitle = plannedMatchTitle
    }
}

struct SharedTimelineReadOnlyView: View {
    let date: Date
    let title: String
    let planSnapshots: [TimelineDisplaySnapshot]
    let actualSnapshots: [TimelineDisplaySnapshot]

    @State private var selectedTabRawValue = TimelineTab.actual.rawValue
    @State private var clock = TickClock(interval: 60)
    @State private var highlightedEntryID: String?
    @State private var quickDetailEntry: TimelineEntry?

    private var now: Date {
        clock.now
    }

    private var selectedTab: TimelineTab {
        TimelineTab(rawValue: selectedTabRawValue) ?? .actual
    }

    private var selectedEntries: [TimelineEntry] {
        switch selectedTab {
        case .plan:
            planEntries
        case .actual:
            actualEntries
        }
    }

    private var actualEntries: [TimelineEntry] {
        entries(from: actualSnapshots, kind: .actual, tab: .actual)
    }

    private var planEntries: [TimelineEntry] {
        entries(from: planSnapshots, kind: .plan, tab: .plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                }
            }

            DayOverviewBar(
                date: date,
                now: now,
                planEntries: planEntries.filter { !$0.kind.isGap },
                actualEntries: actualEntries.filter { !$0.kind.isGap },
                onEntryTap: focusEntry
            )

            if let quickDetailEntry {
                TimelineQuickDetail(entry: quickDetailEntry) {
                    self.quickDetailEntry = nil
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Picker("表示", selection: $selectedTabRawValue) {
                ForEach(TimelineTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.systemImage)
                        .tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("タイムライン表示")

            TimelineEntryList(
                entries: selectedEntries,
                highlightedEntryID: highlightedEntryID,
                allowsContextMenu: false,
                onEntryTap: focusEntry,
                onGapTap: { _ in },
                canCreateGap: { _ in false },
                onToggleVisibility: { _ in },
                canDeleteEntry: { _ in false },
                onDeleteEntry: { _ in }
            )
        }
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
    }

    private func focusEntry(_ entry: TimelineEntry) {
        guard !entry.kind.isGap else { return }
        selectedTabRawValue = entry.kind.tab.rawValue
        highlightedEntryID = entry.id
        quickDetailEntry = entry

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if highlightedEntryID == entry.id {
                highlightedEntryID = nil
            }
            if quickDetailEntry?.id == entry.id {
                quickDetailEntry = nil
            }
        }
    }
}

// MARK: - Entry building

private extension TimelineView {
    var dayStart: Date {
        DayBoundary.dayStart(for: date)
    }

    var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    func entries(for chapters: [Chapter], tab: TimelineTab) -> [TimelineEntry] {
        let eventEntries = chapters.compactMap { makeActualEntry($0) }
            .sorted { $0.clippedStart < $1.clippedStart }
        return mergeWithGaps(eventEntries, tab: tab)
    }

    func entries(for plans: [PlanBlock], tab: TimelineTab) -> [TimelineEntry] {
        let eventEntries = plans.compactMap { makePlanEntry($0) }
            .sorted { $0.clippedStart < $1.clippedStart }
        return mergeWithGaps(eventEntries, tab: tab)
    }

    func makeActualEntry(_ chapter: Chapter) -> TimelineEntry? {
        let rawEnd = chapter.endTime ?? now
        guard chapter.startTime < dayEnd, rawEnd >= dayStart else { return nil }
        let clippedStart = max(chapter.startTime, dayStart)
        let clippedEnd = min(rawEnd, dayEnd)
        guard clippedEnd >= clippedStart else { return nil }

        let category = chapter.category
        let colorHex = category?.colorHex ?? "#8E8E93"
        let matchedPlan = matchingPlan(for: chapter, endingAt: rawEnd)
        return TimelineEntry(
            id: "actual:\(chapter.id.uuidString)",
            kind: .actual,
            sourceID: chapter.id,
            start: chapter.startTime,
            end: rawEnd,
            clippedStart: clippedStart,
            clippedEnd: clippedEnd,
            title: category?.name ?? "未分類",
            subtitle: nil,
            categoryName: category?.name ?? "未分類",
            categoryIconName: category?.icon ?? "circle.fill",
            categoryColorHex: colorHex,
            isActive: chapter.isActive,
            chapter: chapter,
            plan: nil,
            metadata: TimelineEntryMetadata(
                note: chapter.note,
                mood: chapter.mood,
                locationName: chapter.locationName,
                plannedMatchTitle: matchedPlan.map { $0.category?.name ?? $0.title },
                isShort: rawEnd.timeIntervalSince(chapter.startTime) < 60,
                continuesFromPreviousDay: chapter.startTime < dayStart,
                continuesToNextDay: chapter.endTime == nil || rawEnd > dayEnd
            )
        )
    }

    func makePlanEntry(_ plan: PlanBlock) -> TimelineEntry? {
        guard plan.startTime < dayEnd, plan.endTime > dayStart else { return nil }
        let clippedStart = max(plan.startTime, dayStart)
        let clippedEnd = min(plan.endTime, dayEnd)
        guard clippedEnd > clippedStart else { return nil }

        let category = plan.category
        let title = category?.name ?? plan.title
        let subtitle = category == nil || plan.title == title ? nil : plan.title
        return TimelineEntry(
            id: "plan:\(plan.id.uuidString)",
            kind: .plan,
            sourceID: plan.id,
            start: plan.startTime,
            end: plan.endTime,
            clippedStart: clippedStart,
            clippedEnd: clippedEnd,
            title: title,
            subtitle: subtitle,
            categoryName: title,
            categoryIconName: category?.icon ?? "calendar",
            categoryColorHex: category?.colorHex ?? "#8E8E93",
            isActive: false,
            chapter: nil,
            plan: plan,
            metadata: TimelineEntryMetadata(
                note: plan.note,
                mood: nil,
                locationName: nil,
                plannedMatchTitle: nil,
                isShort: plan.endTime.timeIntervalSince(plan.startTime) < 60,
                continuesFromPreviousDay: plan.startTime < dayStart,
                continuesToNextDay: plan.endTime > dayEnd
            )
        )
    }

    func mergeWithGaps(_ events: [TimelineEntry], tab: TimelineTab) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var cursor = dayStart
        let minimumGapDuration: TimeInterval = 5 * 60

        for event in events {
            if event.clippedStart.timeIntervalSince(cursor) >= minimumGapDuration {
                entries.append(gapEntry(tab: tab, start: cursor, end: event.clippedStart))
            }
            entries.append(event)
            cursor = max(cursor, event.clippedEnd)
        }

        if dayEnd.timeIntervalSince(cursor) >= minimumGapDuration {
            entries.append(gapEntry(tab: tab, start: cursor, end: dayEnd))
        }

        if entries.isEmpty {
            entries.append(gapEntry(tab: tab, start: dayStart, end: dayEnd))
        }

        return entries
    }

    func gapEntry(tab: TimelineTab, start: Date, end: Date) -> TimelineEntry {
        let label = tab == .plan ? "未予定" : "未記録"
        return TimelineEntry(
            id: "gap:\(tab.rawValue):\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))",
            kind: .gap(tab),
            sourceID: nil,
            start: start,
            end: end,
            clippedStart: start,
            clippedEnd: end,
            title: label,
            subtitle: nil,
            categoryName: label,
            categoryIconName: tab == .plan ? "calendar" : "clock",
            categoryColorHex: "#8E8E93",
            isActive: false,
            chapter: nil,
            plan: nil,
            metadata: TimelineEntryMetadata(
                note: nil,
                mood: nil,
                locationName: nil,
                plannedMatchTitle: nil,
                isShort: false,
                continuesFromPreviousDay: false,
                continuesToNextDay: false
            )
        )
    }

    func matchingPlan(for chapter: Chapter, endingAt rawEnd: Date) -> PlanBlock? {
        guard let categoryID = chapter.category?.id else { return nil }
        return timelinePlans
            .filter { plan in
                plan.category?.id == categoryID
                    && plan.startTime < rawEnd
                    && plan.endTime > chapter.startTime
            }
            .max { lhs, rhs in
                overlapDuration(chapterStart: chapter.startTime, chapterEnd: rawEnd, plan: lhs)
                    < overlapDuration(chapterStart: chapter.startTime, chapterEnd: rawEnd, plan: rhs)
            }
    }

    func overlapDuration(chapterStart: Date, chapterEnd: Date, plan: PlanBlock) -> TimeInterval {
        let start = max(chapterStart, plan.startTime)
        let end = min(chapterEnd, plan.endTime)
        return max(end.timeIntervalSince(start), 0)
    }
}

private extension SharedTimelineReadOnlyView {
    var dayStart: Date {
        DayBoundary.dayStart(for: date)
    }

    var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    func entries(from snapshots: [TimelineDisplaySnapshot], kind: TimelineEntryKind, tab: TimelineTab) -> [TimelineEntry] {
        let eventEntries = snapshots.compactMap { entry(from: $0, kind: kind) }
            .sorted {
                if $0.clippedStart == $1.clippedStart {
                    return $0.clippedEnd < $1.clippedEnd
                }
                return $0.clippedStart < $1.clippedStart
            }
        return mergeWithGaps(eventEntries, tab: tab)
    }

    func entry(from snapshot: TimelineDisplaySnapshot, kind: TimelineEntryKind) -> TimelineEntry? {
        guard snapshot.start < dayEnd, snapshot.end > dayStart else { return nil }
        let clippedStart = max(snapshot.start, dayStart)
        let clippedEnd = min(snapshot.end, dayEnd)
        guard clippedEnd > clippedStart else { return nil }

        return TimelineEntry(
            id: snapshot.id,
            kind: kind,
            sourceID: snapshot.sourceID,
            start: snapshot.start,
            end: snapshot.end,
            clippedStart: clippedStart,
            clippedEnd: clippedEnd,
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            categoryName: snapshot.categoryName,
            categoryIconName: snapshot.categoryIconName,
            categoryColorHex: snapshot.categoryColorHex,
            isActive: snapshot.isActive,
            chapter: nil,
            plan: nil,
            metadata: TimelineEntryMetadata(
                note: snapshot.note,
                mood: snapshot.mood,
                locationName: snapshot.locationName,
                plannedMatchTitle: snapshot.plannedMatchTitle,
                isShort: snapshot.end.timeIntervalSince(snapshot.start) < 60,
                continuesFromPreviousDay: snapshot.start < dayStart,
                continuesToNextDay: snapshot.end > dayEnd
            )
        )
    }

    func mergeWithGaps(_ events: [TimelineEntry], tab: TimelineTab) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var cursor = dayStart
        let minimumGapDuration: TimeInterval = 5 * 60

        for event in events {
            if event.clippedStart.timeIntervalSince(cursor) >= minimumGapDuration {
                entries.append(gapEntry(tab: tab, start: cursor, end: event.clippedStart))
            }
            entries.append(event)
            cursor = max(cursor, event.clippedEnd)
        }

        if dayEnd.timeIntervalSince(cursor) >= minimumGapDuration {
            entries.append(gapEntry(tab: tab, start: cursor, end: dayEnd))
        }

        if entries.isEmpty {
            entries.append(gapEntry(tab: tab, start: dayStart, end: dayEnd))
        }

        return entries
    }

    func gapEntry(tab: TimelineTab, start: Date, end: Date) -> TimelineEntry {
        let label = tab == .plan ? "未予定" : "未記録"
        return TimelineEntry(
            id: "readonly-gap:\(tab.rawValue):\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))",
            kind: .gap(tab),
            sourceID: nil,
            start: start,
            end: end,
            clippedStart: start,
            clippedEnd: end,
            title: label,
            subtitle: nil,
            categoryName: label,
            categoryIconName: tab == .plan ? "calendar" : "clock",
            categoryColorHex: "#8E8E93",
            isActive: false,
            chapter: nil,
            plan: nil,
            metadata: TimelineEntryMetadata(
                note: nil,
                mood: nil,
                locationName: nil,
                plannedMatchTitle: nil,
                isShort: false,
                continuesFromPreviousDay: false,
                continuesToNextDay: false
            )
        )
    }
}

// MARK: - 24 hour overview

private struct DayOverviewBar: View {
    let date: Date
    let now: Date
    let planEntries: [TimelineEntry]
    let actualEntries: [TimelineEntry]
    var onEntryTap: (TimelineEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("24時間バー")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 7) {
                TimelineBarRow(
                    tab: .plan,
                    date: date,
                    now: now,
                    entries: planEntries,
                    onEntryTap: onEntryTap
                )
                TimelineBarRow(
                    tab: .actual,
                    date: date,
                    now: now,
                    entries: actualEntries,
                    onEntryTap: onEntryTap
                )
            }

            TimelineHourScale()
                .padding(.leading, 38)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct TimelineBarRow: View {
    let tab: TimelineTab
    let date: Date
    let now: Date
    let entries: [TimelineEntry]
    var onEntryTap: (TimelineEntry) -> Void

    private var dayStart: Date {
        DayBoundary.dayStart(for: date)
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(tab.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemGroupedBackground))

                    ForEach(entries) { entry in
                        let segmentWidth = segmentWidth(for: entry, width: width)
                        TimelineBarSegmentView(
                            entry: entry,
                            width: segmentWidth,
                            showsIcon: shouldShowIcon(entry: entry, width: segmentWidth)
                        )
                        .frame(width: max(segmentWidth, 28), height: 18, alignment: .leading)
                        .offset(x: xOffset(for: entry.clippedStart, width: width))
                        .onTapGesture {
                            onEntryTap(entry)
                        }
                    }

                    if Calendar.current.isDateInToday(date) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 22)
                            .offset(x: xOffset(for: min(max(now, dayStart), dayEnd), width: width))
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)
        }
    }

    private func xOffset(for target: Date, width: CGFloat) -> CGFloat {
        let clipped = min(max(target, dayStart), dayEnd)
        let ratio = clipped.timeIntervalSince(dayStart) / dayEnd.timeIntervalSince(dayStart)
        return max(0, min(width, width * ratio))
    }

    private func segmentWidth(for entry: TimelineEntry, width: CGFloat) -> CGFloat {
        let duration = max(entry.clippedEnd.timeIntervalSince(entry.clippedStart), 60)
        let ratio = duration / dayEnd.timeIntervalSince(dayStart)
        return max(width * ratio, 1)
    }

    private func shouldShowIcon(entry: TimelineEntry, width: CGFloat) -> Bool {
        entry.clippedDuration >= 15 * 60 && width >= 24
    }

}

private struct TimelineBarSegmentView: View {
    let entry: TimelineEntry
    let width: CGFloat
    let showsIcon: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(entry.color)
                .frame(width: width, height: 18)

            if showsIcon {
                Image(systemName: entry.categoryIconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: min(width, 18), height: 18)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(entry.title) \(entry.timeRangeText) \(entry.durationText)")
    }
}

private struct TimelineHourScale: View {
    private let marks = Array(stride(from: 0, through: 24, by: 3))

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { hour in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.4))
                            .frame(width: 1, height: 5)
                        Text("\(hour)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 24)
                    .offset(x: xOffset(hour: hour, width: proxy.size.width) - 12)
                }
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private func xOffset(hour: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(hour) / 24
    }
}

// MARK: - Cards

private struct TimelineEntryList: View {
    let entries: [TimelineEntry]
    let highlightedEntryID: String?
    var allowsContextMenu = true
    var onEntryTap: (TimelineEntry) -> Void
    var onGapTap: (TimelineEntry) -> Void
    var canCreateGap: (TimelineEntry) -> Bool
    var onToggleVisibility: (TimelineEntry) -> Void
    var canDeleteEntry: (TimelineEntry) -> Bool
    var onDeleteEntry: (TimelineEntry) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let connectsToPrevious = isContiguousWithPrevious(at: index)
                let connectsToNext = isContiguousWithNext(at: index)
                let showStartTime = !connectsToPrevious
                let showEndTime = index + 1 < entries.count
                if entry.kind.isGap {
                    if canCreateGap(entry) {
                        Button {
                            onGapTap(entry)
                        } label: {
                            TimelineEntryRow(
                                entry: entry,
                                isHighlighted: false,
                                showsStartTime: showStartTime,
                                showsEndTime: showEndTime,
                                connectsToPrevious: connectsToPrevious,
                                connectsToNext: connectsToNext
                            ) {
                                TimelineGapCard(entry: entry, showsAddIcon: true)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    } else {
                        TimelineEntryRow(
                            entry: entry,
                            isHighlighted: false,
                            showsStartTime: showStartTime,
                            showsEndTime: showEndTime,
                            connectsToPrevious: connectsToPrevious,
                            connectsToNext: connectsToNext
                        ) {
                            TimelineGapCard(entry: entry, showsAddIcon: false)
                        }
                        .id(entry.id)
                    }
                } else {
                    Button {
                        onEntryTap(entry)
                    } label: {
                        TimelineEntryRow(
                            entry: entry,
                            isHighlighted: highlightedEntryID == entry.id,
                            showsStartTime: showStartTime,
                            showsEndTime: showEndTime,
                            connectsToPrevious: connectsToPrevious,
                            connectsToNext: connectsToNext
                        ) {
                            TimelineEntryCard(entry: entry, isHighlighted: highlightedEntryID == entry.id)
                        }
                    }
                    .buttonStyle(.plain)
                    .id(entry.id)
                    .modifier(TimelineContextMenuModifier(
                        entry: entry,
                        isEnabled: allowsContextMenu,
                        onEntryTap: onEntryTap,
                        onToggleVisibility: onToggleVisibility,
                        canDeleteEntry: canDeleteEntry,
                        onDeleteEntry: onDeleteEntry
                    ))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func isContiguousWithPrevious(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return areContiguous(entries[index - 1], entries[index])
    }

    private func isContiguousWithNext(at index: Int) -> Bool {
        guard index + 1 < entries.count else { return false }
        return areContiguous(entries[index], entries[index + 1])
    }

    private func areContiguous(_ lhs: TimelineEntry, _ rhs: TimelineEntry) -> Bool {
        Calendar.current.isDate(lhs.clippedEnd, equalTo: rhs.clippedStart, toGranularity: .minute)
    }
}

private struct TimelineContextMenuModifier: ViewModifier {
    let entry: TimelineEntry
    let isEnabled: Bool
    var onEntryTap: (TimelineEntry) -> Void
    var onToggleVisibility: (TimelineEntry) -> Void
    var canDeleteEntry: (TimelineEntry) -> Bool
    var onDeleteEntry: (TimelineEntry) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                if entry.chapter != nil {
                    Button {
                        onEntryTap(entry)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                    Button {
                        onToggleVisibility(entry)
                    } label: {
                        Label(
                            entry.chapter?.isPublic == true ? "非公開にする" : "公開する",
                            systemImage: entry.chapter?.isPublic == true ? "eye.slash" : "eye"
                        )
                    }
                } else if entry.plan != nil {
                    Button {
                        onEntryTap(entry)
                    } label: {
                        Label("編集", systemImage: "pencil")
                    }
                }
                if canDeleteEntry(entry) {
                    Button(role: .destructive) {
                        onDeleteEntry(entry)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } else {
                    Label("削除できません", systemImage: "lock.fill")
                }
            }
        } else {
            content
        }
    }
}

private enum TimelineCardMetrics {
    static let entryHeight: CGFloat = 62
    static let gapHeight: CGFloat = 48
    static let rowVerticalPadding: CGFloat = 5
}

private struct TimelineEntryRow<Content: View>: View {
    let entry: TimelineEntry
    let isHighlighted: Bool
    let showsStartTime: Bool
    let showsEndTime: Bool
    let connectsToPrevious: Bool
    let connectsToNext: Bool
    let content: () -> Content

    init(
        entry: TimelineEntry,
        isHighlighted: Bool,
        showsStartTime: Bool = true,
        showsEndTime: Bool = true,
        connectsToPrevious: Bool = false,
        connectsToNext: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.entry = entry
        self.isHighlighted = isHighlighted
        self.showsStartTime = showsStartTime
        self.showsEndTime = showsEndTime
        self.connectsToPrevious = connectsToPrevious
        self.connectsToNext = connectsToNext
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TimelineTimeRail(
                entry: entry,
                height: rowHeight,
                isHighlighted: isHighlighted,
                showsStartTime: showsStartTime,
                showsEndTime: showsEndTime,
                connectsToPrevious: connectsToPrevious,
                connectsToNext: connectsToNext
            )
            content()
                .padding(.vertical, TimelineCardMetrics.rowVerticalPadding)
        }
    }

    private var rowHeight: CGFloat {
        let cardHeight = entry.kind.isGap ? TimelineCardMetrics.gapHeight : TimelineCardMetrics.entryHeight
        return cardHeight + TimelineCardMetrics.rowVerticalPadding * 2
    }
}

private struct TimelineTimeRail: View {
    let entry: TimelineEntry
    let height: CGFloat
    let isHighlighted: Bool
    let showsStartTime: Bool
    let showsEndTime: Bool
    let connectsToPrevious: Bool
    let connectsToNext: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if showsStartTime {
                    Text(entry.clippedStart.shortTime)
                        .timelineBoundaryTimeStyle()
                        .frame(width: 42, height: 14, alignment: .trailing)
                        .position(x: 21, y: topBoundaryY)
                }

                if showsEndTime {
                    Text(entry.clippedEnd.shortTime)
                        .timelineBoundaryTimeStyle()
                        .frame(width: 42, height: 14, alignment: .trailing)
                        .position(x: 21, y: bottomBoundaryY)
                }
            }
            .frame(width: 42, height: height)

            ZStack {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: lineWidth)
                    .frame(height: lineHeight)
                    .position(x: 4, y: lineMidY)

                if showsStartTime {
                    Circle()
                        .fill(startMarkerColor)
                        .frame(width: 7, height: 7)
                        .position(x: 4, y: topBoundaryY)
                }

                Circle()
                    .strokeBorder(endMarkerColor, lineWidth: entry.kind.isGap ? 1.4 : 1.6)
                    .background(Circle().fill(Color(.systemGroupedBackground)))
                    .frame(width: 7, height: 7)
                    .position(x: 4, y: bottomBoundaryY)
            }
            .frame(width: 8, height: height)
        }
        .frame(width: 56, height: height)
        .accessibilityHidden(true)
    }

    private var railColor: Color {
        if entry.kind.isGap {
            return Color(.separator)
        }
        return entry.isActive || isHighlighted ? entry.color : entry.color.opacity(0.78)
    }

    private var topBoundaryY: CGFloat {
        TimelineCardMetrics.rowVerticalPadding
    }

    private var bottomBoundaryY: CGFloat {
        height - TimelineCardMetrics.rowVerticalPadding
    }

    private var lineStartY: CGFloat {
        connectsToPrevious ? 0 : topBoundaryY
    }

    private var lineEndY: CGFloat {
        connectsToNext ? height : bottomBoundaryY
    }

    private var lineHeight: CGFloat {
        max(lineEndY - lineStartY, 0)
    }

    private var lineMidY: CGFloat {
        lineStartY + lineHeight / 2
    }

    private var lineColor: Color {
        if entry.kind.isGap {
            return Color(.separator).opacity(0.34)
        }
        return railColor.opacity(entry.isActive || isHighlighted ? 0.58 : 0.42)
    }

    private var lineWidth: CGFloat {
        entry.kind.isGap ? 1.7 : 2.4
    }

    private var startMarkerColor: Color {
        if entry.kind.isGap {
            return Color(.separator).opacity(0.5)
        }
        return railColor
    }

    private var endMarkerColor: Color {
        if entry.kind.isGap {
            return Color(.separator).opacity(0.55)
        }
        return railColor.opacity(0.82)
    }

}

private extension Text {
    func timelineBoundaryTimeStyle() -> some View {
        self
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TimelineEntryCard: View {
    let entry: TimelineEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.categoryIconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(entry.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if entry.metadata.plannedMatchTitle != nil {
                        TimelineMatchIndicator(tint: entry.color)
                    }

                    Spacer(minLength: 8)

                    Text(entry.durationText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                supplementalLine
            }
        }
        .frame(height: TimelineCardMetrics.entryHeight)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(backgroundColor)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entry.color)
                .frame(width: 4, height: TimelineCardMetrics.entryHeight - 14)
                .padding(.leading, 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(borderColor, lineWidth: entry.isActive || isHighlighted ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.18), value: isHighlighted)
        .animation(.easeInOut(duration: 0.18), value: entry.isActive)
        .accessibilityElement(children: .combine)
    }

    private var backgroundColor: Color {
        switch entry.kind {
        case .plan:
            return entry.color.opacity(0.06)
        case .actual:
            return entry.color.opacity(entry.isActive ? 0.15 : 0.08)
        case .gap:
            return Color(.tertiarySystemGroupedBackground)
        }
    }

    private var borderColor: Color {
        if entry.isActive || isHighlighted {
            return entry.color
        }
        return Color(.separator).opacity(0.18)
    }

    @ViewBuilder
    private var supplementalLine: some View {
        let items = metadataItems
        if !items.isEmpty {
            HStack(spacing: 7) {
                ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in
                    Label(item.text, systemImage: item.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if items.count > 2 {
                    Text("+\(items.count - 2)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metadataItems: [(icon: String, text: String)] {
        var items: [(icon: String, text: String)] = []
        if let subtitle = entry.subtitle, !subtitle.isEmpty {
            items.append(("text.alignleft", subtitle))
        }
        if let note = entry.metadata.note, !note.isEmpty {
            items.append(("text.bubble", note))
        }
        if let location = entry.metadata.locationName, !location.isEmpty {
            items.append(("mappin.and.ellipse", location))
        }
        return items
    }
}

private struct TimelineGapCard: View {
    let entry: TimelineEntry
    var showsAddIcon = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.categoryIconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 28)

            Text(entry.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            if showsAddIcon {
                Label("追加", systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
            }
        }
        .frame(height: TimelineCardMetrics.gapHeight)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(.tertiarySystemGroupedBackground).opacity(0.72))
        )
        .accessibilityLabel(showsAddIcon ? "\(entry.title) \(entry.timeRangeText) 追加" : "\(entry.title) \(entry.timeRangeText)")
    }
}

private struct TimelineMatchIndicator: View {
    let tint: Color

    var body: some View {
        Label("予定通り", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(0.1))
            )
            .lineLimit(1)
    }
}

private struct TimelineQuickDetail: View {
    let entry: TimelineEntry
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.categoryIconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(entry.color)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text("\(entry.timeRangeText)  \(entry.durationText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private func displayDuration(_ seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "0分" }
    guard seconds >= 60 else { return "1分未満" }
    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
        return "\(hours)時間\(minutes)分"
    } else if hours > 0 {
        return "\(hours)時間"
    } else {
        return "\(minutes)分"
    }
}

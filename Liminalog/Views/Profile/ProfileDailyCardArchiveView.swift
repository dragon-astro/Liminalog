import SwiftData
import SwiftUI

struct ProfileDailyCardArchivePagerView: View {
    @Environment(\.modelContext) private var modelContext

    let entries: [ProfileDailyCardEntry]
    @State private var scrolledEntryID: ProfileDailyCardEntry.ID?
    @State private var payloadsByDayIdentifier: [String: DailyReflectionPayload] = [:]
    @State private var persistedSnapshotSignatures: Set<String> = []

    init(entries: [ProfileDailyCardEntry], initialEntry: ProfileDailyCardEntry) {
        let sortedEntries = entries.sorted { $0.dayStart > $1.dayStart }
        self.entries = sortedEntries
        let initialID = sortedEntries.first { $0.id == initialEntry.id }?.id ?? sortedEntries.first?.id
        _scrolledEntryID = State(initialValue: initialID)
    }

    private var selectedEntry: ProfileDailyCardEntry? {
        guard let scrolledEntryID else { return entries.first }
        return entries.first { $0.id == scrolledEntryID } ?? entries.first
    }

    private var selectedIndex: Int? {
        guard let selectedEntry else { return nil }
        return entries.firstIndex { $0.id == selectedEntry.id }
    }

    private var progressText: String {
        guard let selectedIndex else { return "" }
        return "\(selectedIndex + 1) / \(entries.count)"
    }

    var body: some View {
        ZStack {
            LiminalTheme.canvasGradient.ignoresSafeArea()

            if entries.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(entries) { entry in
                            ProfileDailyCardArchivePageSlot(
                                entry: entry,
                                payload: payload(for: entry),
                                isActive: entry.id == selectedEntry?.id,
                                isPageSwipeActive: false,
                                onPersistSnapshot: persistSnapshotIfNeeded
                            )
                            .containerRelativeFrame(.horizontal)
                            .accessibilityHidden(entry.id != selectedEntry?.id)
                            .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledEntryID, anchor: .center)
                .defaultScrollAnchor(.center)
                .scrollIndicators(.hidden)
                .scrollDisabled(entries.count <= 1)
                .contentShape(Rectangle())
                .onAppear {
                    if scrolledEntryID == nil {
                        scrolledEntryID = entries.first?.id
                    }
                    refreshPayloadCache()
                }
                .task(id: payloadWindowSignature) {
                    refreshPayloadCache()
                }
                .ignoresSafeArea(edges: [.top, .bottom])
            }
        }
        .navigationTitle(selectedEntry?.dayStart.japaneseMonthDayShortWeekday ?? "デイリーカード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .bottom) {
            if entries.count > 1 {
                Text(progressText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(LiminalTheme.divider.opacity(0.5), lineWidth: 1)
                    }
                    .padding(.bottom, 14)
            }
        }
    }

    private func payload(for entry: ProfileDailyCardEntry) -> DailyReflectionPayload? {
        payloadsByDayIdentifier[entry.dayIdentifier]
    }

    private var payloadWindowEntries: [ProfileDailyCardEntry] {
        guard let selectedIndex else { return Array(entries.prefix(2)) }
        let lowerBound = max(entries.startIndex, selectedIndex - 1)
        let upperBound = min(entries.endIndex - 1, selectedIndex + 1)
        return Array(entries[lowerBound...upperBound])
    }

    private var payloadWindowSignature: String {
        payloadWindowEntries
            .map { entry in
                [
                    entry.dayIdentifier,
                    "\(entry.score)",
                    "\(Int(entry.plannedDuration.rounded()))",
                    "\(Int(entry.recordedDuration.rounded()))"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    @MainActor
    private func refreshPayloadCache() {
        let windowEntries = payloadWindowEntries
        guard !windowEntries.isEmpty else {
            payloadsByDayIdentifier = [:]
            return
        }

        let now = Date()
        var nextPayloads = payloadsByDayIdentifier
        let activeDayIdentifiers = Set(windowEntries.map(\.dayIdentifier))

        for entry in windowEntries {
            let boundary = DayBoundary(date: entry.dayStart, calendar: .japanese)
            let lookbackStart = Calendar.japanese.date(byAdding: .day, value: -28, to: boundary.dayStart) ?? boundary.dayStart
            let plans = fetchPlans(start: boundary.dayStart, end: boundary.dayEnd)
            let chapters = fetchChapters(start: lookbackStart, end: boundary.dayEnd)
            nextPayloads[entry.dayIdentifier] = DailyReflectionPayload.make(
                date: entry.dayStart,
                queriedPlans: plans,
                queriedChapters: chapters,
                now: now
            )
        }

        payloadsByDayIdentifier = nextPayloads.filter { activeDayIdentifiers.contains($0.key) }
    }

    @MainActor
    private func fetchPlans(start: Date, end: Date) -> [PlanBlock] {
        let descriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate {
                $0.startTime < end && $0.endTime > start
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card archive plans: \(String(describing: error))")
            return []
        }
    }

    @MainActor
    private func fetchChapters(start: Date, end: Date) -> [Chapter] {
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate {
                $0.startTime >= start && $0.startTime < end
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch daily card archive chapters: \(String(describing: error))")
            return []
        }
    }

    @MainActor
    private func persistSnapshotIfNeeded(_ payload: DailyReflectionPayload) {
        let signature = payload.snapshotSignature
        guard !persistedSnapshotSignatures.contains(signature) else { return }
        persistedSnapshotSignatures.insert(signature)
        DailyCardSnapshotStore(modelContext: modelContext).upsert(
            date: payload.date,
            summary: payload.summary,
            persona: payload.persona,
            categoryRows: payload.categoryRows,
            recordedDuration: payload.recordedDuration
        )
    }
}

private struct ProfileDailyCardArchivePageSlot: View {
    let entry: ProfileDailyCardEntry
    let payload: DailyReflectionPayload?
    let isActive: Bool
    let isPageSwipeActive: Bool
    let onPersistSnapshot: (DailyReflectionPayload) -> Void

    var body: some View {
        if let payload {
            ProfileDailyCardArchivePayloadDetailView(
                payload: payload,
                showsNavigationTitle: false,
                isPageSwipeActive: isPageSwipeActive,
                extendsUnderSystemChrome: true,
                persistsSnapshot: isActive,
                onPersistSnapshot: onPersistSnapshot
            )
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        } else if isActive {
            ProfileDailyCardArchiveDetailView(
                entry: entry,
                showsNavigationTitle: false,
                isPageSwipeActive: isPageSwipeActive,
                extendsUnderSystemChrome: true,
                persistsSnapshot: isActive
            )
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        } else {
            LiminalTheme.canvasGradient.ignoresSafeArea()
        }
    }
}

struct ProfileDailyCardArchiveDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]

    let entry: ProfileDailyCardEntry
    let showsNavigationTitle: Bool
    let isPageSwipeActive: Bool
    let extendsUnderSystemChrome: Bool
    let persistsSnapshot: Bool

    init(
        entry: ProfileDailyCardEntry,
        showsNavigationTitle: Bool = true,
        isPageSwipeActive: Bool = false,
        extendsUnderSystemChrome: Bool = false,
        persistsSnapshot: Bool = true
    ) {
        self.entry = entry
        self.showsNavigationTitle = showsNavigationTitle
        self.isPageSwipeActive = isPageSwipeActive
        self.extendsUnderSystemChrome = extendsUnderSystemChrome
        self.persistsSnapshot = persistsSnapshot
        let boundary = DayBoundary(date: entry.dayStart, calendar: .japanese)
        let dayStart = boundary.dayStart
        let dayEnd = boundary.dayEnd
        let chapterLookbackStart = Calendar.japanese.date(byAdding: .day, value: -28, to: dayStart) ?? dayStart
        _queriedPlans = Query(
            filter: #Predicate<PlanBlock> {
                $0.startTime < dayEnd && $0.endTime > dayStart
            },
            sort: [SortDescriptor(\.startTime)]
        )
        _queriedChapters = Query(
            filter: #Predicate<Chapter> {
                $0.startTime >= chapterLookbackStart && $0.startTime < dayEnd
            },
            sort: [SortDescriptor(\.startTime)]
        )
    }

    var body: some View {
        let payload = DailyReflectionPayload.make(
            date: entry.dayStart,
            queriedPlans: queriedPlans,
            queriedChapters: queriedChapters
        )

        ProfileDailyCardArchivePayloadDetailView(
            payload: payload,
            showsNavigationTitle: showsNavigationTitle,
            isPageSwipeActive: isPageSwipeActive,
            extendsUnderSystemChrome: extendsUnderSystemChrome,
            persistsSnapshot: persistsSnapshot,
            onPersistSnapshot: persistDailyCardSnapshot
        )
    }

    @MainActor
    private func persistDailyCardSnapshot(_ payload: DailyReflectionPayload) {
        DailyCardSnapshotStore(modelContext: modelContext).upsert(
            date: payload.date,
            summary: payload.summary,
            persona: payload.persona,
            categoryRows: payload.categoryRows,
            recordedDuration: payload.recordedDuration
        )
    }
}

private struct ProfileDailyCardArchivePayloadDetailView: View {
    let payload: DailyReflectionPayload
    let showsNavigationTitle: Bool
    let isPageSwipeActive: Bool
    let extendsUnderSystemChrome: Bool
    let persistsSnapshot: Bool
    let onPersistSnapshot: (DailyReflectionPayload) -> Void

    var body: some View {
        if showsNavigationTitle {
            content
                .navigationTitle(payload.date.japaneseMonthDayShortWeekday)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            let topPadding = extendsUnderSystemChrome ? max(proxy.safeAreaInsets.top + 56, 116) : 12
            let bottomPadding = extendsUnderSystemChrome ? max(proxy.safeAreaInsets.bottom, 0) + 32 : 32

            ScrollView {
                VStack(spacing: 14) {
                    dailyCard
                }
                .frame(minHeight: max(proxy.size.height - topPadding - bottomPadding, 0), alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
            .scrollDisabled(isPageSwipeActive)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var dailyCard: some View {
        DailyReflectionPayloadCard(
            payload: payload,
            onPlanTomorrow: nil,
            onPersistSnapshot: persistsSnapshot ? onPersistSnapshot : nil
        )
        .equatable()
    }
}

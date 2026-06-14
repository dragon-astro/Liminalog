import SwiftData
import SwiftUI

struct ProfileDailyCardArchivePagerView: View {
    let entries: [ProfileDailyCardEntry]
    @State private var selectedID: ProfileDailyCardEntry.ID

    init(entries: [ProfileDailyCardEntry], initialEntry: ProfileDailyCardEntry) {
        self.entries = entries.sorted { $0.dayStart > $1.dayStart }
        _selectedID = State(initialValue: initialEntry.id)
    }

    private var selectedEntry: ProfileDailyCardEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    private var selectedIndex: Int? {
        entries.firstIndex { $0.id == selectedID }
    }

    private var progressText: String {
        guard let selectedIndex else { return "" }
        return "\(selectedIndex + 1) / \(entries.count)"
    }

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(entries) { entry in
                ProfileDailyCardArchiveDetailView(entry: entry, showsNavigationTitle: false)
                    .tag(entry.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(LiminalTheme.canvasGradient.ignoresSafeArea())
        .navigationTitle(selectedEntry?.dayStart.japaneseMonthDayShortWeekday ?? "デイリーカード")
        .navigationBarTitleDisplayMode(.inline)
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
}

struct ProfileDailyCardArchiveDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]

    let entry: ProfileDailyCardEntry
    let showsNavigationTitle: Bool

    init(entry: ProfileDailyCardEntry, showsNavigationTitle: Bool = true) {
        self.entry = entry
        self.showsNavigationTitle = showsNavigationTitle
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
        if showsNavigationTitle {
            content
                .navigationTitle(entry.dayStart.japaneseMonthDayShortWeekday)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                dailyCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(LiminalTheme.canvasGradient.ignoresSafeArea())
    }

    private var dailyCard: some View {
        DailyReflectionCard(
            date: entry.dayStart,
            summary: scoreSummary,
            chapters: dayChapters,
            historyChapters: historyChapters,
            plans: dayPlans,
            dayBoundary: dayBoundary,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            onPlanTomorrow: nil
        )
        .task(id: snapshotSignature) {
            persistDailyCardSnapshot()
        }
    }

    private var dayBoundary: DayBoundary {
        DayBoundary(date: entry.dayStart, calendar: .japanese)
    }

    private var dayPlans: [PlanBlock] {
        queriedPlans
            .filter { $0.startTime < dayBoundary.dayEnd && $0.endTime > dayBoundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var dayChapters: [Chapter] {
        let now = Date()
        return queriedChapters
            .filter { $0.startTime < dayBoundary.dayEnd && ($0.endTime ?? now) > dayBoundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private var historyChapters: [Chapter] {
        queriedChapters.sorted { $0.startTime < $1.startTime }
    }

    private var scoreSummary: ScoreSummary {
        ScoreCalculator.summary(
            date: entry.dayStart,
            plans: dayPlans,
            chapters: dayChapters,
            calendar: .japanese,
            now: Date()
        )
    }

    private var recordedDuration: TimeInterval {
        let now = Date()
        return dayChapters.reduce(0) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
            return partial + max(end.timeIntervalSince(start), 0)
        }
    }

    private var categoryRows: [(category: Category, duration: TimeInterval)] {
        let now = Date()
        let grouped = Dictionary(grouping: dayChapters.compactMap { chapter -> (Category, TimeInterval)? in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? now, dayBoundary.dayEnd)
            return (category, max(end.timeIntervalSince(start), 0))
        }, by: { $0.0.id })

        return grouped.compactMap { _, values in
            guard let category = values.first?.0 else { return nil }
            return (category, values.reduce(0) { $0 + $1.1 })
        }
        .sorted { $0.duration > $1.duration }
    }

    private var dailyPersona: DailyPersona {
        DailyPersona.make(
            summary: scoreSummary,
            chapters: dayChapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: dayBoundary
        )
    }

    private var snapshotSignature: String {
        [
            "\(dayBoundary.dayStart.timeIntervalSince1970)",
            "\(dayChapters.count)",
            "\(dayPlans.count)",
            "\(Int(recordedDuration.rounded()))",
            "\(Int(scoreSummary.totalScore.rounded()))"
        ].joined(separator: ":")
    }

    @MainActor
    private func persistDailyCardSnapshot() {
        DailyCardSnapshotStore(modelContext: modelContext).upsert(
            date: entry.dayStart,
            summary: scoreSummary,
            persona: dailyPersona,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration
        )
    }
}

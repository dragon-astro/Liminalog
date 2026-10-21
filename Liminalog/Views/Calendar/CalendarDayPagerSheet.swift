import SwiftUI
import SwiftData

struct CalendarDayPagerSheet: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let highlightedPlanID: UUID?
    let mode: CalendarExpandedDayMode

    @State private var scrolledOffset: Int? = 0
    @State private var visibleHour = 8
    @State private var selectedCategoryID: UUID?
    @State private var isScheduleInteractionActive = false
    @State private var pendingCreateDate: Date
    @State private var pendingPlanStartsAsAllDay = false
    @State private var showingPlanSheet = false
    @State private var showingPresetSheet = false
    @State private var operationError: String?
    private let pageOffsets = Array(-240...240)

    init(initialDate: Date, highlightedPlanID: UUID?, mode: CalendarExpandedDayMode = .summary) {
        self.initialDate = Calendar.japanese.startOfDay(for: initialDate)
        self.highlightedPlanID = highlightedPlanID
        self.mode = mode
        _pendingCreateDate = State(initialValue: Calendar.japanese.startOfDay(for: initialDate))
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .timeline {
                CalendarExpandedDayTimeline(
                    initialDate: initialDate,
                    scrolledOffset: $scrolledOffset,
                    visibleHour: $visibleHour,
                    selectedCategoryID: $selectedCategoryID,
                    isScheduleInteractionActive: $isScheduleInteractionActive
                )
            } else {
                summaryPager
            }
        }
        .navigationBarBackButtonHidden()
        #if DEBUG || LIMINALOG_UI_TESTING
        .background {
            if CalendarExpandedDayDiagnostics.isEnabled {
                CalendarExpandedDayPresentationProbe()
            }
        }
        .onAppear { CalendarExpandedDayDiagnostics.contentAppeared() }
        #endif
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isScheduleInteractionActive)
        .toolbar {
            if mode == .timeline {
                ToolbarItem(placement: .principal) {
                    Text(currentDate.japaneseMonthDayShortWeekday)
                        .font(.headline)
                        .accessibilityIdentifier("calendar-expanded-day-date")
                        .accessibilityValue(DailyCardSnapshot.dayIdentifier(for: currentDate, calendar: .japanese))
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    LiminalHaptics.lightImpact(intensity: 0.45)
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("calendar-expanded-day-back")
                .disabled(isScheduleInteractionActive)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    if mode == .summary {
                        dayVisibilityMenu
                        SummaryPresetToolbarButton { showingPresetSheet = true }
                    }
                    if canCreatePlansForDay {
                        Button {
                            LiminalHaptics.openSheet()
                            preparePlanCreation()
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(LiminalTheme.accent)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("予定を追加")
                        .disabled(isScheduleInteractionActive)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsAllDay)
        }
        .sheet(isPresented: $showingPresetSheet) {
            CalendarPresetSheet(targetDate: currentDate)
        }
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var summaryPager: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(pageOffsets, id: \.self) { offset in
                        // Defer each day's queries and content until its page is laid out.
                        // Resolving the initial scroll target must only inspect page shells.
                        GeometryReader { _ in
                            CalendarDayView(
                                date: pageDate(offset),
                                highlightedPlanID: highlightedPlanID(for: pageDate(offset)),
                                showsNavigationControls: false,
                                allowsDayNavigation: false
                            )
                        }
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(offset != currentOffset)
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledOffset, anchor: .center)
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .contentShape(Rectangle())
            .frame(maxHeight: .infinity)
            .onAppear {
                scrollProxy.scrollTo(currentOffset, anchor: .center)
            }
        }
    }

    private var currentOffset: Int {
        scrolledOffset ?? 0
    }

    private var currentDate: Date {
        pageDate(currentOffset)
    }

    private func pageDate(_ offset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: offset, to: initialDate) ?? initialDate
    }

    private func highlightedPlanID(for date: Date) -> UUID? {
        Calendar.japanese.isDate(date, inSameDayAs: initialDate) ? highlightedPlanID : nil
    }

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
            }
        }
    }

    private var dayVisibilityMenu: some View {
        let visibleDayChapters = dayChapters
        let allPublic = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy(\.isPublic)
        let allPrivate = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy { !$0.isPublic }
        let isMixed = !visibleDayChapters.isEmpty && !allPublic && !allPrivate

        return Menu {
            if visibleDayChapters.isEmpty {
                Text("この日にチャプターはありません")
            } else {
                if isMixed {
                    Text("公開/非公開が混在しています")
                        .font(.caption)
                }
                Button {
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: true) else {
                        LiminalHaptics.failure()
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                    LiminalHaptics.selection()
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: false) else {
                        LiminalHaptics.failure()
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                    LiminalHaptics.selection()
                } label: {
                    Label("すべて非公開", systemImage: "eye.slash")
                }
                .disabled(allPrivate)

                Divider()
                Text("\(visibleDayChapters.count)件のチャプター")
                    .font(.caption)
            }
        } label: {
            Image(systemName: allPrivate ? "eye.slash" : (isMixed ? "eye.fill" : "eye"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(LiminalTheme.accent)
        }
        .accessibilityLabel("この日の公開設定")
    }

    private var dayChapters: [Chapter] {
        let boundary = DayBoundary(date: currentDate, calendar: .japanese)
        return ScoreSnapshotLoader.chapters(
            in: DateInterval(start: boundary.dayStart, end: boundary.dayEnd),
            modelContext: modelContext,
            now: Date(),
            calendar: .japanese
        )
    }

    private var canCreateTimedPlansForDay: Bool {
        store.canCreatePlan(startTime: currentDate, isAllDay: false)
    }

    private var canCreatePlansForDay: Bool {
        true
    }

    private func preparePlanCreation() {
        guard let preset = CalendarPlanCreationPreset.make(
            for: currentDate,
            canCreateTimedPlan: canCreateTimedPlansForDay, includesMemos: true
        ) else { return }
        pendingCreateDate = preset.initialDate
        pendingPlanStartsAsAllDay = preset.startsAsAllDay
        showingPlanSheet = true
    }
}
